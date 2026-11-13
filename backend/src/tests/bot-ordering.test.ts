import {serviceCoverageRouter} from '../http/routes/serviceCoverage';
import {checkServiceAddress,invalidateServiceAddress,requestAddressConnection} from '../modules/serviceCoverage';
import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {randomUUID} from 'node:crypto';
import {AddressInfo} from 'node:net';
import {Database} from '../infrastructure/db/Database';
import {env} from '../common/env';
import {configureAuthDatabase,signAccessToken} from '../common/auth';
import {errorHandler} from '../common/api';
import {botAuditRouter} from '../http/routes/botAudit';
import {botActionTitle,botAuditContext,botAuditSnapshot} from '../modules/botAudit';
import {buildV1Router} from '../http/routes/v1';
import {BonusService,PaymentService,NotificationService,SchedulingService} from '../modules/domainServices';

test('bot ordering: real transactions, scopes, provider proof, audit and concurrent last slot',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),users=[randomUUID(),randomUUID()],cleaner=randomUUID(),catalog=randomUUID(),addresses=[randomUUID(),randomUUID()],packages=[randomUUID(),randomUUID()];
 const phones=['+7701'+String(Date.now()).slice(-7),'+7702'+String(Date.now()).slice(-7)];
 const saved={token:env.moonAiOrderingToken,enabled:env.moonAiEnabled};env.moonAiOrderingToken='fixture-ordering-token-never-use-in-production';env.moonAiEnabled=false;
 let invoices=0;const notifications=new NotificationService(db,{send:async()=>({sent:0})} as any);
 const app=express();app.use(express.json(),buildV1Router({db,notifications,payments:new PaymentService(db,new BonusService(db)),scheduling:new SchedulingService(db),paymentGateway:{createKaspiInvoice:async()=>{invoices++;return {provider:'kaspi',queued:true};}}} as any),errorHandler);
 const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));const base='http://127.0.0.1:'+(server.address() as AddressInfo).port+'/integrations/moon-ai/ordering';
 const call=async(path:string,body?:any,key=randomUUID(),token=env.moonAiOrderingToken)=>{
  const response=await fetch(base+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json','X-MoonAI-Ordering-Token':token,'Idempotency-Key':key},body:body?JSON.stringify(body):undefined});return {status:response.status,body:await response.json() as any};
 };
 try{
  for(let i=0;i<2;i++)await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[users[i],phones[i]]);
  await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'cleaner','approved')",[cleaner,'bot-fixture-'+cleaner]);
  await db.query("INSERT INTO cleaner_profiles(user_id,verification_status) VALUES($1,'approved')",[cleaner]);
  const schedule=(await db.query("INSERT INTO cleaner_work_schedule_requests(cleaner_id,week_start,days,status) VALUES($1,'2038-06-07','[]','approved') RETURNING id",[cleaner])).rows[0];
  await db.query("INSERT INTO cleaner_working_days(cleaner_id,work_date,start_time,end_time,request_id) VALUES($1,'2038-06-08','08:00','18:00',$2)",[cleaner,schedule.id]);
  await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,months,base_price,price_per_m2) VALUES($1,$2,4,1,1000,0)",[catalog,'Bot fixture '+catalog]);
  for(let i=0;i<2;i++){
   await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area,verified_area) VALUES($1,$2,'Астана','Fixture','1',50,50)",[addresses[i],users[i]]);
   await db.query("INSERT INTO customer_packages(id,customer_id,package_id,address_id,total_cleanings,available_cleanings,status) VALUES($1,$2,$3,$4,4,4,'active')",[packages[i],users[i],catalog,addresses[i]]);
  }
  await t.test('webhook token is not an ordering credential; unauthenticated requests cannot read customers',async()=>{
   assert.equal((await call('/customer?phone='+encodeURIComponent(phones[0]),undefined,randomUUID(),'wrong')).status,401);
   assert.equal((await call('/customer?phone='+encodeURIComponent(phones[0]))).body.data.packages.length,1);
  });
  await t.test('purchase cannot use another customer address and failures are audited without acting as customer',async()=>{
   const r=await call('/packages',{phone:phones[0],packageId:catalog,addressId:addresses[1],confirmedByCustomer:true});assert.equal(r.status,400);
   assert.equal((await db.query("SELECT COUNT(*)::int n FROM audit_logs WHERE action='bot.moon-ai.package_purchase' AND payload->>'customerId'=$1 AND payload->>'result'='error' AND actor_id IS NULL",[users[0]])).rows[0].n,1);
  });
  let paymentId='';
  await t.test('five concurrent purchase retries create one package, one invoice and one durable replay',async()=>{
   const key=randomUUID(),body={phone:phones[0],packageId:catalog,addressId:addresses[0],confirmedByCustomer:true};
   const replies=await Promise.all(Array.from({length:5},()=>call('/packages',body,key)));
   assert.ok(replies.every(r=>r.status===200),JSON.stringify(replies));assert.equal(invoices,1);
   paymentId=replies[0].body.data.payment.id;
   for(const r of replies)assert.equal(r.body.data.payment.id,paymentId);
   assert.equal((await call('/packages',{...body,addressId:addresses[1]},key)).status,409);
   const p=(await db.query('SELECT payload FROM payments WHERE id=$1',[paymentId])).rows[0];assert.equal(p.payload.createdBy,'bot');
   assert.equal((await db.query("SELECT COUNT(*)::int n FROM audit_logs WHERE action='bot.moon-ai.package_purchase' AND entity_id=$1 AND payload->>'actorKind'='bot' AND actor_id IS NULL",[paymentId])).rows[0].n,1);
  });
  await t.test('caller cannot forge a paid status; pending invoice does not activate package or allow booking',async()=>{
   const r=await call('/payments/verify',{phone:phones[0],paymentId,status:'paid',paid:true});assert.equal(r.status,200,JSON.stringify(r));
   assert.equal(r.body.data.readyToBook,false);assert.equal(r.body.data.payment.status,'pending');
   const attempt=await call('/orders',{phone:phones[0],customerPackageId:r.body.data.customerPackage.id,date:'2038-06-08',startTime:'10:00',confirmedByCustomer:true});assert.equal(attempt.status,402);
   const q=(await db.query('SELECT purchase_config FROM customer_packages WHERE id=$1',[r.body.data.customerPackage.id])).rows[0];assert.equal(q.purchase_config.createdBy,'bot');
  });
  await t.test('verified provider state activates once; the admin audit explicitly names the bot',async()=>{
   // Simulate a trusted provider settlement in the isolated fixture, never an HTTP claim.
   await db.query("UPDATE payments SET status='paid',paid_at=NOW(),approval_source='moon_ai' WHERE id=$1",[paymentId]);
   const verified=await call('/payments/verify',{phone:phones[0],paymentId});
   assert.equal(verified.status,200,JSON.stringify(verified));assert.equal(verified.body.data.readyToBook,true);
   const again=await call('/payments/verify',{phone:phones[0],paymentId});
   assert.equal(again.body.data.customerPackage.available_cleanings,verified.body.data.customerPackage.available_cleanings);
   const token=signAccessToken({id:users[0],phone:phones[0],role:'superadmin'});
   const response=await fetch(base.replace('/integrations/moon-ai/ordering','')+'/admin/audit?search=bot.moon-ai&limit=100',{headers:{Authorization:'Bearer '+token}});
   assert.equal(response.status,200);
   const data:any=await response.json();assert.ok(data.data.some((row:any)=>row.entity_id===paymentId&&row.actor_name==='Бот MooonAI'&&row.actor_id===null));
  });
  await t.test('concurrent bookings compete atomically for one cleaner; losing request spends no cleaning',async()=>{
   const replies=await Promise.all(users.map((_,i)=>call('/orders',{phone:phones[i],customerPackageId:packages[i],date:'2038-06-08',startTime:'18:00',confirmedByCustomer:true})));
   assert.deepEqual(replies.map(r=>r.status).sort(),[200,409],JSON.stringify(replies));
   const orders=(await db.query('SELECT * FROM service_orders WHERE customer_id=ANY($1::uuid[])',[users])).rows;assert.equal(orders.length,1);
   const balances=(await db.query('SELECT available_cleanings FROM customer_packages WHERE id=ANY($1::uuid[])',[packages])).rows.map(r=>r.available_cleanings).sort();assert.deepEqual(balances,[3,4]);
   const winner=users.indexOf(orders[0].customer_id);
   assert.equal((await call('/orders',{phone:phones[winner],customerPackageId:packages[winner],date:'2038-06-08',startTime:'18:00',confirmedByCustomer:true})).body.code,'customer_booking_overlap');
   assert.equal((await call('/orders',{phone:phones[1-winner],customerPackageId:packages[1-winner],date:'2038-06-08',startTime:'18:05',confirmedByCustomer:true})).status,400);
  });
 }finally{
  env.moonAiOrderingToken=saved.token;env.moonAiEnabled=saved.enabled;
  await new Promise<void>(r=>server.close(()=>r()));
  await db.query('DELETE FROM bot_ordering_requests WHERE customer_id=ANY($1::uuid[])',[users]);
  await db.query("DELETE FROM audit_logs WHERE payload->>'customerId'=ANY($1::text[]) OR entity_id IN(SELECT id::text FROM payments WHERE customer_id=ANY($1::uuid[]))",[users]);
  await db.query('DELETE FROM notifications WHERE user_id=ANY($1::uuid[]) OR target_id IN(SELECT id::text FROM service_orders WHERE customer_id=ANY($1::uuid[]))',[users]);
  await db.query('DELETE FROM service_orders WHERE customer_id=ANY($1::uuid[])',[users]);
  await db.query('DELETE FROM payment_events WHERE payment_id IN(SELECT id FROM payments WHERE customer_id=ANY($1::uuid[]))',[users]);
  await db.query('DELETE FROM customer_package_periods WHERE customer_package_id IN(SELECT id FROM customer_packages WHERE customer_id=ANY($1::uuid[]))',[users]);
  await db.query('UPDATE customer_packages SET purchase_payment_id=NULL WHERE customer_id=ANY($1::uuid[])',[users]);
  await db.query('DELETE FROM payments WHERE customer_id=ANY($1::uuid[])',[users]);
  await db.query('DELETE FROM customer_packages WHERE customer_id=ANY($1::uuid[])',[users]);
  await db.query('DELETE FROM customer_addresses WHERE user_id=ANY($1::uuid[])',[users]);
  await db.query('DELETE FROM catalog_packages WHERE id=$1',[catalog]);
  await db.query('DELETE FROM cleaner_working_days WHERE cleaner_id=$1',[cleaner]);await db.query('DELETE FROM cleaner_work_schedule_requests WHERE cleaner_id=$1',[cleaner]);
  await db.query('DELETE FROM cleaner_profiles WHERE user_id=$1',[cleaner]);await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[...users,cleaner]]);await db.close();
 }
});


