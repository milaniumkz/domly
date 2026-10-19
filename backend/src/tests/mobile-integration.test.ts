import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import express from 'express';
import { AddressInfo } from 'node:net';
import { Database } from '../infrastructure/db/Database';
import { mobileRouter } from '../http/routes/mobile';
import { errorHandler } from '../common/api';
import { signAccessToken } from '../common/auth';
import { packageQuote } from '../modules/packageQuote';
import { updateOrderAddons } from '../modules/orderAddons';
import { qualifyReferral } from '../modules/referrals';

test('mobile backend persistence, permissions, pricing and account lifecycle', {skip: !process.env.DOMLY_INTEGRATION_DATABASE_URL}, async t => {
  const db = new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const customer = randomUUID(), inviter = randomUUID(), admin = randomUUID();
  const house = randomUUID(), pkg = randomUUID(), addon = randomUUID(), cp = randomUUID(), payment = randomUUID(), video = randomUUID(), order = randomUUID();
  const app = express();
  app.use(express.json(), mobileRouter(db), errorHandler);
  const server = app.listen(0, '127.0.0.1');
  await new Promise<void>(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const token = (id: string, role: 'customer'|'admin') => signAccessToken({id,role,phone: `test-${id}`});
  async function request(path: string, method='GET', body?: object, id=customer, role: 'customer'|'admin'='customer') {
    const response = await fetch(base+path, {method, headers: {'Authorization': `Bearer ${token(id,role)}`, 'Content-Type':'application/json'}, body: body ? JSON.stringify(body) : undefined});
    return {status: response.status, json: await response.json() as any};
  }
  try {
    for (const [id,role] of [[customer,'customer'],[inviter,'customer'],[admin,'admin']]) {
      await db.query('INSERT INTO app_users (id,phone,role) VALUES ($1,$2,$3)', [id,`test-${id}`,role]);
    }
    await db.query("INSERT INTO connected_houses (id,city,street_ru,house,active) VALUES ($1,'Астана','Тестовая','1',FALSE)", [house]);
    await db.query("INSERT INTO catalog_packages (id,name_ru,cleaning_count,months,base_price,price_per_m2) VALUES ($1,'Тест',2,3,100,10)", [pkg]);
    await db.query("INSERT INTO catalog_addons (id,title_ru,price) VALUES ($1,'Тестовый доп',25)", [addon]);
    await t.test('waitlist persists and deduplicates joins', async () => {
      for (let i=0;i<2;i++) assert.equal((await request(`/geo/houses/${house}/waitlist`,'POST',{})).status,200);
      const rows = await request(`/geo/houses/${house}/waitlist`);
      assert.equal(rows.json.data.length,1);
      assert.equal((await request(`/geo/houses/${house}/stats`)).json.data.house.current_users,1);
      assert.equal((await request(`/geo/houses/${house}/waitlist`,'GET',undefined,inviter)).json.data.length,0);
    });
    await t.test('referrals reject self codes and persist one inviter', async () => {
      const own = await request('/referrals');
      assert.equal((await request('/referrals','POST',{code:own.json.data.referralCode})).status,400);
      const ref = await request('/referrals','GET',undefined,inviter);
      assert.equal((await request('/referrals','POST',{code:ref.json.data.referralCode})).status,200);
      assert.equal((await request('/referrals')).json.data.referredByCode,ref.json.data.referralCode);
    });
    await t.test('video catalogue reflects admin updates and rejects customer writes', async () => {
      assert.equal((await request('/admin/videos','POST',{id:video,title:'Видео',url:'https://example.com/video',audienceType:'client'})).status,403);
      assert.equal((await request('/admin/videos','POST',{id:video,title:'Видео',url:'https://example.com/video',audienceType:'client'},admin,'admin')).status,200);
      const detail = (await request(`/training/videos/${video}`)).json.data;
      assert.equal(detail.url,'https://example.com/video');
      assert.equal(detail.videoUrl,'https://example.com/video');
      assert.ok((await request('/training/videos?audience=client')).json.data.some((row: any)=>row.id===video));
      assert.ok(!(await request('/training/videos?audience=cleaner')).json.data.some((row: any)=>row.id===video));
    });
    await t.test('server prices package and addons from database, ignoring client amount', async () => {
      const quote = await packageQuote(db,{packageId:pkg,area:50,amount:1,addonsDetailed:[{key:addon,quantity:2,price:1}]});
      assert.equal(quote.cleaningCount,6);
      assert.equal(quote.monthlyPrice,3650);
      await assert.rejects(packageQuote(db,{packageId:pkg,area:50,addonsDetailed:[{key:addon,quantity:-1}]}));
    });
    await t.test('referral reward is credited once for repeated payment application', async () => {
      await db.query('INSERT INTO customer_packages (id,customer_id,package_id,total_cleanings,available_cleanings) VALUES ($1,$2,$3,2,2)', [cp,customer,pkg]);
      await db.query("INSERT INTO payments (id,customer_id,customer_package_id,provider,status,amount) VALUES ($1,$2,$3,'manual','paid',100)", [payment,customer,cp]);
      for(let i=0;i<2;i++) await qualifyReferral(db,{id:payment,customer_id:customer,customer_package_id:cp});
      const balance = (await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[inviter])).rows[0];
      assert.equal(Number(balance.bonus_balance),2000);
      assert.equal((await request('/referrals','GET',undefined,inviter)).json.data.paid,1);
    });
    await t.test('addon edits persist server prices and protect paid quantities', async () => {
      await db.query("INSERT INTO service_orders (id,customer_id,customer_package_id,package_id,scheduled_date,start_time,end_time,estimated_duration_minutes,status) VALUES ($1,$2,$3,$4,CURRENT_DATE+1,'10:00','12:00',120,'pending_assignment')",[order,customer,cp,pkg]);
      const result=await updateOrderAddons(db,order,customer,[{key:addon,quantity:2,price:1}]);
      assert.equal(result.payableAmount,50);
      assert.equal((await request(`/orders/${order}/addons`,'POST',{addonsDetailed:[{key:addon,quantity:2}]},inviter)).status,404);
      await db.query("UPDATE order_addons SET payment_status='paid' WHERE order_id=$1",[order]);
      await assert.rejects(updateOrderAddons(db,order,customer,[]));
      assert.equal((await db.query('SELECT quantity FROM order_addons WHERE order_id=$1',[order])).rows[0].quantity,'2.00');
    });
    await t.test('account with an active order cannot be deleted',async()=>{
      assert.equal((await request('/me','DELETE')).status,409);
      await db.query("UPDATE service_orders SET status='completed' WHERE id=$1",[order]);
    });
    await t.test('account deletion revokes access and anonymizes identity', async () => {
      assert.equal((await request('/me','DELETE')).status,200);
      assert.equal((await request('/referrals')).status,401);
      const user=(await db.query('SELECT phone,deleted_at FROM app_users WHERE id=$1',[customer])).rows[0];
      assert.ok(user.deleted_at);
      assert.ok(user.phone.startsWith('deleted-'));
    });
  } finally {
    await new Promise<void>((resolve,reject)=>server.close(error=>error?reject(error):resolve()));
    await db.query('DELETE FROM bonus_transactions WHERE payment_id=$1',[payment]);
    await db.query('DELETE FROM payments WHERE id=$1',[payment]);
    await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
    await db.query('DELETE FROM customer_packages WHERE id=$1',[cp]);
    await db.query('DELETE FROM user_referrals WHERE customer_id=$1',[customer]);
    await db.query('DELETE FROM house_waitlist WHERE house_id=$1',[house]);
    await db.query('DELETE FROM connected_houses WHERE id=$1',[house]);
    await db.query('DELETE FROM training_videos WHERE id=$1',[video]);
    await db.query('DELETE FROM catalog_addons WHERE id=$1',[addon]);
    await db.query('DELETE FROM catalog_packages WHERE id=$1',[pkg]);
    await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[customer,inviter,admin]]);
    await db.close();
  }
});

