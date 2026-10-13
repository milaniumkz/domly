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
    acceptMoonChatEvent,acceptMoonPaymentStatus,ensureGuestSession,guestSession,bindGuestSession}=await import('../modules/moonAi');
  const previous={moonAiEnabled:env.moonAiEnabled,moonAiChannelUrl:env.moonAiChannelUrl,moonAiChannelApiKey:env.moonAiChannelApiKey,moonAiWebhookToken:env.moonAiWebhookToken,moonAiSource:env.moonAiSource};
  Object.assign(env,{moonAiEnabled:true,moonAiChannelUrl:'https://core.mooonai.com/api/v1/channels/api/messages',moonAiChannelApiKey:'fixture-channel-key',moonAiWebhookToken:'fixture-hook-key',moonAiSource:'domly'});
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
    for(const id of [user,stranger,idle])await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[id,'moon-fixture-'+id]);
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
      assert.equal(sent[0].thread_id,paymentId);assert.equal(sent[0].source,'domly_invoice');assert.equal(sent[0].from_type,'user');
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
    await t.test('assistant replies are stored once and notified only to the owner',async()=>{
      const events=new Map<string,any>();
      const notifications={create:async(input:any)=>{events.set(input.dedupeKey,input);}};
      const event={event_id:randomUUID(),event_type:'agent_message',source:'domly',external_thread_id:chatId,thread_id:`api:domly:${chatId}`,message:{data:{text:'Здравствуйте!'}}};
      assert.equal((await acceptMoonChatEvent(db,notifications,event)).duplicate,false);
      assert.equal((await acceptMoonChatEvent(db,notifications,event)).duplicate,true);
      assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM chat_messages WHERE chat_id=$1',[chatId])).rows[0].n,1);
      assert.equal(events.size,1);assert.equal([...events.values()][0].userId,user);assert.equal([...events.values()][0].targetType,'assistant_chat');
      await assert.rejects(acceptMoonChatEvent(db,notifications,{...event,source:'foreign'}));
      const ignored=await acceptMoonChatEvent(db,notifications,{...event,event_type:'user_message'});assert.equal(ignored.ignored,true);
    });
    await t.test('new registered customer gets a single thirty-minute welcome',async()=>{
      await scheduleSignupFollowup(db,idle);await scheduleSignupFollowup(db,idle);
      const rows=(await db.query("SELECT *,EXTRACT(EPOCH FROM run_after-created_at)::int AS delay FROM moon_ai_outbox WHERE customer_id=$1 AND kind='inactive_signup'",[idle])).rows;
      assert.equal(rows.length,1);assert.equal(rows[0].delay,1800);
      await db.query("UPDATE moon_ai_outbox SET run_after=NOW()-INTERVAL '1 second' WHERE id=$1",[rows[0].id]);
      await processMoonOutbox(db,send);assert.equal(sent.length,2);
      await processMoonOutbox(db,send);assert.equal(sent.length,2);
    });
    await t.test('first-open guest sessions are private, idempotent and expire on account binding',async()=>{
      const a=await ensureGuestSession(db,keys[0]),again=await ensureGuestSession(db,keys[0]),b=await ensureGuestSession(db,keys[1]);
      assert.equal(a.chatId,again.chatId);assert.notEqual(a.chatId,b.chatId);
      const guest=await guestSession(db,keys[0]);assert.equal(guest.chat_id,a.chatId);
      const reminders=(await db.query("SELECT EXTRACT(EPOCH FROM run_after-created_at)::int AS delay FROM moon_ai_outbox WHERE installation_id=$1 AND kind='inactive_install'",[guest.id])).rows;
      assert.equal(reminders.length,1);assert.ok(reminders[0].delay>=1799 && reminders[0].delay<=1800);
      await assert.rejects(guestSession(db,'c'.repeat(64)));
      await bindGuestSession(db,keys[0],user);
      await assert.rejects(guestSession(db,keys[0]));
      assert.equal((await db.query("SELECT state FROM moon_ai_outbox WHERE installation_id=$1",[guest.id])).rows[0].state,'cancelled');
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
      const app=express();app.use(express.json(),buildV1Router({db,notifications:{create:async()=>{}}} as any),errorHandler);
      const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
      const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
      try {
        const jwt=signAccessToken({id:user,role:'customer',phone:'fixture'});
        const other=signAccessToken({id:stranger,role:'customer',phone:'fixture'});
        assert.equal((await fetch(base+`/chats/${chatId}/messages`,{headers:{Authorization:'Bearer '+other}})).status,403);
        const own=await fetch(base+`/chats/${chatId}/messages`,{headers:{Authorization:'Bearer '+jwt}});
        assert.equal(own.status,200);assert.equal((await own.json() as any).data[0].sender_kind,'assistant');
        assert.equal((await fetch(base+'/assistant/guest/messages')).status,401);
        assert.equal((await fetch(base+'/assistant/guest/messages',{headers:{'X-Assistant-Session':keys[0]}})).status,401);
        assert.equal((await fetch(base+'/assistant/guest/messages',{headers:{'X-Assistant-Session':keys[1]}})).status,200);
        const sent=await fetch(base+'/assistant/guest/messages',{method:'POST',headers:{'X-Assistant-Session':keys[1],'Content-Type':'application/json'},body:JSON.stringify({message:'Привет'})});
        assert.equal(sent.status,201);
        assert.equal((await fetch(base+'/integrations/moon-ai/messages',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,401);
      }finally{await new Promise<void>((r,e)=>server.close(err=>err?e(err):r()));}
    });
  }finally{
    Object.assign(env,previous);
    const guests=(await db.query('SELECT id,chat_id FROM assistant_installations WHERE key_hash=ANY($1::text[])',[keys.map(k=>require('node:crypto').createHash('sha256').update(k).digest('hex'))])).rows;
    for(const g of guests){await db.query('DELETE FROM moon_ai_outbox WHERE installation_id=$1',[g.id]);await db.query('UPDATE assistant_installations SET chat_id=NULL WHERE id=$1',[g.id]);await db.query('DELETE FROM chats WHERE id=$1',[g.chat_id]);await db.query('DELETE FROM assistant_installations WHERE id=$1',[g.id]);}
    await db.query('DELETE FROM moon_ai_outbox WHERE customer_id=ANY($1::uuid[])',[[user,stranger,idle]]);
    await db.query('DELETE FROM chats WHERE customer_id=ANY($1::uuid[])',[[user,stranger,idle]]);
    await db.query('DELETE FROM payment_events WHERE payment_id IN(SELECT id FROM payments WHERE customer_id=ANY($1::uuid[]))',[[user,stranger,idle]]);
    await db.query('DELETE FROM payments WHERE customer_id=ANY($1::uuid[])',[[user,stranger,idle]]);
    await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[user,stranger,idle]]);
    await db.close();
  }
});
