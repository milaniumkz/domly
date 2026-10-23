import {defaultRequiredTasks} from '../modules/checklists';
import sharp from 'sharp';
import {env} from '../common/env';
import {httpsMediaUrl} from '../modules/mediaLinks';
import {Readable} from 'node:stream';
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import express from 'express';
import {AddressInfo} from 'node:net';
import {Database} from '../infrastructure/db/Database';
import {buildV1Router} from '../http/routes/v1';
import {errorHandler} from '../common/api';
import {signAccessToken,signRefreshToken,verifyAccessToken} from '../common/auth';
import {NotificationService,SchedulingService,hashToken} from '../modules/domainServices';
import {verifyCleaner} from '../modules/cleanerVerification';
import {PaymentGatewayService} from '../modules/integrations';

test('admin operations against real PostgreSQL', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
  const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const admin=randomUUID(),cleaner=randomUUID(),customer=randomUUID(),file=randomUUID();
  const catalogIds: Record<string,string> = {};
  const housePrefix='admin-address-'+randomUUID();
  let failPush=false;
  const notifications=new NotificationService(db,{send:async()=>{if(failPush)throw Error('Provider offline');return {sent:0};}} as any);
  const app=express();
  app.use(express.json(),buildV1Router({db,notifications,paymentGateway:new PaymentGatewayService(),payments:{refundOrderPayments:async()=>[]},scheduling:new SchedulingService(db),addressSearch:{externalSuggestions:async()=>[]},storage:{uploadBuffer:async(key:string)=>env.minioPublicUrl.replace(/\/$/,'')+'/'+key,client:{getObject:async()=>Readable.from([Buffer.from('test image')])}}} as any),errorHandler);
  const server=app.listen(0,'127.0.0.1');
  await new Promise<void>(resolve=>server.once('listening',resolve));
  const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
  async function request(path:string,method='GET',body?:object,asCustomer=false) {
    const token=signAccessToken({id:asCustomer?customer:admin,role:asCustomer?'customer':'superadmin',phone:'fixture'});
    const res=await fetch(base+path,{method,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
    return {status:res.status,json:await res.json() as any};
  }
  try {
    for(const [id,role] of [[admin,'superadmin'],[cleaner,'cleaner'],[customer,'customer']])await db.query("INSERT INTO app_users(id,phone,role,status,full_name) VALUES($1,$2,$3,'pending','Тестовая анкета')",[id,'admin-test-'+id,role]);
    await db.query('INSERT INTO cleaner_profiles(user_id) VALUES($1)',[cleaner]);
    await db.query("INSERT INTO files(id,owner_id,bucket,object_key,public_url) VALUES($1,$2,'test',$3,'https://example.com/document')",[file,cleaner,file]);
    await db.query("INSERT INTO cleaner_documents(cleaner_id,type,file_id) VALUES($1,'selfieUrl',$2)",[cleaner,file]);
    await t.test('cleaner verification keeps address and emergency contact private to staff', async () => {
      const token=signAccessToken({id:cleaner,role:'cleaner',phone:'fixture'});
      const saved=await fetch(base+'/cleaner/profile',{method:'PATCH',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({homeAddress:'Тәуелсіздік 29/2',emergencyContactPhone:'+77000000000',emergencyContactRelation:'Сестра'})});
      assert.equal(saved.status,200);
      const own=await fetch(base+'/cleaner/profile',{headers:{Authorization:'Bearer '+token}});
      assert.equal((await own.json()).data.profile.home_address,'Тәуелсіздік 29/2');
      const list=await request('/admin/cleaners');
      const row=list.json.data.find((item:any)=>item.id===cleaner);
      assert.equal(row.emergency_contact_phone,'+77000000000');
      const details=await request('/admin/cleaners/'+cleaner+'/details');
      assert.equal(details.json.data.cleaner.emergency_contact_relation,'Сестра');
      assert.equal((await request('/admin/cleaners','GET',undefined,true)).status,403);
    });
    await t.test('customer settings and address search persist across requests', async () => {
      const updated=await request('/me/settings','PATCH',{language:'kk',darkMode:true,animations:false,tutorialCompleted_customer:true},true);
      assert.equal(updated.status,200);
      const current=await request('/me/settings','GET',undefined,true);
      assert.equal(current.json.data.language,'kk');
      assert.equal(current.json.data.darkMode,true);
      assert.equal(current.json.data.animations,false);
      assert.equal(current.json.data.tutorialCompleted_customer,true);
      const address=await request('/addresses','POST',{city:'Астана',street:'Тәуелсіздік',house:'29/2',area:100,residentialComplex:'ЖК Тестовый'},true);
      assert.equal(address.status,201);
      assert.equal(address.json.data.residential_complex,'ЖК Тестовый');
      const edited=await request('/addresses/'+address.json.data.id,'PATCH',{city:'Астана',street:'Тәуелсіздік',house:'29/2',area:110,residentialComplex:'ЖК Новый'},true);
      assert.equal(edited.status,200);
      assert.equal(edited.json.data.residential_complex,'ЖК Новый');
      const addresses=await request('/addresses','GET',undefined,true);
      assert.ok(addresses.json.data.some((item:any)=>item.id===address.json.data.id && item.house==='29/2' && item.service_available===true && item.residential_complex==='ЖК Новый'));
    });
    await t.test('Russian and Kazakh searches find the same Astana address in the chosen language', async () => {
      const id=randomUUID(), house='29/2-'+id.slice(0,6);
      await db.query("INSERT INTO connected_houses(id,city,street_ru,street_kk,house,active,residential_complex_ru,residential_complex_kk) VALUES($1,'Астана','Тауелсиздик','Тәуелсіздік',$2,FALSE,'ЖК Проверочный '||$2,'Тексеру '||$2)",[id,house]);
      for(const [search,lang,street] of [['тауелсиздык','ru','Тауелсиздик'],['Тәуелсіздік','kk','Тәуелсіздік'],['Проверочный','ru','Тауелсиздик'],['Тексеру','kk','Тәуелсіздік']]) {
        const result=await request('/geo/address-suggestions?city='+encodeURIComponent('Астана')+'&search='+encodeURIComponent(search+' '+house)+'&lang='+lang);
        assert.equal(result.status,200);
        assert.equal(result.json.data.suggestions.find((row:any)=>row.id===id)?.street,street);
      }
      const exact=await request('/geo/connected-houses?id='+id);
      assert.equal(exact.status,200);assert.equal(exact.json.data.length,1);
      assert.equal(exact.json.data[0].status,'ACTIVE');
      assert.ok(exact.json.data[0].address.includes(house));
      assert.equal(exact.json.data[0].id,id);
      assert.equal((await request('/geo/connected-houses?id=not-a-uuid')).status,400);
      await db.query('DELETE FROM connected_houses WHERE id=$1',[id]);
    });
    await t.test('priced add-ons keep a booking awaiting payment before cleaner search',async()=>{
      const packageId=randomUUID(),purchaseId=randomUUID(),addonId=randomUUID();
      await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,months,base_price,price_per_m2) VALUES($1,'Пакет допов',4,1,4000,100)",[packageId]);
      await db.query("INSERT INTO catalog_addons(id,title_ru,price,duration_minutes) VALUES($1,'Проверочная допуслуга',4300,15)",[addonId]);
      await db.query("INSERT INTO customer_packages(id,customer_id,package_id,total_cleanings,available_cleanings,status) VALUES($1,$2,$3,4,4,'active')",[purchaseId,customer,packageId]);
      try {
        const unknown=await request('/orders','POST',{customerPackageId:purchaseId,date:'2032-10-14',startTime:'10:00',addonsDetailed:[{label:'Несуществующая услуга',quantity:1}]},true);
        assert.equal(unknown.status,400);
        const created=await request('/orders','POST',{customerPackageId:purchaseId,date:'2032-10-14',startTime:'10:00',addonsDetailed:[{key:addonId,label:'Проверочная допуслуга',quantity:2}]},true);
        assert.equal(created.status,201);
        const order=created.json.data.order;
        assert.equal(order.status,'pending_payment');
        assert.equal(Number(order.addon_amount),8600);
        assert.equal(created.json.data.offer,null);
        assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM order_offers WHERE order_id=$1',[order.id])).rows[0].n,0);
        const lines=(await db.query('SELECT quantity,payment_status FROM order_addons WHERE order_id=$1',[order.id])).rows;
        assert.equal(Number(lines[0].quantity),2);
        assert.equal(lines[0].payment_status,'pending');
        await db.query('DELETE FROM service_orders WHERE id=$1',[order.id]);
      } finally {
        await db.query('DELETE FROM customer_packages WHERE id=$1',[purchaseId]);
        await db.query('DELETE FROM catalog_addons WHERE id=$1',[addonId]);
        await db.query('DELETE FROM catalog_packages WHERE id=$1',[packageId]);
      }
    });
    await t.test('BCC sandbox form and callbacks verify bank result without fulfilling real orders',async()=>{
      const paymentId=randomUUID(),orderId=randomUUID();
      const previous={bccMode:env.bccMode,bccNotifyUrl:env.bccNotifyUrl,publicApiUrl:env.publicApiUrl,bccNotifyUser:env.bccNotifyUser,bccNotifyPassword:env.bccNotifyPassword};
      const originalFetch=global.fetch;
      Object.assign(env,{bccMode:'test',bccNotifyUrl:'https://domly.kz:443/api/v1/payments/bcc/webhook',publicApiUrl:'https://domly.kz',bccNotifyUser:'',bccNotifyPassword:''});
      await db.query("INSERT INTO service_orders(id,customer_id,status,payable_amount) VALUES($1,$2,'pending_payment',350)",[orderId,customer]);
      await db.query("INSERT INTO payments(id,customer_id,order_id,provider,status,amount) VALUES($1,$2,$3,'bcc','pending',350)",[paymentId,customer,orderId]);
      try {
        const methods=await request('/payments/methods');assert.equal(methods.json.data.online,true);assert.equal(methods.json.data.onlineTest,true);
        const session=await request('/payments/'+paymentId+'/bcc-session','POST',{},true);
        assert.equal(session.status,200);
        assert.match(session.json.data.paymentHtml,/test3ds.bcc.kz:5445/);
        assert.equal(session.json.data.testMode,true);
        const reference=session.json.data.providerPayload.ORDER;
        const repeated=await request('/payments/'+paymentId+'/bcc-session','POST',{},true);
        assert.equal(repeated.json.data.providerPayload.ORDER,reference);
        let bankResponse:any={ORDER:reference,TERMINAL:'88888881',AMOUNT:'350.00',CURRENCY:'398',ACTION:'0',RC:'00'};
        global.fetch=(async(input:any,init:any)=>String(input).startsWith('https://test3ds.bcc.kz:5445/')
          ? new Response(JSON.stringify(bankResponse),{status:200,headers:{'Content-Type':'application/json'}}) : originalFetch(input,init)) as typeof fetch;
        const callback=await originalFetch(base+'/payments/bcc/webhook',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({ORDER:reference,ACTION:'0',RC:'00'})});
        assert.equal(callback.status,200);
        assert.equal((await callback.json()).data.bankStatus,'paid');
        const saved=(await db.query('SELECT * FROM payments WHERE id=$1',[paymentId])).rows[0];
        assert.equal(saved.status,'pending');assert.equal(saved.payload.bccBankStatus,'paid');
        assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[orderId])).rows[0].status,'pending_payment');
        assert.equal(Number((await db.query('SELECT COUNT(*) AS n FROM order_offers WHERE order_id=$1',[orderId])).rows[0].n),0);
        bankResponse={...bankResponse,AMOUNT:'999.00'};
        assert.equal((await request('/payments/bcc/webhook','POST',{ORDER:reference,ACTION:'0',RC:'00'})).status,502);
        bankResponse={ACTION:'0',RC:'00'};
        assert.equal((await request('/payments/bcc/webhook','POST',{ORDER:reference,ACTION:'0',RC:'00'})).status,502);
        bankResponse={ORDER:reference,TERMINAL:'88888881',ACTION:'2',RC:'05'};
        assert.equal((await request('/payments/bcc/webhook','POST',{ORDER:reference,ACTION:'0',RC:'00'})).status,200);
        assert.equal((await db.query('SELECT status FROM payments WHERE id=$1',[paymentId])).rows[0].status,'rejected');
      } finally {
        global.fetch=originalFetch;Object.assign(env,previous);
        await db.query('DELETE FROM payment_events WHERE payment_id=$1',[paymentId]);
        await db.query('DELETE FROM payments WHERE id=$1',[paymentId]);
        await db.query('DELETE FROM service_orders WHERE id=$1',[orderId]);
      }
    });
    await t.test('unbooked package purchase appears in customer orders while awaiting payment and after approval', async () => {
      const pkgId=randomUUID(), purchaseId=randomUUID(), payId=randomUUID();
      await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,months,base_price,price_per_m2) VALUES($1,'Пакет проверки',4,1,4000,100)",[pkgId]);
      await db.query("INSERT INTO customer_packages(id,customer_id,package_id,total_cleanings,available_cleanings) VALUES($1,$2,$3,4,4)",[purchaseId,customer,pkgId]);
      await db.query("INSERT INTO payments(id,customer_id,customer_package_id,provider,status,amount) VALUES($1,$2,$3,'kaspi','invoice_requested',4000)",[payId,customer,purchaseId]);
      const pending=await request('/orders','GET',undefined,true);
      assert.equal(pending.status,200);
      assert.equal(pending.json.data.find((item:any)=>item.id===payId)?.status,'pending_payment');
      await db.query("UPDATE payments SET status='paid' WHERE id=$1",[payId]);
      const paid=await request('/orders','GET',undefined,true);
      assert.equal(paid.json.data.find((item:any)=>item.id===payId)?.status,'pending_assignment');
      await db.query('DELETE FROM payments WHERE id=$1',[payId]);
      await db.query('DELETE FROM customer_packages WHERE id=$1',[purchaseId]);
      await db.query('DELETE FROM catalog_packages WHERE id=$1',[pkgId]);
    });
    await t.test('banner creation, metadata, hidden visibility, editing and deletion', async () => {
      assert.equal((await request('/admin/banners','POST',{titleRu:''})).status,400);
      assert.equal((await request('/admin/banners','POST',{titleRu:'No access'},true)).status,403);
      const created=await request('/admin/banners','POST',{
        titleRu:'Тестовый баннер',subtitleRu:'Краткий текст',descriptionRu:'Подробности',
        imageUrl:env.minioPublicUrl+'/promo_banners/test.jpg',ctaLabelRu:'Пакеты',
        targetType:'route',targetValue:'/client/package-selection',active:false,
      });
      assert.equal(created.status,201);
      const id=created.json.data.id;
      try {
        assert.equal(created.json.data.placement,'home_top');
        assert.equal(created.json.data.subtitle_ru,'Краткий текст');
        assert.equal(created.json.data.cta_label_ru,'Пакеты');
        assert.match(created.json.data.image_url,/\/api\/v1\/files\/media\?/);
        assert.ok((await request('/admin/banners')).json.data.some((row:any)=>row.id===id));
        assert.ok(!(await request('/catalog/banners')).json.data.some((row:any)=>row.id===id));
        const edited=await request('/admin/banners/'+id,'PATCH',{active:true,targetType:'external',targetValue:'https://domly.kz',ctaLabelRu:'Открыть'});
        assert.equal(edited.status,200);
        assert.equal(edited.json.data.subtitle_ru,'Краткий текст');
        const published=(await request('/catalog/banners')).json.data.find((row:any)=>row.id===id);
        assert.equal(published.target_value,'https://domly.kz');
        assert.equal(published.cta_label_ru,'Открыть');
        assert.match(published.image_url,/\/api\/v1\/files\/media\?/);
        assert.equal((await request('/admin/banners/'+id,'PATCH',{imageUrl:'',subtitleRu:'',ctaLabelRu:''})).status,200);
        assert.equal((await request('/admin/banners/'+id,'DELETE',undefined,true)).status,403);
        assert.equal((await request('/admin/banners/'+id,'DELETE')).status,200);
        assert.ok(!(await request('/admin/banners')).json.data.some((row:any)=>row.id===id));
      } finally { await db.query('DELETE FROM banners WHERE id=$1',[id]); }
    });
    await t.test('promotions accept any package and preserve reward and presentation',async()=>{
      const packageId=randomUUID();
      await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,base_price) VALUES($1,'Тестовый пакет',1,10000)",[packageId]);
      const ids:string[]=[];
      try {
        assert.equal((await request('/admin/promotions','POST',{titleRu:'',packageId:''})).status,400);
        assert.equal((await request('/admin/promotions','POST',{titleRu:'Bad',packageId:'invalid'})).status,400);
        assert.equal((await request('/admin/promotions','POST',{titleRu:'Bad',rewardType:'percent',rewardValue:101})).status,400);
        assert.equal((await request('/admin/promotions','POST',{titleRu:'No access'},true)).status,403);
        for(const type of ['fixed','percent']) {
          const value=type==='fixed'?15000:10;
          const created=await request('/admin/promotions','POST',{titleRu:'Тест акции',descriptionRu:'Кратко',packageId:'',rewardType:type,rewardValue:value,maxBonusSpendPercent:50,oncePerCustomer:true,active:false,presentation:{fullInfo:'Подробно',features:['Окна'],exclusions:['Балкон'],homeBannerImageUrl:env.minioPublicUrl+'/promo_banners/promotion.jpg',showBannerTitle:false,rewardTarget:'addons'}});
          assert.equal(created.status,201);
          const row=created.json.data;ids.push(row.id);
          assert.equal(row.package_id,null);assert.equal(row.reward_type,type);assert.equal(Number(row.reward_value),value);assert.equal(row.active,false);
          assert.equal(row.presentation.fullInfo,'Подробно');assert.deepEqual(row.presentation.features,['Окна']);assert.equal(row.presentation.showBannerTitle,false);
          assert.match(row.presentation.homeBannerImageUrl,/\/api\/v1\/files\/media\?/);
          assert.ok((await request('/admin/promotions')).json.data.some((item:any)=>item.id===row.id));
          assert.equal((await request('/admin/promotions/'+row.id,'PATCH',{packageId,active:true})).status,200);
          assert.equal((await request('/admin/promotions/'+row.id,'PATCH',{packageId:null,descriptionRu:'Обновлено'})).json.data.package_id,null);
          const updated=(await request('/admin/promotions')).json.data.find((item:any)=>item.id===row.id);
          assert.equal(updated.presentation.fullInfo,'Подробно');
          await db.query('INSERT INTO promotion_redemptions(promotion_id,customer_id,reward_amount) VALUES($1,$2,100)',[row.id,customer]);
          assert.equal((await request('/admin/promotions/'+row.id,'DELETE')).status,200);
          assert.ok(!(await request('/admin/promotions')).json.data.some((item:any)=>item.id===row.id));
          assert.equal((await db.query('SELECT id FROM promotion_redemptions WHERE promotion_id=$1',[row.id])).rowCount,1);
          assert.equal((await request('/admin/promotions/'+row.id+'/active','PATCH',{active:true})).status,404);
        }
      } finally {
        for(const id of ids)await db.query('DELETE FROM promotions WHERE id=$1',[id]);
        await db.query('DELETE FROM catalog_packages WHERE id=$1',[packageId]);
      }
    });
    await t.test('admin session refresh rotates tokens and preserves access after reopening',async()=>{
      const original=signRefreshToken({id:admin,role:'superadmin',phone:'fixture'});
      await db.query("INSERT INTO refresh_sessions(user_id,token_hash,expires_at) VALUES($1,$2,NOW()+INTERVAL '30 days')",[admin,hashToken(original)]);
      let token=original;
      for(let i=0;i<3;i++) {
        const response=await request('/auth/refresh','POST',{refreshToken:token});
        assert.equal(response.status,200);
        const next=response.json.data;
        assert.notEqual(next.refreshToken,token);
        assert.equal(verifyAccessToken(next.accessToken).id,admin);
        assert.equal((await fetch(base+'/admin/quality',{headers:{Authorization:'Bearer '+next.accessToken}})).status,200);
        assert.equal((await request('/auth/refresh','POST',{refreshToken:token})).status,401);
        token=next.refreshToken;
      }
      assert.equal((await request('/auth/refresh','POST',{refreshToken:'invalid'})).status,401);
    });
    await t.test('order start confirmation, completion, ownership and retry are consistent',async()=>{
      const order=randomUUID();
      await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,status) VALUES($1,$2,$3,'assigned')",[order,customer,cleaner]);
      async function cleanerRequest(path:string,body:object) {
        const token=signAccessToken({id:cleaner,role:'cleaner',phone:'fixture'});
        const res=await fetch(base+path,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});
        return {status:res.status,json:await res.json() as any};
      }
      try {
        const other=randomUUID();
        await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[other,'order-owner-'+other]);
        try {
          const token=signAccessToken({id:other,role:'customer',phone:'fixture'});
          for (const path of ['cancel','confirm-start']) {
            const res=await fetch(base+`/orders/${order}/${path}`,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({confirmed:true})});
            assert.ok([403,404].includes(res.status));
          }
          assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[order])).rows[0].status,'assigned');
        } finally {await db.query('DELETE FROM app_users WHERE id=$1',[other]);}
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'completed'})).status,409);
        assert.equal((await cleanerRequest(`/orders/${order}/photo-report`,{photoUrls:['a','b','c']})).status,409);
        const start=await cleanerRequest(`/orders/${order}/status`,{status:'in_progress'});
        assert.equal(start.status,200);
        assert.equal(start.json.data.status,'start_pending');
        assert.equal(start.json.data.start_requires_customer_confirmation,true);
        assert.equal((await request(`/orders/${order}/confirm-start`,'POST',{confirmed:false},true)).status,200);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'in_progress'})).status,200);
        const confirm=await request(`/orders/${order}/confirm-start`,'POST',{confirmed:true},true);
        assert.equal(confirm.status,200);
        assert.equal(confirm.json.data.order.status,'in_progress');
        assert.equal(confirm.json.data.order.cleaning_start_confirmed,true);
        assert.ok(confirm.json.data.order.started_at);
        const count=Number((await db.query('SELECT COUNT(*) AS count FROM notifications WHERE target_id=$1',[order])).rows[0].count);
        assert.equal((await request(`/orders/${order}/confirm-start`,'POST',{confirmed:true},true)).status,200);
        assert.equal(Number((await db.query('SELECT COUNT(*) AS count FROM notifications WHERE target_id=$1',[order])).rows[0].count),count);
        assert.equal((await request(`/orders/${order}/photo-report`,'GET',undefined,true)).json.data.canSubmit,true);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'completed'})).status,409);
        assert.equal((await cleanerRequest(`/orders/${order}/photo-report`,{photoUrls:['a','b','c']})).status,400);
        const photoKey='photo_reports/'+cleaner+'/'+randomUUID()+'.jpg';
        const photoUrl=env.minioPublicUrl.replace(/\/$/,'')+'/'+photoKey;
        await db.query("INSERT INTO files(owner_id,bucket,object_key,mime_type,public_url) VALUES($1,$2,$3,'image/jpeg',$4)",[cleaner,env.minioBucket,photoKey,photoUrl]);
        assert.equal((await cleanerRequest(`/orders/${order}/photo-report`,{photoUrls:[photoUrl,photoUrl,photoUrl]})).status,201);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'completed'})).status,409);
        assert.equal((await cleanerRequest(`/orders/${order}/checklist`,{completedTasks:defaultRequiredTasks.slice(0,1),note:'Проверка заметки'})).status,200);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'completed'})).status,409);
        const draft=await request(`/orders/${order}/checklist`,'GET');
        assert.equal(draft.json.data.items.filter((i:any)=>i.required&&!i.checked).length,4);
        assert.equal(draft.json.data.report.note,'Проверка заметки');
        // A legacy draft retained only checked rows; opening it must restore missing requirements.
        await db.query('DELETE FROM checklist_report_items WHERE report_id=$1 AND NOT checked',[draft.json.data.report.id]);
        await db.query('UPDATE checklist_reports SET requirements_initialized=FALSE WHERE id=$1',[draft.json.data.report.id]);
        const restored=await request(`/orders/${order}/checklist`,'GET');
        assert.equal(restored.json.data.items.filter((i:any)=>i.required).length,5);
        assert.equal(restored.json.data.items.filter((i:any)=>i.checked).length,1);
        assert.equal((await cleanerRequest(`/orders/${order}/checklist`,{completedTasks:defaultRequiredTasks})).status,200);
        const reportId=draft.json.data.report.id;
        await db.query("INSERT INTO checklist_report_items(report_id,title_ru,required) VALUES($1,'Доп. услуга: Мытьё окон',TRUE)",[reportId]);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'completed'})).status,409);
        assert.equal((await cleanerRequest(`/orders/${order}/checklist`,{completedTasks:defaultRequiredTasks,addons:['Мытьё окон']})).status,200);
        assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM checklist_report_items WHERE report_id=$1 AND required AND NOT checked',[reportId])).rows[0].n,0);
        assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM checklist_report_items WHERE report_id=$1',[reportId])).rows[0].n,6);
        const complete=await cleanerRequest(`/orders/${order}/status`,{status:'completed'});
        assert.equal(complete.status,200);
        assert.ok(complete.json.data.completed_at);
        assert.equal((await request(`/orders/${order}/photo-report`,'GET',undefined,true)).json.data.canSubmit,false);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'completed'})).status,200);
        assert.equal((await cleanerRequest(`/orders/${order}/status`,{status:'in_progress'})).status,409);
        assert.equal((await request(`/orders/${order}/reschedule`,'POST',{date:'2030-01-01',time:'10:00'},true)).status,409);
        assert.equal((await request(`/orders/${order}/cancel`,'POST',{},true)).status,404);
        const history=(await db.query('SELECT new_status FROM order_status_history WHERE order_id=$1 ORDER BY created_at',[order])).rows.map((row:any)=>row.new_status);
        assert.deepEqual(history,['start_pending','assigned','start_pending','in_progress','completed']);
        const notices=(await db.query('SELECT user_id,title_ru FROM notifications WHERE target_id=$1',[order])).rows;
        assert.ok(notices.some((row:any)=>row.user_id===customer&&row.title_ru==='Уборка завершена'));
        assert.ok(notices.every((row:any)=>[customer,cleaner].includes(row.user_id)));
      } finally {
        await db.query('DELETE FROM notifications WHERE target_id=$1',[order]);
        await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
      }
    });
    await t.test('rescheduling and cancellation notify both parties and retain history',async()=>{
      const order=randomUUID();
      await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,status,scheduled_date,start_time,end_time,estimated_duration_minutes) VALUES($1,$2,$3,'assigned','2031-01-01','10:00','12:00',120)",[order,customer,cleaner]);
      try {
        const move=await request(`/orders/${order}/reschedule`,'POST',{date:'2031-01-02',time:'13:00'},true);
        assert.equal(move.status,200);
        assert.equal(String(move.json.data.start_time),'13:00:00');
        assert.equal((await request(`/orders/${order}/cancel`,'POST',{reason:'test'},true)).status,200);
        assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[order])).rows[0].status,'cancelled');
        assert.equal((await request(`/orders/${order}/cancel`,'POST',{},true)).status,404);
        assert.equal((await request(`/orders/${order}/status`,'POST',{status:'in_progress'})).status,409);
        const history=(await db.query('SELECT new_status FROM order_status_history WHERE order_id=$1 ORDER BY created_at',[order])).rows;
        assert.deepEqual(history.map((row:any)=>row.new_status),['assigned','cancelled']);
        const notices=(await db.query('SELECT user_id,title_ru FROM notifications WHERE target_id=$1',[order])).rows;
        for(const user of [customer,cleaner]) {
          assert.ok(notices.some((row:any)=>row.user_id===user&&row.title_ru==='Время уборки изменено'));
          assert.ok(notices.some((row:any)=>row.user_id===user&&row.title_ru==='Заказ отменён'));
        }
      } finally {
        await db.query('DELETE FROM notifications WHERE target_id=$1',[order]);
        await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
      }
    });
    await t.test('cleaner cancellation releases assignment without cancelling payment and rejects late withdrawal',async()=>{
      const order=randomUUID(),late=randomUUID();
      const token=signAccessToken({id:cleaner,role:'cleaner',phone:'fixture'});
      async function release(id:string) {
        return fetch(base+`/orders/${id}/status`,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({status:'canceled'})});
      }
      try {
        await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,status,scheduled_date,start_time,end_time,estimated_duration_minutes,total_amount) VALUES($1,$3,$4,'assigned','2032-01-01','10:00','12:00',120,22000),($2,$3,$4,'assigned',CURRENT_DATE,'00:01','02:01',120,22000)",[order,late,customer,cleaner]);
        assert.equal((await fetch(base+`/orders/${order}/cancel`,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:'{}'})).status,403);
        assert.equal((await release(late)).status,409);
        assert.equal((await release(order)).status,200);
        const row=(await db.query('SELECT * FROM service_orders WHERE id=$1',[order])).rows[0];
        assert.equal(row.cleaner_id,null);
        assert.ok(['pending_assignment','waiting_cleaner'].includes(row.status));
        assert.equal(Number(row.total_amount),22000);
        assert.equal(row.cancelled_by,null);
        assert.equal((await release(order)).status,403);
        assert.ok((await db.query("SELECT id FROM notifications WHERE target_id=$1 AND user_id=$2 AND title_ru='Подбираем другую уборщицу'",[order,customer])).rows.length);
      } finally {
        await db.query('DELETE FROM notifications WHERE target_id=ANY($1::text[])',[[order,late]]);
        await db.query('DELETE FROM service_orders WHERE id=ANY($1::uuid[])',[[order,late]]);
      }
    });
    await t.test('uploads and photo reports use signed media across customer, Pro and admin without opening private storage',async()=>{
      const order=randomUUID();let uploaded:any;
      const token=signAccessToken({id:cleaner,role:'cleaner',phone:'fixture'});
      try {
        await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,status) VALUES($1,$2,$3,'in_progress')",[order,customer,cleaner]);
        const validPhoto=await sharp({create:{width:640,height:480,channels:3,background:'#238a65'}}).jpeg().toBuffer();
        const form=new FormData();form.append('folder','photo_reports');form.append('file',new Blob([new Uint8Array(validPhoto)],{type:'image/jpeg'}),'report.jpg');
        const upload=await fetch(base+'/files',{method:'POST',headers:{Authorization:'Bearer '+token},body:form});
        assert.equal(upload.status,201);uploaded=(await upload.json() as any).data;
        const url=new URL(uploaded.public_url);
        assert.equal(url.pathname,'/api/v1/files/media');
        const image=await fetch(base+url.pathname.replace('/api/v1','')+url.search);
        assert.equal(image.status,200);assert.equal(image.headers.get('content-type'),'image/jpeg');
        assert.equal(await image.text(),'test image');
        assert.equal((await fetch(base+'/files/media?key=private')).status,403);
        const tampered=new URL(url);tampered.searchParams.set('key','other/file.jpg');
        assert.equal((await fetch(base+tampered.pathname.replace('/api/v1','')+tampered.search)).status,403);
        const stored=(await db.query('SELECT public_url FROM files WHERE id=$1',[uploaded.id])).rows[0].public_url;
        assert.equal((await request('/complaints','POST',{title:'test',body:'test',photoUrls:[stored]},true)).status,403);
        const report=await fetch(base+`/orders/${order}/photo-report`,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({photoUrls:[uploaded.public_url,uploaded.public_url,uploaded.public_url]})});
        assert.equal(report.status,201);
        assert.equal((await db.query('SELECT photo_urls FROM photo_reports WHERE order_id=$1',[order])).rows[0].photo_urls[0],stored);
        for(const asCustomer of [true,false]) {
          const response=await request(`/orders/${order}/photo-report`,'GET',undefined,asCustomer);
          assert.equal(response.status,200);
          const photo=new URL(response.json.data.report.photo_urls[0]);
          assert.equal(photo.pathname,'/api/v1/files/media');
          assert.equal((await fetch(base+photo.pathname.replace('/api/v1','')+photo.search)).status,200);
        }
        const preview=await request('/admin/files/preview?url='+encodeURIComponent(uploaded.public_url));
        assert.equal(preview.status,200);assert.equal(Buffer.from(preview.json.data.base64,'base64').toString(),'test image');
      } finally {
        await db.query('DELETE FROM notifications WHERE target_id=$1',[order]);
        await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
        if(uploaded)await db.query('DELETE FROM files WHERE id=$1',[uploaded.id]);
      }
    });
    await t.test('both order participants review completed work once and ratings stay separate',async()=>{
      const order=randomUUID(),other=randomUUID();
      const token=signAccessToken({id:cleaner,role:'cleaner',phone:'fixture'});
      const outsider=signAccessToken({id:other,role:'cleaner',phone:'fixture'});
      async function review(asCleaner:boolean,rating:number) {
        if(!asCleaner)return request('/reviews','POST',{orderId:order,rating,cleanerId:other},true);
        const res=await fetch(base+'/reviews',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({orderId:order,rating})});
        return {status:res.status,json:await res.json() as any};
      }
      try {
        await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'cleaner','approved')",[other,'review-test-'+other]);
        await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,status) VALUES($1,$2,$3,'in_progress')",[order,customer,cleaner]);
        assert.equal((await review(true,5)).status,409);
        await db.query("UPDATE service_orders SET status='completed' WHERE id=$1",[order]);
        assert.equal((await fetch(base+'/reviews',{method:'POST',headers:{Authorization:'Bearer '+outsider,'Content-Type':'application/json'},body:JSON.stringify({orderId:order,rating:5})})).status,403);
        assert.equal((await review(true,6)).status,400);
        const pro=await review(true,4);assert.equal(pro.status,201);assert.equal(pro.json.data.author_role,'cleaner');
        assert.equal((await review(true,4)).status,200);
        const client=await review(false,5);assert.equal(client.status,201);assert.equal(client.json.data.cleaner_id,cleaner);
        assert.equal((await review(false,5)).status,200);
        assert.equal(Number((await db.query('SELECT COUNT(*) AS count FROM reviews WHERE order_id=$1',[order])).rows[0].count),2);
        assert.equal(Number((await db.query('SELECT rating FROM app_users WHERE id=$1',[customer])).rows[0].rating),4);
        assert.equal(Number((await db.query('SELECT rating FROM app_users WHERE id=$1',[cleaner])).rows[0].rating),5);
      } finally {
        const reviews=(await db.query('SELECT id FROM reviews WHERE order_id=$1',[order])).rows.map((r:any)=>r.id);
        if(reviews.length)await db.query('DELETE FROM notifications WHERE target_id=ANY($1::text[])',[reviews]);
        await db.query('DELETE FROM reviews WHERE order_id=$1',[order]);
        await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
        await db.query('DELETE FROM app_users WHERE id=$1',[other]);
      }
    });
    await t.test('personal notifications never leak through role membership',async()=>{
      const other=randomUUID();
      const ids=[randomUUID(),randomUUID(),randomUUID()];
      await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[other,'notification-test-'+other]);
      try {
        for(const [id,user,role] of [[ids[0],customer,'customer'],[ids[1],other,'customer'],[ids[2],null,'customer']]) {
          await db.query("INSERT INTO notifications(id,user_id,role,title_ru,body_ru) VALUES($1,$2,$3,'Test','Test')",[id,user,role]);
        }
        const rows=(await request('/notifications','GET',undefined,true)).json.data;
        assert.ok(rows.some((row:any)=>row.id===ids[0]));
        assert.ok(rows.some((row:any)=>row.id===ids[2]));
        assert.ok(!rows.some((row:any)=>row.id===ids[1]));
        assert.equal((await request('/notifications/'+ids[1]+'/read','POST',{},true)).status,404);
        const before=(await request('/notifications/unread-count','GET',undefined,true)).json.data.count;
        await request('/notifications/'+ids[0]+'/read','POST',{},true);
        assert.equal((await request('/notifications/unread-count','GET',undefined,true)).json.data.count,before-1);
        assert.equal((await request('/notifications/read-all','POST',{},true)).status,200);
        assert.equal((await db.query('SELECT read_at FROM notifications WHERE id=$1',[ids[1]])).rows[0].read_at,null);
        assert.equal((await db.query('SELECT COUNT(*)::int AS count FROM notification_reads WHERE notification_id=$1 AND user_id=$2',[ids[1],customer])).rows[0].count,0);
      } finally {
        await db.query('DELETE FROM notifications WHERE id=ANY($1::uuid[])',[ids]);
        await db.query('DELETE FROM app_users WHERE id=$1',[other]);
      }
    });
    await t.test('cleaner zones load, persist, clear and reject inactive selections',async()=>{
      const active=randomUUID(),inactive=randomUUID();
      const token=signAccessToken({id:cleaner,role:'cleaner',phone:'fixture'});
      async function cleanerRequest(body?:object) {
        const res=await fetch(base+'/cleaner/profile',{method:body?'PATCH':'GET',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
        return {status:res.status,json:await res.json() as any};
      }
      try {
        await db.query("INSERT INTO service_zones(id,name_ru,city,active) VALUES($1,'Test Active','Test',TRUE),($2,'Test Inactive','Test',FALSE)",[active,inactive]);
        const zones=(await request('/geo/zones?city=Test')).json.data;
        assert.ok(zones.some((row:any)=>row.id===active));
        assert.ok(!zones.some((row:any)=>row.id===inactive));
        assert.equal((await fetch(base+'/admin/zones',{headers:{Authorization:'Bearer '+token}})).status,403);
        assert.equal((await cleanerRequest({zoneIds:[active,active]})).status,200);
        assert.deepEqual((await cleanerRequest()).json.data.zones.map((z:any)=>z.id),[active]);
        assert.equal((await cleanerRequest({soundVolume:50})).status,200);
        assert.equal((await cleanerRequest()).json.data.zones.length,1);
        assert.equal((await cleanerRequest({zoneIds:[inactive],fullName:'Must Roll Back'})).status,400);
        assert.equal((await cleanerRequest()).json.data.profile.full_name,'Тестовая анкета');
        assert.equal((await cleanerRequest()).json.data.zones.length,1);
        assert.equal((await cleanerRequest({zoneIds:[]})).status,200);
        assert.equal((await cleanerRequest()).json.data.zones.length,0);
      } finally {await db.query('DELETE FROM cleaner_zones WHERE cleaner_id=$1',[cleaner]);await db.query('DELETE FROM service_zones WHERE id=ANY($1::uuid[])',[[active,inactive]]);}
    });
    await t.test('area approval credits bonus once across both endpoints and retries',async()=>{
      const address=randomUUID(),check=randomUUID();
      const initial=Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[customer])).rows[0].bonus_balance);
      try {
        await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area,is_primary) VALUES($1,$2,'Астана','Test','1',90,TRUE)",[address,customer]);
        await db.query("INSERT INTO quality_check_requests(id,customer_id,address_id,requested_area) VALUES($1,$2,$3,100)",[check,customer,address]);
        const repeatedRequests=await Promise.all(Array.from({length:3},()=>request('/quality-checks/from-file','POST',{addressId:address,actualArea:100},true)));
        assert.ok(repeatedRequests.every(result=>result.status===201 && result.json.data.request.id===check));
        assert.equal(Number((await db.query("SELECT COUNT(*) AS n FROM quality_check_requests WHERE customer_id=$1 AND address_id=$2 AND status IN ('pending','scheduled')",[customer,address])).rows[0].n),1);
        assert.equal((await request('/admin/quality-checks/'+check,'PATCH',{status:'approved',approvedArea:100})).status,200);
        assert.equal((await request('/admin/quality-checks/'+check,'PATCH',{actualArea:100,difference:10,reviewStatus:'verified',confirmedByQualityControl:true})).status,200);
        assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[customer])).rows[0].bonus_balance),initial+2000);
        assert.equal(Number((await db.query('SELECT verified_area FROM customer_addresses WHERE id=$1',[address])).rows[0].verified_area),100);
        const repeated=await Promise.all([request('/admin/quality-checks/'+check+'/approve','POST',{approvedArea:100}),request('/admin/users/'+customer+'/confirm-area','POST',{actualArea:100})]);
        for(const res of repeated) assert.equal(res.status,200);
        assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[customer])).rows[0].bonus_balance),initial+2000);
        const history=(await request('/bonus/history','GET',undefined,true)).json.data;
        assert.equal(history.filter((row:any)=>row.dedupe_key==='area-confirmation:'+customer+':'+address).length,1);
        assert.equal((await request('/admin/quality-checks/'+check+'/approve','POST',{approvedArea:-5})).status,400);
      } finally {
        await db.query('DELETE FROM quality_check_requests WHERE id=$1',[check]);
        await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[customer]);
        await db.query('UPDATE app_users SET bonus_balance=$2 WHERE id=$1',[customer,initial]);
        await db.query('DELETE FROM customer_addresses WHERE id=$1',[address]);
      }
    });
    await t.test('dispatched order reaches cleaner and acceptance keeps it in cleaner orders',async()=>{
      const order=randomUUID();
      const token=signAccessToken({id:cleaner,role:'cleaner',phone:'fixture'});
      const service=new SchedulingService(db);
      try {
        await db.query("UPDATE app_users SET status='approved' WHERE id=$1",[cleaner]);
        await db.query("UPDATE cleaner_profiles SET verification_status='approved' WHERE user_id=$1",[cleaner]);
        await db.query("INSERT INTO service_orders(id,customer_id,scheduled_date,start_time,end_time,estimated_duration_minutes,area,status) VALUES($1,$2,'2030-01-02','10:00','12:00',120,100,'pending_assignment')",[order,customer]);
        const candidates=await service.availableCleaners('2030-01-02','10:00','12:00');
        const offer=await service.offerNextCleaner(order,candidates.filter((c:any)=>c.id!==cleaner).map((c:any)=>c.id)) as any;
        assert.equal(offer.cleaner_id,cleaner);
        const remaining=Date.parse(offer.expires_at)-Date.now();
        assert.ok(remaining>110000 && remaining<=120000,'Default offer expires after two minutes');
        const offersResponse=await fetch(base+'/cleaner/offers',{headers:{Authorization:'Bearer '+token}});
        assert.equal(offersResponse.status,200);
        const offers=(await offersResponse.json() as any).data;
        assert.equal(offers.find((row:any)=>row.order_id===order).id,offer.id);
        assert.ok(Date.parse(offers.find((row:any)=>row.order_id===order).expires_at)>Date.now());
        assert.equal((await request('/orders/'+order+'/offers/accept','POST',{},true)).status,403);
        const responses=await Promise.all([service.acceptOffer(order,cleaner),service.acceptOffer(order,cleaner)].map(p=>p.then(()=>200,error=>error.statusCode??error.status??409)));
        assert.equal(responses.filter(status=>status===200).length,1);
        const accepted=(await (await fetch(base+'/cleaner/orders',{headers:{Authorization:'Bearer '+token}})).json() as any).data.find((row:any)=>row.id===order);
        assert.equal(accepted.cleaner_id,cleaner);assert.equal(accepted.status,'assigned');assert.ok(accepted.scheduled_date);
        assert.ok(!(await service.cleanerOffers(cleaner)).some((row:any)=>row.order_id===order));
        await assert.rejects(service.declineOffer(order,cleaner));
        assert.equal(await service.offerNextCleaner(order),null);
        assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[order])).rows[0].status,'assigned');
      } finally {
        await db.query('DELETE FROM order_offers WHERE order_id=$1',[order]);
        await db.query('DELETE FROM service_orders WHERE id=$1',[order]);
        await db.query("UPDATE app_users SET status='pending' WHERE id=$1",[cleaner]);
        await db.query("UPDATE cleaner_profiles SET verification_status='pending' WHERE user_id=$1",[cleaner]);
      }
    });
    await t.test('document preview reads stored objects only and rejects customer access',async()=>{
      const url='https://example.com/document';
      const preview=await request('/admin/files/preview?url='+encodeURIComponent(url));
      assert.equal(preview.status,200);
      assert.equal(Buffer.from(preview.json.data.base64,'base64').toString(),'test image');
      assert.equal((await request('/admin/files/preview?url='+encodeURIComponent(url),'GET',undefined,true)).status,403);
      assert.equal((await request('/admin/files/preview?url=http%3A%2F%2Flocalhost%2Fprivate')).status,404);
    });
    await t.test('all admin list sections load and deny customer access',async()=>{
      for(const section of ['cities','orders','payments','complaints','reviews','checklistReports','photoReports','cleaners','users','preorders','quality','addressRequests','payouts','audit','zones','houses','checklistTemplates','packages','addons','addonGroups','banners','promotions','promotionRedemptions','contentPages','videoViews']) {
        assert.equal((await request('/admin/'+section)).status,200,section);
        assert.equal((await request('/admin/'+section,'GET',undefined,true)).status,403,section+' permissions');
      }
      const rows=(await request('/admin/cleaners?status=pending&search=Тестовая')).json.data;
      const row=rows.find((item:any)=>item.id===cleaner);
      assert.equal(row.full_name,'Тестовая анкета');
      assert.equal(row.verification_status,'pending');
      assert.equal(row.documents[0].url,'https://example.com/document');
      assert.equal((await request('/admin/cleaners/'+cleaner+'/details')).json.data.documents[0].public_url,'https://example.com/document');
    });
    await t.test('all cities and address matches beyond the first 500 are available',async()=>{
      assert.equal((await request('/geo/cities?limit=200')).json.data.length,90);
      assert.equal((await request('/geo/cities?search=Капчагай')).json.data[0].name_ru,'Конаев');
      assert.equal((await request('/geo/cities?search=Косшы')).json.data[0].name_ru,'Косшы');
      await db.query(`INSERT INTO connected_houses(city,street_ru,house,active)
        SELECT $1,'Ааа тест',n::text,FALSE FROM generate_series(1,501) n`,[housePrefix]);
      await db.query(`INSERT INTO connected_houses(city,street_ru,house,active) VALUES($1,'Момышұлы','14',FALSE)`,[housePrefix]);
      const rows=(await request('/geo/address-suggestions?city='+housePrefix+'&search=Момышулы%2014&limit=1')).json.data.suggestions;
      assert.equal(rows.length,1);assert.equal(rows[0].house,'14');
      assert.equal(rows[0].source,'address_directory');assert.equal(rows[0].connected,false);
    });
    await t.test('admin can create, edit and hide catalogue and geography records',async()=>{
      const name=housePrefix;
      const pkg=await request('/admin/catalog/packages','POST',{nameRu:name,cleaningCount:2,months:1,basePrice:0,pricePerM2:180,features:['Поддерживающая уборка']});
      assert.equal(pkg.status,201);catalogIds.pkg=pkg.json.data.id;
      assert.equal((await request('/admin/catalog/packages/'+catalogIds.pkg,'PATCH',{nameRu:name+' edited',pricePerM2:190})).status,200);
      assert.equal((await request('/admin/packages/'+catalogIds.pkg+'/active','PATCH',{active:false})).status,200);
      const group=await request('/admin/catalog/addon-groups','POST',{titleRu:name});
      assert.equal(group.status,201);catalogIds.group=group.json.data.id;
      const addon=await request('/admin/catalog/addons','POST',{titleRu:name,groupId:catalogIds.group,price:2000,durationMinutes:30});
      assert.equal(addon.status,201);catalogIds.addon=addon.json.data.id;
      assert.equal((await request('/admin/catalog/addons/'+catalogIds.addon,'PATCH',{price:2500})).status,200);
      const zone=await request('/admin/service-zones','POST',{nameRu:name,city:housePrefix,polygon:[{lat:51.1,lng:71.4},{lat:51.2,lng:71.4},{lat:51.1,lng:71.5}]});
      assert.equal(zone.status,201);catalogIds.zone=zone.json.data.id;
      assert.equal((await request('/admin/service-zones/'+catalogIds.zone,'PATCH',{polygon:[{lat:51.1,lng:71.4}]})).status,200);
      const house=await request('/admin/connected-houses','POST',{city:housePrefix,streetRu:'Тестовая',house:'15',zoneId:catalogIds.zone,active:false});
      assert.equal(house.status,201);catalogIds.house=house.json.data.id;
      assert.equal((await request('/admin/connected-houses/'+catalogIds.house,'PATCH',{active:true})).status,200);
    });
    await t.test('payment cards include customer, package, address and creation date',async()=>{
      const address=randomUUID(),purchase=randomUUID(),payment=randomUUID();
      try {
        await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,apartment,area,verified_area) VALUES($1,$2,'Астана','Test Street','14','5',100,100)",[address,customer]);
        await db.query('INSERT INTO customer_packages(id,customer_id,package_id,address_id,total_cleanings,available_cleanings) VALUES($1,$2,$3,$4,2,2)',[purchase,customer,catalogIds.pkg,address]);
        await db.query("INSERT INTO payments(id,customer_id,customer_package_id,provider,status,amount,invoice_phone) VALUES($1,$2,$3,'kaspi','invoice_requested',22000,'+77000000000')",[payment,customer,purchase]);
        const row=(await request('/admin/payments')).json.data.find((item:any)=>item.id===payment);
        assert.equal(row.customer_name,'Тестовая анкета');
        assert.equal(row.customer_phone,'admin-test-'+customer);
        assert.equal(row.package_name_ru,housePrefix+' edited');
        assert.equal(row.street,'Test Street');assert.equal(row.house,'14');assert.equal(row.apartment,'5');
        assert.equal(Number(row.verified_area),100);
        assert.ok(row.created_at);assert.equal(row.invoice_phone,'+77000000000');
      } finally {
        await db.query('DELETE FROM payments WHERE id=$1',[payment]);
        await db.query('DELETE FROM customer_packages WHERE id=$1',[purchase]);
        await db.query('DELETE FROM customer_addresses WHERE id=$1',[address]);
      }
    });
    await t.test('failed notification persistence rolls back the entire decision',async()=>{
      await assert.rejects(verifyCleaner(db,{persist:async()=>{throw Error('Storage failure');}} as any,cleaner,'approved',admin));
      const state=(await db.query('SELECT u.status,cp.verification_status FROM app_users u JOIN cleaner_profiles cp ON cp.user_id=u.id WHERE u.id=$1',[cleaner])).rows[0];
      assert.equal(state.status,'pending');assert.equal(state.verification_status,'pending');
      assert.equal((await db.query('SELECT status FROM cleaner_documents WHERE cleaner_id=$1',[cleaner])).rows[0].status,'pending');
    });
    await t.test('approve is atomic and repeated clicks do not duplicate notifications',async()=>{
      failPush=true;
      for(let i=0;i<2;i++)assert.equal((await request('/admin/cleaners/'+cleaner+'/verification','PATCH',{status:'approved'})).status,200);
      const state=(await db.query('SELECT u.status,cp.verification_status,cp.verified_at FROM app_users u JOIN cleaner_profiles cp ON cp.user_id=u.id WHERE u.id=$1',[cleaner])).rows[0];
      assert.equal(state.status,'approved');assert.equal(state.verification_status,'approved');assert.ok(state.verified_at);
      assert.equal((await db.query('SELECT status FROM cleaner_documents WHERE cleaner_id=$1',[cleaner])).rows[0].status,'approved');
      assert.equal(Number((await db.query('SELECT COUNT(*) FROM notifications WHERE user_id=$1',[cleaner])).rows[0].count),1);
      assert.equal(Number((await db.query("SELECT COUNT(*) FROM audit_logs WHERE actor_id=$1 AND action='cleaner.verification'",[admin])).rows[0].count),1);
    });
    await t.test('reject, block and pending keep user, profile and documents consistent',async()=>{
      failPush=false;
      for(const status of ['rejected','blocked','pending']){
        const res=await request('/admin/cleaners/'+cleaner+'/verification','PATCH',{status});
        assert.equal(res.status,200);assert.equal(res.json.data.cleaner.status,status);assert.equal(res.json.data.profile.verification_status,status);assert.equal(res.json.data.profile.verified_at,null);
        assert.equal((await db.query('SELECT status FROM cleaner_documents WHERE cleaner_id=$1',[cleaner])).rows[0].status,status);
      }
      assert.equal((await request('/admin/cleaners/'+cleaner+'/verification','PATCH',{status:'wrong'})).status,400);
      assert.equal((await request('/admin/cleaners/'+customer+'/verification','PATCH',{status:'approved'})).status,404);
    });
    await t.test('area photo request persists an owned file and admin can review it',async()=>{
      const ownFile=randomUUID();
      await db.query("INSERT INTO files(id,owner_id,bucket,object_key,public_url) VALUES($1::uuid,$2,'test',$1::text,'https://example.com/area-plan')",[ownFile,customer]);
      try {
        assert.equal((await request('/quality-checks/from-file','POST',{actualArea:100,fileId:file},true)).status,404);
        assert.equal((await request('/quality-checks/from-file','POST',{actualArea:100,addressId:randomUUID(),fileId:ownFile},true)).status,404);
        assert.equal((await request('/quality-checks/from-file','POST',{actualArea:100,fileUrl:'upload-error://fake'},true)).status,404);
        assert.equal((await request('/quality-checks/from-file','POST',{actualArea:100,fileUrl:'https://example.com/area-plan'},true)).status,201);
        const result=await request('/quality-checks/from-file','POST',{actualArea:100,fileId:ownFile},true);
        assert.equal(result.status,201);assert.equal(result.json.data.request.document_file_id,ownFile);
        const rows=(await request('/admin/quality')).json.data;
        assert.equal(rows.find((row:any)=>row.id===result.json.data.request.id).areaTechnicalPlanUrl,'https://example.com/area-plan');
        assert.equal((await request('/admin/quality-checks/'+result.json.data.request.id,'PATCH',{adminComment:'Проверено',approvedArea:100,status:'approved'})).status,200);
        assert.equal((await request('/quality-checks/from-file','POST',{actualArea:0,fileId:ownFile},true)).status,400);
      } finally {
        await db.query('DELETE FROM quality_check_requests WHERE customer_id=$1',[customer]);
        await db.query('DELETE FROM files WHERE id=$1',[ownFile]);
      }
    });
    await t.test('concurrent admin assignments cannot double-book a cleaner',async()=>{
      const ids=[randomUUID(),randomUUID()];
      try {
        for(const id of ids)await db.query("INSERT INTO service_orders(id,customer_id,status,scheduled_date,start_time,end_time) VALUES($1,$2,'pending_assignment','2035-01-01','10:00','12:00')",[id,customer]);
        const results=await Promise.all(ids.map(id=>request('/admin/orders/'+id+'/assign-cleaner','POST',{cleanerId:cleaner})));
        assert.equal(results.filter(r=>r.status===200).length,1);
        assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM service_orders WHERE id=ANY($1::uuid[]) AND cleaner_id=$2',[ids,cleaner])).rows[0].n,1);
      } finally {
        await db.query('DELETE FROM notifications WHERE target_id=ANY($1::text[])',[ids]);
        await db.query('DELETE FROM service_orders WHERE id=ANY($1::uuid[])',[ids]);
      }
    });

    await t.test('checklist template search and date filters remain valid SQL',async()=>{
      for(const query of ['?search=absent','?dateFrom=2000-01-01&dateTo=2099-01-01','?search=absent&offset=5&limit=5'])assert.equal((await request('/admin/checklistTemplates'+query)).status,200);
    });
    await t.test('ordinary users cannot grant themselves a bonus',async()=>{
      const before=(await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[customer])).rows[0].bonus_balance;
      assert.equal((await request('/bonus/transactions','POST',{amount:100000},true)).status,403);
      assert.equal((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[customer])).rows[0].bonus_balance,before);
    });
    await t.test('complaints are scoped to the customer and available to admin',async()=>{
      await db.query("INSERT INTO complaints(customer_id,title,body) VALUES($1,'Тестовая жалоба','Тест')",[customer]);
      assert.equal((await request('/complaints','GET',undefined,true)).status,200);
      const res=await request('/admin/complaints');assert.equal(res.status,200);assert.ok(res.json.data.some((row:any)=>row.customer_id===customer));
      assert.equal((await request('/complaints')).status,403);
    });
  } finally {
    await new Promise<void>(resolve=>server.close(()=>resolve()));
    await db.query('DELETE FROM connected_houses WHERE city=$1',[housePrefix]);
    if(catalogIds.zone)await db.query('DELETE FROM service_zones WHERE id=$1',[catalogIds.zone]);
    if(catalogIds.addon)await db.query('DELETE FROM catalog_addons WHERE id=$1',[catalogIds.addon]);
    if(catalogIds.group)await db.query('DELETE FROM addon_groups WHERE id=$1',[catalogIds.group]);
    if(catalogIds.pkg)await db.query('DELETE FROM catalog_packages WHERE id=$1',[catalogIds.pkg]);
    await db.query('DELETE FROM complaints WHERE customer_id=$1',[customer]);
    await db.query('DELETE FROM audit_logs WHERE actor_id=$1',[admin]);
    await db.query('DELETE FROM cleaner_documents WHERE cleaner_id=$1',[cleaner]);
    await db.query('DELETE FROM files WHERE id=$1',[file]);
    await db.query('DELETE FROM files WHERE owner_id=ANY($1::uuid[])',[[admin,cleaner,customer]]);
    await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[admin,cleaner,customer]]);
    await db.close();
  }
});