test('strict service zones: database boundary, connection-only fallback and fresh address proof',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
 const user=randomUUID(),zone=randomUUID(),house=randomUUID(),inside=randomUUID(),outside=randomUUID(),catalog=randomUUID(),pkg=randomUUID(),payment=randomUUID(),order=randomUUID(),oldFile=randomUUID(),freshFile=randomUUID(),oldReview=randomUUID(),freshReview=randomUUID();
 const city='Coverage fixture '+zone;
 const notices=new NotificationService(db,{send:async()=>({sent:0})} as any);
 const previous=(await db.query("SELECT value FROM app_settings WHERE key='enforceServiceZones'")).rows[0];
 await db.query("INSERT INTO app_settings(key,value) VALUES('enforceServiceZones','false') ON CONFLICT(key) DO UPDATE SET value='false'");
 configureAuthDatabase(db);
 const app=express();app.use(express.json(),serviceCoverageRouter(db,notices),errorHandler);
 const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
 const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
 const request=async(path:string,body:any)=>{const res=await fetch(base+path,{method:'POST',headers:{Authorization:'Bearer '+signAccessToken({id:user,phone:'fixture',role:'customer'}),'Content-Type':'application/json'},body:JSON.stringify(body)});return {status:res.status,body:await res.json() as any};};
 try{
  await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[user,'coverage-'+user]);
  await db.query("INSERT INTO service_zones(id,name_ru,city,polygon) VALUES($1,$2,$2,$3)",[zone,city,JSON.stringify([{lat:50,lng:70},{lat:52,lng:70},{lat:52,lng:72},{lat:50,lng:72}])]);
  await db.query("INSERT INTO connected_houses(id,city,street_ru,house,zone_id,active) VALUES($1,$2,'Внутри','1',$3,TRUE)",[house,city,zone]);
  await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area,verified_area) VALUES($1,$2,$3,'Внутри','1',50,50)",[inside,user,city]);
  await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area,verified_area) VALUES($1,$2,'Астана','Қосшы вне зоны','9',50,50)",[outside,user]);
  await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,months,base_price,price_per_m2) VALUES($1,$2,4,1,1000,0)",[catalog,city]);
  await db.query("INSERT INTO customer_packages(id,customer_id,package_id,address_id,total_cleanings,available_cleanings,status) VALUES($1,$2,$3,$4,4,4,'active')",[pkg,user,catalog,outside]);
  await db.query("INSERT INTO payments(id,customer_id,customer_package_id,provider,amount,status) VALUES($1,$2,$3,'kaspi',1000,'paid')",[payment,user,pkg]);
  await db.query('UPDATE customer_packages SET purchase_payment_id=$2 WHERE id=$1',[pkg,payment]);
  await db.query("INSERT INTO service_orders(id,customer_id,customer_package_id,address_id,package_id,scheduled_date,start_time,end_time,status) VALUES($1,$2,$3,$4,$5,'2038-06-08','12:00','14:00','assigned')",[order,user,pkg,outside,catalog]);
  await db.query("INSERT INTO files(id,owner_id,bucket,object_key,public_url,created_at) VALUES($1,$2,'test',$3,'https://example.com/old-plan',NOW()-INTERVAL '1 day')",[oldFile,user,oldFile]);
  await db.query("INSERT INTO quality_check_requests(id,customer_id,address_id,requested_area,status,document_file_id) VALUES($1,$2,$3,50,'approved',$4)",[oldReview,user,outside,oldFile]);
  await db.query("UPDATE app_settings SET value='true' WHERE key='enforceServiceZones'");
  await t.test('checks the active polygon and connected house instead of the Astana label',async()=>{
   await checkServiceAddress(db,inside);
   await assert.rejects(checkServiceAddress(db,outside),(e:any)=>e.code==='outside_service_zone');
   const geometry=(await db.query("SELECT domly_polygon_contains($1,51,71) AS inside,domly_polygon_contains($1,60,80) AS outside",[JSON.stringify([{lat:50,lng:70},{lat:52,lng:70},{lat:52,lng:72}])])).rows[0];assert.equal(geometry.inside,true);assert.equal(geometry.outside,false);
   const geo=(await db.query("SELECT domly_polygon_contains($1,51,71) AS hole,domly_polygon_contains($1,50.2,70.2) AS covered,domly_city_key('г. Нур-Султан')=domly_city_key('Astana') AS alias",[JSON.stringify({type:'Polygon',coordinates:[[[70,50],[72,50],[72,52],[70,52],[70,50]],[[70.5,50.5],[71.5,50.5],[71.5,51.5],[70.5,51.5],[70.5,50.5]]]})])).rows[0];assert.equal(geo.hole,false);assert.equal(geo.covered,true);assert.equal(geo.alias,true);
   await db.query('UPDATE service_zones SET active=FALSE WHERE id=$1',[zone]);await assert.rejects(checkServiceAddress(db,inside));await db.query('UPDATE service_zones SET active=TRUE WHERE id=$1',[zone]);
  });
  await t.test('old-client purchase attempts create one connection request and no charge',async()=>{
   const replies=await Promise.all([request('/packages/purchase',{addressId:outside,packageId:catalog}),request('/packages/purchase',{addressId:outside,packageId:catalog})]);assert.ok(replies.every(r=>r.status===409&&r.body.code==='outside_service_zone'));
   assert.equal((await db.query('SELECT COUNT(*)::int n FROM service_address_requests WHERE customer_id=$1',[user])).rows[0].n,1);
   assert.equal((await db.query('SELECT COUNT(*)::int n FROM payments WHERE customer_id=$1',[user])).rows[0].n,1);
   assert.equal((await db.query('SELECT COUNT(*)::int n FROM customer_packages WHERE customer_id=$1',[user])).rows[0].n,1);
  });
  await t.test('database also rejects direct/bot package creation, invoices, booking and cleaner start',async()=>{
   for(const operation of [()=>db.query("INSERT INTO customer_packages(customer_id,package_id,address_id,total_cleanings,available_cleanings) VALUES($1,$2,$3,4,4)",[user,catalog,outside]),()=>db.query("INSERT INTO payments(customer_id,customer_package_id,provider,amount,status) VALUES($1,$2,'kaspi',1000,'pending')",[user,pkg]),()=>db.query("INSERT INTO service_orders(customer_id,customer_package_id,address_id,package_id,scheduled_date,start_time,end_time,status) VALUES($1,$2,$3,$4,'2038-06-09','12:00','14:00','pending_assignment')",[user,pkg,outside,catalog]),()=>db.query("UPDATE service_orders SET status='start_pending' WHERE id=$1",[order])])await assert.rejects(operation(),(e:any)=>e.code==='PZ001');
  });
  await t.test('invalidation is idempotent, preserves paid visits and queues profile push plus native WhatsApp',async()=>{
   await Promise.all([invalidateServiceAddress(db,notices,outside,user),invalidateServiceAddress(db,notices,outside,user)]);
   const a=(await db.query('SELECT * FROM customer_addresses WHERE id=$1',[outside])).rows[0];assert.equal(a.service_status,'needs_new_address');assert.equal(a.verified_area,null);assert.equal(a.area_reverification_required,true);
   assert.equal((await db.query('SELECT available_cleanings FROM customer_packages WHERE id=$1',[pkg])).rows[0].available_cleanings,4);assert.equal((await db.query('SELECT status FROM payments WHERE id=$1',[payment])).rows[0].status,'paid');
   assert.equal((await db.query("SELECT COUNT(*)::int n FROM moon_ai_outbox WHERE customer_id=$1 AND kind='address_reverification'",[user])).rows[0].n,1);
   assert.equal((await db.query("SELECT COUNT(*)::int n FROM notifications WHERE user_id=$1 AND target_type='address_request'",[user])).rows[0].n,1);
  });
  await t.test('changing to a covered address cannot reuse the old plan or its approval',async()=>{
   await db.query("UPDATE customer_addresses SET city=$2,street='Внутри',house='1' WHERE id=$1",[outside,city]);
   await assert.rejects(checkServiceAddress(db,outside),(e:any)=>e.code==='address_area_reverification_required');
   await assert.rejects(db.query('UPDATE customer_addresses SET verified_area=50 WHERE id=$1',[outside]),(e:any)=>e.code==='PZ002');
   await db.query("INSERT INTO files(id,owner_id,bucket,object_key,public_url) VALUES($1,$2,'test',$3,'https://example.com/new-plan')",[freshFile,user,freshFile]);
   await db.query("INSERT INTO quality_check_requests(id,customer_id,address_id,requested_area,status,document_file_id) VALUES($1,$2,$3,50,'pending',$4)",[freshReview,user,outside,freshFile]);
   await db.query('UPDATE customer_addresses SET verified_area=50 WHERE id=$1',[outside]);await checkServiceAddress(db,outside);
   assert.equal((await db.query('SELECT area_reverification_required FROM customer_addresses WHERE id=$1',[outside])).rows[0].area_reverification_required,false);
  });
 }finally{
  await new Promise<void>(r=>server.close(()=>r()));configureAuthDatabase(null);
  await db.query("UPDATE app_settings SET value='false' WHERE key='enforceServiceZones'");
  await db.query('DELETE FROM notifications WHERE user_id=$1 OR target_id IN(SELECT id::text FROM service_address_requests WHERE customer_id=$1)',[user]);
  await db.query('DELETE FROM moon_ai_outbox WHERE customer_id=$1',[user]);await db.query('DELETE FROM chat_messages WHERE chat_id IN(SELECT id FROM chats WHERE customer_id=$1)',[user]);await db.query('DELETE FROM chats WHERE customer_id=$1',[user]);
  await db.query("DELETE FROM audit_logs WHERE payload->>'customerId'=$1",[user]);await db.query('DELETE FROM service_address_requests WHERE customer_id=$1',[user]);await db.query('DELETE FROM quality_check_requests WHERE customer_id=$1',[user]);await db.query('DELETE FROM files WHERE owner_id=$1',[user]);
  await db.query('DELETE FROM service_orders WHERE id=$1',[order]);await db.query('UPDATE customer_packages SET purchase_payment_id=NULL WHERE id=$1',[pkg]);await db.query('DELETE FROM payments WHERE id=$1',[payment]);await db.query('DELETE FROM customer_packages WHERE id=$1',[pkg]);await db.query('DELETE FROM customer_addresses WHERE user_id=$1',[user]);await db.query('DELETE FROM connected_houses WHERE id=$1',[house]);await db.query('DELETE FROM service_zones WHERE id=$1',[zone]);await db.query('DELETE FROM catalog_packages WHERE id=$1',[catalog]);await db.query('DELETE FROM app_users WHERE id=$1',[user]);
  if(previous)await db.query("UPDATE app_settings SET value=$1 WHERE key='enforceServiceZones'",[previous.value]);else await db.query("DELETE FROM app_settings WHERE key='enforceServiceZones'");await db.close();
 }
});

