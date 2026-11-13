import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {randomUUID} from 'node:crypto';
import {AddressInfo} from 'node:net';
import {Database} from '../infrastructure/db/Database';
import {env} from '../common/env';
import {signAccessToken} from '../common/auth';
import {errorHandler} from '../common/api';
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