test('temporary delivery fallback completes backend login and the code is single-use', {skip: !process.env.DOMLY_INTEGRATION_DATABASE_URL}, async () => {
  const {AuthService} = await import('../modules/domainServices');
  const {env} = await import('../common/env');
  const {ApiError} = await import('../common/api');
  const {randomInt} = await import('node:crypto');
  const db = new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const id=randomUUID(), phone='+7700'+randomInt(1000000,10000000);
  const original=env.otpFailureFallbackUntil;
  try {
    await db.query("INSERT INTO app_users (id,phone,role) VALUES ($1,$2,'customer')",[id,phone]);
    env.otpFailureFallbackUntil=new Date(Date.now()+60000).toISOString();
    const service=new AuthService(db,{sendOtp:async()=>{throw new ApiError(503,'integration_error','Provider unavailable');}} as any);
    const sent=await service.requestOtp(phone);
    const session=await service.verifyOtp(phone,sent.fallbackCode!);
    assert.equal(session.user.id,id);
    assert.equal(session.user.role,'customer');
    assert.ok(session.accessToken);
    assert.ok(session.refreshToken);
    await assert.rejects(()=>service.verifyOtp(phone,sent.fallbackCode!),(e:any)=>e.code==='invalid_otp');
  } finally {
    env.otpFailureFallbackUntil=original;
    await db.query('DELETE FROM refresh_sessions WHERE user_id=$1',[id]);
    await db.query('DELETE FROM auth_otp_codes WHERE phone=$1',[phone]);
    await db.query('DELETE FROM app_users WHERE id=$1',[id]);
    await db.close();
  }
});