test('purchase idempotency and legacy payment callback authentication',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
  const {BonusService,PaymentService,PricingService}=await import('../modules/domainServices');
  const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),customer=randomUUID(),pkg=randomUUID(),address=randomUUID();
  const bonuses=new BonusService(db);const notifications=new NotificationService(db,{send:async()=>({sent:0})} as any);
  const app=express();app.use(express.json(),buildV1Router({db,bonuses,payments:new PaymentService(db,bonuses),pricing:new PricingService(),notifications,paymentGateway:{createKaspiInvoice:async()=>null},scheduling:new SchedulingService(db)} as any),errorHandler);
  const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
  const token=signAccessToken({id:customer,role:'customer',phone:'audit-'+customer});const previousToken=env.kaspiWebhookToken,previousMoon=env.moonAiEnabled;env.moonAiEnabled=false;env.kaspiWebhookToken=randomUUID();
  try{
    await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[customer,'audit-'+customer]);
    await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,months,base_price,price_per_m2) VALUES($1,$2,1,1,0,10)",[pkg,'Аудит '+pkg]);
    await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area) VALUES($1,$2,'Астана','Аудит','1',100)",[address,customer]);
    const body={packageId:pkg,addressId:address,provider:'kaspi',idempotencyKey:randomUUID()};
    const purchase=()=>fetch(base+'/packages/purchase',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});
    const responses=await Promise.all([purchase(),purchase(),purchase()]);assert.ok(responses.every(r=>r.status===200));const rows=await Promise.all(responses.map(r=>r.json() as Promise<any>));assert.equal(new Set(rows.map(r=>r.data.customerPackage.id)).size,1);
    assert.equal((await db.query('SELECT COUNT(*)::int AS n FROM customer_packages WHERE customer_id=$1',[customer])).rows[0].n,1);
    const id=rows[0].data.payment.id;
    const hook=(secret?:string)=>fetch(base+'/payments/kaspi/webhook',{method:'POST',headers:{'Content-Type':'application/json',...(secret?{'X-Kaspi-Token':secret}:{})},body:JSON.stringify({paymentId:id,status:'paid'})});
    assert.equal((await hook()).status,401);assert.equal((await hook('wrong')).status,401);
    assert.notEqual((await db.query('SELECT status FROM payments WHERE id=$1',[id])).rows[0].status,'paid');
    assert.equal((await hook(env.kaspiWebhookToken)).status,200);assert.equal((await hook(env.kaspiWebhookToken)).status,200);
    const cp=(await db.query('SELECT status,available_cleanings FROM customer_packages WHERE customer_id=$1',[customer])).rows[0];assert.equal(cp.status,'active');assert.equal(cp.available_cleanings,1);
    const orderBody={customerPackageId:rows[0].data.customerPackage.id,date:'2035-01-03',startTime:'08:00',idempotencyKey:randomUUID()};
    const orders=await Promise.all([1,2,3].map(()=>fetch(base+'/orders',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(orderBody)})));
    assert.ok(orders.every(r=>r.status===201));
    const booked=await Promise.all(orders.map(r=>r.json() as Promise<any>));assert.equal(new Set(booked.map(r=>r.data.order.id)).size,1);
    assert.equal((await db.query('SELECT available_cleanings FROM customer_packages WHERE customer_id=$1',[customer])).rows[0].available_cleanings,0);
  }finally{
    env.kaspiWebhookToken=previousToken;env.moonAiEnabled=previousMoon;
    await new Promise<void>(r=>server.close(()=>r()));
    await db.query('DELETE FROM notifications WHERE user_id=$1 OR target_id IN(SELECT id::text FROM service_orders WHERE customer_id=$1)',[customer]);
    await db.query('DELETE FROM quality_check_requests WHERE customer_id=$1',[customer]);
    await db.query('DELETE FROM service_orders WHERE customer_id=$1',[customer]);
    await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[customer]);
    await db.query('DELETE FROM payment_events WHERE payment_id IN(SELECT id FROM payments WHERE customer_id=$1)',[customer]);
    await db.query('DELETE FROM payments WHERE customer_id=$1',[customer]);
    await db.query('DELETE FROM quality_check_requests WHERE customer_id=$1',[customer]);
    await db.query('DELETE FROM notifications WHERE user_id=$1',[customer]);
    await db.query('DELETE FROM customer_packages WHERE customer_id=$1',[customer]);
    await db.query('DELETE FROM app_users WHERE id=$1',[customer]);await db.query('DELETE FROM catalog_packages WHERE id=$1',[pkg]);await db.close();
  }
});


test('health database timeout returns 503 and the same process recovers',async()=>{
  const {healthHandler}=await import('../http/health');
  let fail=true;
  const app=express();app.get('/health',healthHandler({query:async()=>{if(fail)throw Error('connection timeout');return {rows:[]};}} as any));
  const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
  const url='http://127.0.0.1:'+(server.address() as AddressInfo).port+'/health';
  try{assert.equal((await fetch(url)).status,503);fail=false;assert.equal((await fetch(url)).status,200);}
  finally{await new Promise<void>(r=>server.close(()=>r()));}
});