test('bot audit descriptions, ownership and safe financial details',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),admin=randomUUID(),customer=randomUUID(),cleaner=randomUUID(),catalog=randomUUID(),address=randomUUID(),purchase=randomUUID(),payment=randomUUID(),order=randomUUID(),event=randomUUID(),legacy=randomUUID(),human=randomUUID();
 configureAuthDatabase(db);const app=express();app.use(botAuditRouter(db),errorHandler);const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
 const request=async(path:string,role:'superadmin'|'customer'='superadmin')=>{const res=await fetch(base+path,{headers:{Authorization:'Bearer '+signAccessToken({id:role==='customer'?customer:admin,phone:'fixture',role})}});return {status:res.status,data:await res.json() as any};};
 try{
  for(const [id,role,name] of [[admin,'superadmin','Администратор'],[customer,'customer','Клиент журнала'],[cleaner,'cleaner','Исполнитель журнала']])await db.query("INSERT INTO app_users(id,phone,role,status,full_name) VALUES($1,$2,$3,'approved',$4)",[id,'audit-fixture-'+id,role,name]);
  await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,months,base_price,price_per_m2) VALUES($1,$2,4,1,777,0)",[catalog,'Audit '+catalog]);
  await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area) VALUES($1,$2,'Астана','Тест','1',50)",[address,customer]);
  await db.query("INSERT INTO customer_packages(id,customer_id,package_id,address_id,total_cleanings,available_cleanings,status) VALUES($1,$2,$3,$4,4,3,'active')",[purchase,customer,catalog,address]);
  await db.query("INSERT INTO payments(id,customer_id,customer_package_id,provider,amount,status,payload) VALUES($1,$2,$3,'kaspi',777,'paid',$4)",[payment,customer,purchase,{paymentHtml:'DO_NOT_EXPOSE',bccPrivateKey:'DO_NOT_EXPOSE'}]);
  await db.query('UPDATE customer_packages SET purchase_payment_id=$2 WHERE id=$1',[purchase,payment]);
  await db.query("INSERT INTO service_orders(id,customer_id,customer_package_id,address_id,package_id,cleaner_id,scheduled_date,start_time,end_time,status) VALUES($1,$2,$3,$4,$5,$6,'2038-01-02','12:00','14:00','assigned')",[order,customer,purchase,address,catalog,cleaner]);
  await db.query("INSERT INTO audit_logs(id,action,entity_type,entity_id,payload) VALUES($1,'bot.moon-ai.order_create','order',$2,$3)",[event,order,{actorKind:'bot',actorName:'MooonAI',customerId:customer,requestId:randomUUID(),result:'success',snapshot:{order:{status:'pending_assignment'}},context:{date:'2038-01-02',startTime:'12:00'}}]);
  await db.query("INSERT INTO audit_logs(id,action,entity_type,payload) VALUES($1,'bot.moon-ai.catalog.quote','bot_action',$2)",[legacy,{actorKind:'bot',actorName:'MooonAI',result:'success'}]);
  await db.query("INSERT INTO audit_logs(id,actor_id,action,entity_type,payload) VALUES($1,$2,'bot.moon-ai.catalog.quote','bot_action',$3)",[human,admin,{actorKind:'bot',actorName:'MooonAI'}]);
  await t.test('all known catalog variants are readable Russian',()=>{for(const action of ['bot.moon-ai.quote','bot.moon-ai.catalog.quote'])assert.equal(botActionTitle(action),'Расчёт стоимости пакета');assert.equal(botActionTitle('bot.moon-ai.moon-ai.catalog'),'Просмотр каталога услуг');assert.equal(botActionTitle('unknown'),'Действие бота');});
  await t.test('list shows real customer and excludes human-origin spoof',async()=>{const r=await request('/admin/bot-actions?search='+encodeURIComponent('Клиент журнала'));assert.equal(r.status,200);assert.ok(r.data.data.some((e:any)=>e.id===event&&e.customer.name==='Клиент журнала'));assert.ok(!r.data.data.some((e:any)=>e.id===human));});
  await t.test('Russian action search matches legacy operation names',async()=>{const r=await request('/admin/bot-actions?search='+encodeURIComponent('Расчёт'));assert.equal(r.status,200);assert.ok(r.data.data.some((e:any)=>e.id===legacy&&e.title==='Расчёт стоимости пакета'));});
  await t.test('opens the linked payment, package, order and cleaner without gateway secrets',async()=>{const r=await request('/admin/bot-actions/'+event);assert.equal(r.status,200,JSON.stringify(r.data));const d=r.data.data;assert.equal(d.customer.name,'Клиент журнала');assert.equal(d.cleaner.name,'Исполнитель журнала');assert.equal(Number(d.packagePayment.amount),777);assert.equal(d.order.status,'assigned');assert.equal(d.snapshot.order.status,'pending_assignment');assert.equal(JSON.stringify(d).includes('DO_NOT_EXPOSE'),false);});
  await t.test('historical global quotes do not fabricate missing customer or amounts',async()=>{const r=await request('/admin/bot-actions/'+legacy);assert.equal(r.data.data.customer,null);assert.equal(r.data.data.event.amount,null);assert.equal(r.data.data.detailsAvailable,false);assert.ok(r.data.data.note);});
  await t.test('customer sessions cannot read admin financial audit',async()=>{assert.equal((await request('/admin/bot-actions','customer')).status,403);assert.equal((await request('/admin/bot-actions/'+event,'customer')).status,403);});
  await t.test('new snapshots exclude tokens, bank forms and private payloads',()=>{const context=botAuditContext({area:67,date:'2038-01-02',token:'secret',phone:'private',provider:'bcc'});assert.deepEqual(context,{date:'2038-01-02',provider:'bcc',area:67});const snapshot=botAuditSnapshot({payment:{id:payment,amount:777,status:'paid',payload:{paymentHtml:'secret'}}});assert.equal(snapshot.payment.amount,777);assert.equal(JSON.stringify(snapshot).includes('secret'),false);});
 }finally{
  await new Promise<void>(r=>server.close(()=>r()));configureAuthDatabase(null);
  await db.query('DELETE FROM audit_logs WHERE id=ANY($1::uuid[])',[[event,legacy,human]]);await db.query('DELETE FROM service_orders WHERE id=$1',[order]);await db.query('UPDATE customer_packages SET purchase_payment_id=NULL WHERE id=$1',[purchase]);await db.query('DELETE FROM payments WHERE id=$1',[payment]);await db.query('DELETE FROM customer_packages WHERE id=$1',[purchase]);await db.query('DELETE FROM customer_addresses WHERE id=$1',[address]);await db.query('DELETE FROM catalog_packages WHERE id=$1',[catalog]);await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[admin,customer,cleaner]]);await db.close();
 }
});