test('Moon AI invoices, signed events, guest isolation and thirty-minute campaigns', {skip: !process.env.DOMLY_INTEGRATION_DATABASE_URL}, async t => {
  const {env}=await import('../common/env');
  const {ensureAssistantChat,queueMoonInvoice,scheduleCheckoutFollowup,scheduleSignupFollowup,processMoonOutbox,
    acceptMoonChatEvent,acceptMoonPaymentStatus,matchMoonPaymentStatus,ensureGuestSession,guestSession,bindGuestSession,queueAssistantMessage}=await import('../modules/moonAi');
  const {sendMessengerFollowup}=await import('../modules/moonMessenger');
  const previous={moonAiEnabled:env.moonAiEnabled,moonAiChannelUrl:env.moonAiChannelUrl,moonAiChannelApiKey:env.moonAiChannelApiKey,moonAiWebhookToken:env.moonAiWebhookToken,moonAiSource:env.moonAiSource,
    moonAiRestApiKey:env.moonAiRestApiKey,moonAiOrganizationId:env.moonAiOrganizationId,moonAiAgentId:env.moonAiAgentId,moonAiWabaChannelId:env.moonAiWabaChannelId,moonAiWabaTemplateId:env.moonAiWabaTemplateId};
  Object.assign(env,{moonAiEnabled:true,moonAiChannelUrl:'https://core.mooonai.com/api/v1/channels/api/messages',moonAiChannelApiKey:'fixture-channel-key',moonAiWebhookToken:'fixture-hook-key',moonAiSource:'domly',
    moonAiRestApiKey:'fixture-rest-key',moonAiOrganizationId:'4649',moonAiAgentId:'6875',moonAiWabaChannelId:'7787',moonAiWabaTemplateId:'215'});
  const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const user=randomUUID(),stranger=randomUUID(),idle=randomUUID(),paymentId=randomUUID();
  const keys=['a'.repeat(64),'b'.repeat(64)];
  const sent:any[]=[];
  const send=(async (_url:any,init:any)=>{
    assert.equal(init.headers['X-API-Key'],'fixture-channel-key');
    const body=JSON.parse(init.body);sent.push(body);
    assert.deepEqual(Object.keys(body).sort(),['data','from_type','message_type','source','thread_id']);
    return new Response(JSON.stringify({accepted:true,thread_id:`api:${body.source}:${body.thread_id}`,external_thread_id:body.thread_id,source:'domly'}),{status:200});
  }) as typeof fetch;
  let chatId='';
  try {
    for(const id of [user,stranger,idle])await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[id,'+7'+id.replace(/\D/g,'').padEnd(10,'0').slice(0,10)]);
    await t.test('one private assistant chat survives concurrent creation',async()=>{
      const chats=await Promise.all(Array.from({length:5},()=>ensureAssistantChat(db,user)));
      chatId=chats[0].id;assert.equal(new Set(chats.map(c=>c.id)).size,1);
      assert.deepEqual((await db.query('SELECT user_id FROM chat_participants WHERE chat_id=$1',[chatId])).rows.map(r=>r.user_id),[user]);
    });
    await db.query("INSERT INTO payments(id,customer_id,provider,status,amount,invoice_phone) VALUES($1,$2,'kaspi','pending',22000,'+77000000000')",[paymentId,user]);
    const payment=(await db.query('SELECT * FROM payments WHERE id=$1',[paymentId])).rows[0];
    await t.test('invoice request is deduplicated and uses server quote and phone',async()=>{
      for(let i=0;i<3;i++)await queueMoonInvoice(db,payment,'Уборка');
      assert.equal((await db.query("SELECT COUNT(*)::int AS n FROM moon_ai_outbox WHERE payment_id=$1 AND kind='invoice'",[paymentId])).rows[0].n,1);
      await assert.rejects(queueMoonInvoice(db,{...payment,invoice_phone:'123'},'Bad'));
      await processMoonOutbox(db,send);assert.equal(sent.length,1);
      assert.notEqual(sent[0].thread_id,paymentId);assert.equal(sent[0].data.text.includes('paymentId='),false);assert.equal(sent[0].source,'domly_invoice');assert.equal(sent[0].from_type,'user');
      assert.ok(sent[0].data.text.includes('payment_sum=22000'));assert.ok(sent[0].data.text.includes('phone_number=77000000000'));
      await processMoonOutbox(db,send);assert.equal(sent.length,1);
    });
    await t.test('abandoned checkout runs after thirty minutes and is cancelled on payment',async()=>{
      await scheduleCheckoutFollowup(db,payment);
      const reminder=(await db.query("SELECT EXTRACT(EPOCH FROM run_after-created_at)::int AS delay FROM moon_ai_outbox WHERE payment_id=$1 AND kind='abandoned_checkout'",[paymentId])).rows[0];
      assert.equal(reminder.delay,1800);
      await processMoonOutbox(db,send);assert.equal(sent.length,1);
    });
    const paid={key:paymentId,status:'paid',amount:22000,phone:'+77000000000',externalId:'moon-invoice-fixture',eventId:randomUUID(),eventTime:new Date().toISOString(),payload:{test:true}};
    await t.test('amount and phone must match before payment is activated',async()=>{
      await assert.rejects(acceptMoonPaymentStatus(db,{...paid,amount:1}));
      await assert.rejects(acceptMoonPaymentStatus(db,{...paid,phone:'+77000000001'}));
      assert.equal((await db.query('SELECT status FROM payments WHERE id=$1',[paymentId])).rows[0].status,'invoice_requested');
      const result=await acceptMoonPaymentStatus(db,paid);assert.equal(result.status,'paid');
      assert.equal((await db.query("SELECT state FROM moon_ai_outbox WHERE payment_id=$1 AND kind='abandoned_checkout'",[paymentId])).rows[0].state,'cancelled');
      await acceptMoonPaymentStatus(db,paid);
      const late=await acceptMoonPaymentStatus(db,{...paid,status:'pending',eventId:randomUUID()});assert.equal(late.status,'paid');
      assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM payment_events WHERE payment_id=$1',[paymentId])).rows[0].n,2);
    });
    await t.test('automatic and manual approval provenance survives repeat callbacks', async () => {
      const {PaymentService, BonusService} = await import('../modules/domainServices');
      const service = new PaymentService(db, new BonusService(db));
      await service.markPaid(paymentId, stranger);
      const automatic = (await db.query('SELECT approval_source,approved_by,approved_at FROM payments WHERE id=$1', [paymentId])).rows[0];
      assert.equal(automatic.approval_source, 'moon_ai');
      assert.equal(automatic.approved_by, null);
      assert.ok(automatic.approved_at);
      const manualId = randomUUID();
      await db.query("INSERT INTO payments(id,customer_id,provider,status,amount,invoice_phone) VALUES($1,$2,'kaspi','invoice_requested',22000,'+77000000000')", [manualId,user]);
      await service.markPaid(manualId, stranger);
      const before = (await db.query('SELECT approval_source,approved_by,approved_at FROM payments WHERE id=$1', [manualId])).rows[0];
      assert.equal(before.approval_source, 'manual');
      assert.equal(before.approved_by, stranger);
      await acceptMoonPaymentStatus(db, {...paid,key:manualId,externalId:'manual-invoice-fixture',eventId:randomUUID()});
      await service.markPaid(manualId, user);
      const after = (await db.query('SELECT approval_source,approved_by,approved_at FROM payments WHERE id=$1', [manualId])).rows[0];
      assert.deepEqual(after, before);
    });
    await t.test('ID-free callbacks match phone, amount and original event time', async () => {
      const id=randomUUID(),requestTime=new Date(Date.now()-120000).toISOString(),eventTime=new Date(Date.now()-60000).toISOString();
      await db.query("INSERT INTO payments(id,customer_id,provider,status,amount,invoice_phone,invoice_requested_at) VALUES($1,$2,'kaspi','invoice_requested',99101,'+77000000000',$3)",[id,user,requestTime]);
      const invoice={phone:'+7 (700) 000-00-00',amount:99101,status:'invoice_sent' as const,dateTime:eventTime};
      const sent=await matchMoonPaymentStatus(db,invoice);
      assert.equal(sent.resolution,'matched');assert.equal(sent.payment?.id,id);assert.equal(sent.payment?.status,'invoice_requested');
      assert.equal(sent.payment?.payload.moonAi.status,'invoice_sent');
      const paid={...invoice,status:'paid' as const,dateTime:new Date(Date.now()-30000).toISOString()};
      const concurrent=await Promise.all([matchMoonPaymentStatus(db,paid),matchMoonPaymentStatus(db,paid)]);
      assert.equal(concurrent.filter(r=>r.duplicate).length,1);
      assert.equal(concurrent[0].payment?.approval_source,'moon_ai');
      const futureId=randomUUID();await db.query("INSERT INTO payments(id,customer_id,provider,status,amount,invoice_phone,invoice_requested_at) VALUES($1,$2,'kaspi','invoice_requested',99101,'+77000000000',NOW())",[futureId,user]);
      const retry=await matchMoonPaymentStatus(db,paid);assert.equal(retry.payment?.id,id);
      assert.equal((await db.query('SELECT status FROM payments WHERE id=$1',[futureId])).rows[0].status,'invoice_requested');
      await assert.rejects(matchMoonPaymentStatus(db,{...paid,dateTime:''}));
      await assert.rejects(matchMoonPaymentStatus(db,{...paid,phone:'123'}));
      await assert.rejects(matchMoonPaymentStatus(db,{...paid,amount:NaN}));
      const noMatch=await matchMoonPaymentStatus(db,{...paid,amount:99102});assert.equal(noMatch.resolution,'not_found');assert.equal(noMatch.payment,null);
    });
    await t.test('ambiguous phone/amount callbacks never confirm either payment', async () => {
      const ids=[randomUUID(),randomUUID()],dateTime=new Date(Date.now()-30000).toISOString();
      for(const id of ids) await db.query("INSERT INTO payments(id,customer_id,provider,status,amount,invoice_phone,invoice_requested_at) VALUES($1,$2,'kaspi','invoice_requested',99103,'+77000000000',NOW()-INTERVAL '2 minutes')",[id,user]);
      const result=await matchMoonPaymentStatus(db,{phone:'+77000000000',amount:99103,status:'paid',dateTime});
      assert.equal(result.resolution,'ambiguous');assert.equal(result.payment,null);assert.equal(result.candidateIds.length,2);
      const rows=(await db.query('SELECT status,payload FROM payments WHERE id=ANY($1::uuid[])',[ids])).rows;
      for(const row of rows){assert.equal(row.status,'invoice_requested');assert.equal(row.payload.moonAiReview.reason,'ambiguous');}
    });
    await t.test('ID-free rejection, cancellation and manual confirmation keep their meaning', async () => {
      const {PaymentService,BonusService}=await import('../modules/domainServices');
      const service=new PaymentService(db,new BonusService(db));
      const dateTime=new Date(Date.now()-30000).toISOString();
      for(const [amount,status] of [[99104,'rejected'],[99105,'cancelled']] as const){
        const id=randomUUID();await db.query("INSERT INTO payments(id,customer_id,provider,status,amount,invoice_phone,invoice_requested_at) VALUES($1,$2,'kaspi','invoice_requested',$3,'+77000000000',NOW()-INTERVAL '2 minutes')",[id,user,amount]);
        const result=await matchMoonPaymentStatus(db,{phone:'+77000000000',amount,status,dateTime});assert.equal(result.payment?.status,status);
        if(status==='rejected'){
          await service.markPaid(id,stranger);
          const bank=await matchMoonPaymentStatus(db,{phone:'+77000000000',amount,status:'paid',dateTime:new Date(Date.now()-15000).toISOString()});
          assert.equal(bank.payment?.approval_source,'manual');assert.equal(bank.payment?.approved_by,stranger);
        } else {
          const late=await matchMoonPaymentStatus(db,{phone:'+77000000000',amount,status:'paid',dateTime:new Date(Date.now()-15000).toISOString()});
          assert.equal(late.payment?.status,'cancelled');
        }
      }
    });
    await t.test('assistant replies are stored once and notified only to the owner',async()=>{
      const events=new Map<string,any>();
      const notifications={create:async(input:any)=>{events.set(input.dedupeKey,input);}};
      const event={event_id:randomUUID(),event_type:'agent_message',source:'domly',external_thread_id:`assistant:${chatId}`,thread_id:`api:domly:assistant:${chatId}`,message:{data:{text:'Здравствуйте!'}}};
      assert.equal((await acceptMoonChatEvent(db,notifications,event)).ignored,true);
      await queueAssistantMessage(db,chatId,user,randomUUID(),'Помоги выбрать уборку');
      await processMoonOutbox(db,send);
      assert.equal(sent.at(-1).thread_id,`assistant:${chatId}`);
      assert.equal((await acceptMoonChatEvent(db,notifications,event)).duplicate,false);
      assert.equal((await acceptMoonChatEvent(db,notifications,event)).duplicate,true);
      assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM chat_messages WHERE chat_id=$1',[chatId])).rows[0].n,1);
      assert.equal(events.size,1);assert.equal([...events.values()][0].userId,user);assert.equal([...events.values()][0].targetType,'assistant_chat');
      await assert.rejects(acceptMoonChatEvent(db,notifications,{...event,source:'foreign'}));
      const ignored=await acceptMoonChatEvent(db,notifications,{...event,event_type:'user_message'});assert.equal(ignored.ignored,true);
      assert.equal((await acceptMoonChatEvent(db,notifications,{...event,event_id:randomUUID()})).ignored,true);
      assert.equal((await acceptMoonChatEvent(db,notifications,{...event,event_id:randomUUID(),external_thread_id:chatId,thread_id:`api:domly:${chatId}`})).ignored,true);
      assert.equal(events.size,1);
    });
    await t.test('new registered customer gets a single thirty-minute WhatsApp welcome, never an app message',async()=>{
      await scheduleSignupFollowup(db,idle);await scheduleSignupFollowup(db,idle);
      const rows=(await db.query("SELECT *,EXTRACT(EPOCH FROM run_after-created_at)::int AS delay FROM moon_ai_outbox WHERE customer_id=$1 AND kind='inactive_signup'",[idle])).rows;
      assert.equal(rows.length,1);assert.equal(rows[0].delay,1800);
      await db.query("UPDATE moon_ai_outbox SET run_after=NOW()-INTERVAL '1 second' WHERE id=$1",[rows[0].id]);
      const nativeCalls:any[]=[];
      const nativeSend=(async(url:any,init:any)=>{
        assert.equal(init.headers.Authorization,'Bearer fixture-rest-key');
        const path=new URL(url).pathname;nativeCalls.push({path,body:init.body?JSON.parse(init.body):null});
        const result=path.endsWith('/threads')?{results:[]}:path.endsWith('/whatsapp-templates')?{templates:[{id:215,status:'APPROVED'}]}:
          {thread_id:'native-waba-thread',delivery_status:'enqueued'};
        return new Response(JSON.stringify(result),{status:200});
      }) as typeof fetch;
      await processMoonOutbox(db,nativeSend);
      assert.equal(nativeCalls.length,4);
      assert.match(nativeCalls.at(-2).path,/channels\/7787\/whatsapp-chat\/initiate$/);
      assert.equal(nativeCalls.at(-2).body.template_id,215);
      assert.equal(nativeCalls.at(-2).body.phone,(await db.query('SELECT phone FROM app_users WHERE id=$1',[idle])).rows[0].phone);
      assert.equal(nativeCalls.at(-1).body.status,'active');
      await processMoonOutbox(db,nativeSend);assert.equal(nativeCalls.length,4);
      assert.equal((await db.query("SELECT provider_thread_id FROM moon_ai_outbox WHERE id=$1",[rows[0].id])).rows[0].provider_thread_id,'native-waba-thread');
      assert.equal(Number((await db.query("SELECT COUNT(*) AS n FROM chat_messages m JOIN chats c ON c.id=m.chat_id WHERE c.customer_id=$1",[idle])).rows[0].n),0);
    });
    await t.test('bot conversations use only WABA and ignore grey WhatsApp threads',async()=>{
      for(const channel of ['whatsapp','whatsapp_business']) {
        for(const activeWindow of [true,false]) {
          const calls:any[]=[];
          const transport=(async(url:any,init:any)=>{
            const path=new URL(url).pathname;calls.push({path,body:init.body?JSON.parse(init.body):null});
            const result=path.endsWith('/threads')?{results:[{id:'native-thread',channel_type:channel,status:'active',metadata:{phone_number:'77000000000'},free_form_window_expires_at:activeWindow?new Date(Date.now()+3600000).toISOString():null}]}:
              path.endsWith('/whatsapp-templates')?{templates:[{id:215,status:'APPROVED'}]}:path.endsWith('/messages')?{id:41}:{thread_id:'native-thread',delivery_status:'enqueued'};
            return new Response(JSON.stringify(result),{status:200});
          }) as typeof fetch;
          await sendMessengerFollowup({id:randomUUID(),kind:'abandoned_checkout',text:'Помоги клиенту завершить оформление, без нового счёта.',phone:'+77000000000'},transport);
          const last=calls.at(-2);
          if(channel==='whatsapp'){assert.match(last.path,/\/channels\/7787\/whatsapp-chat\/initiate$/);}
          else if(activeWindow){assert.match(last.path,/\/messages$/);assert.equal(last.body.from_type,'manager');assert.equal(last.body.data.text.includes('Служебное событие'),false);}
          else {assert.match(last.path,/\/whatsapp-template$/);assert.equal(last.body.template_id,215);}
          assert.equal(calls.some(call=>call.path.includes('/channels/api/')),false);
          assert.match(calls.at(-1).path,/\/status$/);assert.equal(calls.at(-1).body.status,'active');
        }
      }
      let pausedCalls=0;
      const paused=(async()=>{pausedCalls++;return new Response(JSON.stringify({results:[{id:'paused-native',channel_type:'whatsapp_business',status:'paused',metadata:{phone_number:'77000000000'}}]}),{status:200});}) as typeof fetch;
      await assert.rejects(sendMessengerFollowup({id:randomUUID(),kind:'inactive_signup',text:'Помоги.',phone:'+77000000000'},paused),/WhatsApp/);
      assert.equal(pausedCalls,1,'A manager pause must not be bypassed by starting another conversation');
    });
    await t.test('first-open guest sessions are private, idempotent and expire on account binding',async()=>{
      const a=await ensureGuestSession(db,keys[0]),again=await ensureGuestSession(db,keys[0]),b=await ensureGuestSession(db,keys[1]);
      assert.equal(a.chatId,again.chatId);assert.notEqual(a.chatId,b.chatId);
      const guest=await guestSession(db,keys[0]);assert.equal(guest.chat_id,a.chatId);
      const reminders=(await db.query("SELECT EXTRACT(EPOCH FROM run_after-created_at)::int AS delay FROM moon_ai_outbox WHERE installation_id=$1 AND kind='inactive_install'",[guest.id])).rows;
      assert.equal(reminders.length,0);
      await assert.rejects(guestSession(db,'c'.repeat(64)));
      await bindGuestSession(db,keys[0],user);
      await assert.rejects(guestSession(db,keys[0]));
      assert.equal((await db.query("SELECT 1 FROM moon_ai_outbox WHERE installation_id=$1 AND state='pending'",[guest.id])).rows.length,0);
      await assert.rejects(bindGuestSession(db,keys[0],stranger));
    });
    await t.test('unknown network delivery is never retried into duplicate invoices',async()=>{
      const id=randomUUID();await db.query("INSERT INTO payments(id,customer_id,provider,status,amount,invoice_phone) VALUES($1,$2,'kaspi','pending',100,'+77000000000')",[id,user]);
      const p=(await db.query('SELECT * FROM payments WHERE id=$1',[id])).rows[0];await queueMoonInvoice(db,p,'Retry');
      let calls=0;const failing=(async()=>{calls++;throw new Error('timeout');}) as typeof fetch;
      await processMoonOutbox(db,failing);await processMoonOutbox(db,failing);
      assert.equal(calls,1);assert.equal((await db.query("SELECT state FROM moon_ai_outbox WHERE payment_id=$1 AND kind='invoice'",[id])).rows[0].state,'uncertain');
    });
    await t.test('HTTP endpoints reject foreign users and isolate guest sessions',async()=>{
      const {buildV1Router}=await import('../http/routes/v1');
      const {PaymentService,BonusService}=await import('../modules/domainServices');
      const realPayments=new PaymentService(db,new BonusService(db));
      const httpNotifications=new Map<string,any>();
      const app=express();app.use(express.json(),buildV1Router({db,payments:realPayments,notifications:{create:async(input:any)=>{httpNotifications.set(input.dedupeKey,input);},createAdminEvent:async()=>{}}} as any),errorHandler);
      const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
      const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
      try {
        const jwt=signAccessToken({id:user,role:'customer',phone:'fixture'});
        const other=signAccessToken({id:stranger,role:'customer',phone:'fixture'});
        assert.equal((await fetch(base+`/chats/${chatId}/messages`,{headers:{Authorization:'Bearer '+other}})).status,403);
        assert.equal((await fetch(base+`/payments/${paymentId}/kaspi-invoice`,{method:'POST',headers:{Authorization:'Bearer '+other,'Content-Type':'application/json'},body:JSON.stringify({invoicePhone:'+77000000000'})})).status,404);
        const own=await fetch(base+`/chats/${chatId}/messages`,{headers:{Authorization:'Bearer '+jwt}});
        assert.equal(own.status,200);assert.equal((await own.json() as any).data[0].sender_kind,'assistant');
        assert.equal((await fetch(base+'/assistant/guest/messages')).status,401);
        assert.equal((await fetch(base+'/assistant/guest/messages',{headers:{'X-Assistant-Session':keys[0]}})).status,401);
        assert.equal((await fetch(base+'/assistant/guest/messages',{headers:{'X-Assistant-Session':keys[1]}})).status,200);
        const sent=await fetch(base+'/assistant/guest/messages',{method:'POST',headers:{'X-Assistant-Session':keys[1],'Content-Type':'application/json'},body:JSON.stringify({message:'Привет'})});
        assert.equal(sent.status,201);
        const pkg=randomUUID(),address=randomUUID();
        try {
          await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,base_price,price_per_m2,months) VALUES($1,'HTTP purchase regression',1,0,220,1)",[pkg]);
          await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area) VALUES($1,$2,'Астана','Тестовая','1',100)",[address,stranger]);
          const purchase=await fetch(base+'/packages/purchase',{method:'POST',headers:{Authorization:'Bearer '+other,'Content-Type':'application/json'},body:JSON.stringify({packageId:pkg,addressId:address,provider:'kaspi'})});
          const body=await purchase.json() as any;assert.equal(purchase.status,200,JSON.stringify(body));
          assert.equal(body.data.customerPackage.status,'pending_payment');assert.equal(body.data.payment.status,'pending');assert.equal(Number(body.data.payment.amount),22000);
          assert.equal(body.data.payment.approval_source,null);assert.equal(body.data.payment.paid_at,null);
          const invoiced=await fetch(base+'/packages/purchase',{method:'POST',headers:{Authorization:'Bearer '+other,'Content-Type':'application/json'},body:JSON.stringify({packageId:pkg,addressId:address,provider:'kaspi',invoicePhone:'+77000000000'})});
          const invoiceBody=await invoiced.json() as any;assert.equal(invoiced.status,200,JSON.stringify(invoiceBody));
          assert.equal((await db.query('SELECT status FROM payments WHERE id=$1',[invoiceBody.data.payment.id])).rows[0].status,'invoice_requested');
          assert.equal((await db.query("SELECT COUNT(*)::int AS n FROM moon_ai_outbox WHERE payment_id=$1 AND kind='invoice'",[invoiceBody.data.payment.id])).rows[0].n,1);
          const zero=await realPayments.createPayment({customerId:stranger,amount:0,provider:'kaspi',applyReferralDiscount:false});
          const bonus=zero.payment as any;assert.equal(bonus.status,'paid');assert.equal(bonus.approval_source,'bonus');assert.ok(bonus.approved_at);assert.ok(bonus.paid_at);
        } finally {
          await db.query('DELETE FROM moon_ai_outbox WHERE payment_id IN(SELECT id FROM payments WHERE customer_package_id IN(SELECT id FROM customer_packages WHERE package_id=$1))',[pkg]);
          await db.query('DELETE FROM payments WHERE customer_package_id IN(SELECT id FROM customer_packages WHERE package_id=$1)',[pkg]);
          await db.query('DELETE FROM customer_packages WHERE package_id=$1',[pkg]);
          await db.query('DELETE FROM customer_addresses WHERE id=$1',[address]);
          await db.query('DELETE FROM catalog_packages WHERE id=$1',[pkg]);
        }
        const addonOrder=randomUUID(), addon=randomUUID();
        try {
          await db.query("INSERT INTO service_orders(id,customer_id,status,payable_amount) VALUES($1,$2,'pending_payment',1234)",[addonOrder,stranger]);
          await db.query("INSERT INTO catalog_addons(id,title_ru,price) VALUES($1,'Fixture extra',1234)",[addon]);
          await db.query("INSERT INTO order_addons(order_id,addon_id,price,payment_status) VALUES($1,$2,1234,'pending')",[addonOrder,addon]);
          const response=await fetch(base+`/orders/${addonOrder}/addon-requests/approve`,{method:'POST',headers:{Authorization:'Bearer '+other,'Content-Type':'application/json'},body:JSON.stringify({kaspiPhone:'+77000000000',paymentMethod:'kaspi'})});
          assert.equal(response.status,200);
          const result=(await response.json() as any).data;
          const saved=(await db.query('SELECT * FROM payments WHERE id=$1',[result.paymentId])).rows[0];
          assert.equal(saved.status,'invoice_requested');assert.equal(Number(saved.amount),1234);
          assert.equal((await db.query("SELECT COUNT(*)::int AS n FROM moon_ai_outbox WHERE payment_id=$1 AND kind='invoice'",[result.paymentId])).rows[0].n,1);
          assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[addonOrder])).rows[0].status,'pending_payment');
          await db.query("UPDATE payments SET status='cancelled' WHERE id=$1",[result.paymentId]);
          const retried=await fetch(base+`/orders/${addonOrder}/pay`,{method:'POST',headers:{Authorization:'Bearer '+other,'Content-Type':'application/json'},body:JSON.stringify({provider:'kaspi',invoicePhone:'+77000000000'})});
          assert.equal(retried.status,200);
          const retry=(await retried.json() as any).data.payment;
          assert.notEqual(retry.id,result.paymentId);assert.equal(Number(retry.amount),1234);
          const storedRetry=(await db.query('SELECT * FROM payments WHERE id=$1',[retry.id])).rows[0];
          assert.equal(storedRetry.payload.retryOfPaymentId,result.paymentId);
          const matched=await matchMoonPaymentStatus(db,{phone:'+77000000000',amount:1234,status:'invoice_sent',dateTime:new Date().toISOString()});
          assert.equal(matched.resolution,'matched');assert.equal(matched.payment?.id,retry.id);
          const duplicateAttempt=await fetch(base+`/orders/${addonOrder}/pay`,{method:'POST',headers:{Authorization:'Bearer '+other,'Content-Type':'application/json'},body:JSON.stringify({provider:'kaspi',invoicePhone:'+77000000001'})});
          assert.equal(duplicateAttempt.status,409);
          const paidRetry=await matchMoonPaymentStatus(db,{phone:'+77000000000',amount:1234,status:'paid',dateTime:new Date().toISOString()});
          assert.equal(paidRetry.payment?.id,retry.id);assert.equal(paidRetry.payment?.status,'paid');

        } finally {
          await db.query('DELETE FROM moon_ai_outbox WHERE payment_id IN(SELECT id FROM payments WHERE order_id=$1)',[addonOrder]);
          await db.query('DELETE FROM moon_ai_payment_callbacks WHERE payment_id IN(SELECT id FROM payments WHERE order_id=$1)',[addonOrder]);
          await db.query('DELETE FROM payment_events WHERE payment_id IN(SELECT id FROM payments WHERE order_id=$1)',[addonOrder]);
          await db.query('DELETE FROM payments WHERE order_id=$1',[addonOrder]);
          await db.query('DELETE FROM service_orders WHERE id=$1',[addonOrder]);
          await db.query('DELETE FROM catalog_addons WHERE id=$1',[addon]);
        }
        const ownedToken='moon-registered-token-fixture',guestToken='moon-guest-token-fixture';
        await db.query("INSERT INTO device_tokens(user_id,platform,token) VALUES($1,'web',$2)",[user,ownedToken]);
        const guestHeaders={'X-Assistant-Session':keys[1],'Content-Type':'application/json'};
        const protectedPush=await fetch(base+'/assistant/guest/device-token',{method:'POST',headers:guestHeaders,body:JSON.stringify({token:ownedToken})});assert.equal(protectedPush.status,200);
        assert.equal((await protectedPush.json() as any).data.saved,false);
        assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM assistant_installation_tokens WHERE token=$1',[ownedToken])).rows[0].n,0);
        assert.equal((await db.query('SELECT user_id FROM device_tokens WHERE token=$1',[ownedToken])).rows[0].user_id,user);
        assert.equal((await db.query('SELECT enabled FROM device_tokens WHERE token=$1',[ownedToken])).rows[0].enabled,true);
        const guestPush=await fetch(base+'/assistant/guest/device-token',{method:'POST',headers:guestHeaders,body:JSON.stringify({token:guestToken})});assert.equal(guestPush.status,200);
        const ownerPush=await fetch(base+'/me/device-tokens',{method:'POST',headers:{Authorization:'Bearer '+other,'Content-Type':'application/json'},body:JSON.stringify({platform:'web',token:guestToken})});assert.equal(ownerPush.status,201);
        assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM assistant_installation_tokens WHERE token=$1',[guestToken])).rows[0].n,0);
        assert.equal((await db.query('SELECT user_id FROM device_tokens WHERE token=$1',[guestToken])).rows[0].user_id,stranger);
        const id=randomUUID();await db.query("INSERT INTO payments(id,customer_id,provider,status,amount,invoice_phone,invoice_requested_at) VALUES($1,$2,'kaspi','invoice_requested',99106,'+77000000000',NOW()-INTERVAL '2 minutes')",[id,user]);
        const callback=await fetch(base+'/payments/moon-ai/kaspi-status',{method:'POST',headers:{'Content-Type':'application/json','X-MoonAI-Token':'fixture-hook-key'},body:JSON.stringify({phone:'+77000000000',amount:99106,status:'invoice_sent',dateTime:new Date(Date.now()-60000).toISOString()})});
        assert.equal(callback.status,200);assert.equal((await callback.json() as any).data.resolution,'matched');
        assert.equal(httpNotifications.size,1);assert.equal([...httpNotifications.values()][0].userId,user);assert.equal([...httpNotifications.values()][0].targetType,'payments');
        const invalid=await fetch(base+'/payments/moon-ai/kaspi-status',{method:'POST',headers:{'Content-Type':'application/json','X-MoonAI-Token':'fixture-hook-key'},body:JSON.stringify({phone:'+77000000000',amount:99106,status:'success',dateTime:new Date().toISOString()})});assert.equal(invalid.status,400);
        const unsigned=await fetch(base+'/payments/moon-ai/kaspi-status',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});assert.equal(unsigned.status,401);
        const legacy=await fetch(base+'/payments/kaspi/webhook',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({paymentId:id,status:'paid'})});assert.equal(legacy.status,409);
        assert.equal((await fetch(base+'/integrations/moon-ai/messages',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,401);
      }finally{await new Promise<void>((r,e)=>server.close(err=>err?e(err):r()));}
    });
  }finally{
    Object.assign(env,previous);
    const guests=(await db.query('SELECT id,chat_id FROM assistant_installations WHERE key_hash=ANY($1::text[])',[keys.map(k=>require('node:crypto').createHash('sha256').update(k).digest('hex'))])).rows;
    for(const g of guests){await db.query('DELETE FROM moon_ai_outbox WHERE installation_id=$1',[g.id]);await db.query('UPDATE assistant_installations SET chat_id=NULL WHERE id=$1',[g.id]);await db.query('DELETE FROM chats WHERE id=$1',[g.chat_id]);await db.query('DELETE FROM assistant_installations WHERE id=$1',[g.id]);}
    await db.query('DELETE FROM moon_ai_outbox WHERE customer_id=ANY($1::uuid[])',[[user,stranger,idle]]);
    await db.query('DELETE FROM chats WHERE customer_id=ANY($1::uuid[])',[[user,stranger,idle]]);
    await db.query("DELETE FROM moon_ai_payment_callbacks WHERE phone='77000000000' AND amount BETWEEN 99101 AND 99106");
    await db.query('DELETE FROM payment_events WHERE payment_id IN(SELECT id FROM payments WHERE customer_id=ANY($1::uuid[]))',[[user,stranger,idle]]);
    await db.query('DELETE FROM payments WHERE customer_id=ANY($1::uuid[])',[[user,stranger,idle]]);
    await db.query('DELETE FROM device_tokens WHERE user_id=ANY($1::uuid[])',[[user,stranger,idle]]);
    await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[user,stranger,idle]]);
    await db.close();
  }
});
