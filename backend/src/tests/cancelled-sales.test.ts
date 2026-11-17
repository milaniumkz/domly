import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import express from 'express';
import {AddressInfo} from 'node:net';
import {Database} from '../infrastructure/db/Database';
import {configureAuthDatabase,signAccessToken} from '../common/auth';
import {errorHandler} from '../common/api';
import {buildV1Router} from '../http/routes/v1';
import {BonusService} from '../modules/domainServices';
import {env} from '../common/env';

test('Kaspi cancellation: atomic business effects, paid base protection and complete admin records',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);configureAuthDatabase(db);
 const user=randomUUID(),admin=randomUUID(),cleaner=randomUUID(),zone=randomUUID(),house=randomUUID(),address=randomUUID(),catalog=randomUUID(),addon=randomUUID();
 const previous={enabled:env.moonAiEnabled,hook:env.moonAiWebhookToken};env.moonAiEnabled=false;env.moonAiWebhookToken='fixture-cancel-hook';
 const notices:any[]=[];const bonus=new BonusService(db);
 const app=express();app.use(express.json(),buildV1Router({db,bonuses:bonus,notifications:{create:async(v:any)=>{notices.push(v);},createAdminEvent:async(v:any)=>{notices.push(v);return [];}}} as any),errorHandler);
 const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
 const token=(role:'customer'|'superadmin')=>signAccessToken({id:role==='customer'?user:admin,role,phone:'fixture'});
 const payer='+77009998877';
 async function pkg(status='pending_payment',bot=false){const id=randomUUID();await db.query(`INSERT INTO customer_packages(id,customer_id,package_id,address_id,total_cleanings,available_cleanings,status,purchase_config)
  VALUES($1,$2,$3,$4,4,4,$5,$6)`,[id,user,catalog,address,status,{...(bot?{createdBy:'bot'}:{}),addressSnapshot:{city:'Астана',street:'Историческая',house:'43',apartment:'103',area:67},packageSnapshot:{name_ru:'Квартальный тест'},addons:[{title:'Окно',quantity:2,total:100}]}]);return id;}
 async function payment(cp:string|null,order:string|null,amount=1000,status='invoice_requested',payload:any={},bonusAmount=0){const id=randomUUID();await db.query(`INSERT INTO payments(id,customer_id,customer_package_id,order_id,provider,status,amount,bonus_amount,invoice_phone,invoice_requested_at,payload,paid_at,applied_at)
  VALUES($1,$2,$3,$4,'kaspi',$5::payment_status,$6,$7,$8,NOW()-INTERVAL '1 minute',$9,CASE WHEN $5::payment_status='paid' THEN NOW() END,CASE WHEN $5::payment_status='paid' THEN NOW() END)`,[id,user,cp,order,status,amount,bonusAmount,payer,payload]);return id;}
 async function order(cp:string|null,status='assigned'){const id=randomUUID();await db.query(`INSERT INTO service_orders(id,customer_id,customer_package_id,package_id,address_id,cleaner_id,scheduled_date,start_time,end_time,estimated_duration_minutes,status,addon_amount,total_amount,payable_amount)
  VALUES($1,$2,$3,$4,$5,$6,CURRENT_DATE+1,'10:00','12:00',120,$7,50,50,50)`,[id,user,cp,catalog,address,cleaner,status]);return id;}
 async function callback(id:string,status='cancel',hook='fixture-cancel-hook',time=new Date().toISOString()){
  const p=(await db.query('SELECT amount FROM payments WHERE id=$1',[id])).rows[0];
  const r=await fetch(base+'/payments/moon-ai/kaspi-status',{method:'POST',headers:{'Content-Type':'application/json','X-MoonAI-Token':hook},body:JSON.stringify({paymentId:id,phone:payer,amount:Number(p.amount),status,dateTime:time})});return{status:r.status,body:await r.json() as any};
 }
 async function list(query='',role:'customer'|'superadmin'='superadmin'){
  const r=await fetch(base+'/admin/cancelled-sales'+query,{headers:{Authorization:'Bearer '+token(role)}});return{status:r.status,body:await r.json() as any};}
 let botPayment='';
 try{
  for(const [id,role] of [[user,'customer'],[admin,'superadmin'],[cleaner,'cleaner']])await db.query("INSERT INTO app_users(id,phone,role,status,full_name,bonus_balance) VALUES($1,$2,$3,'approved',$4,500)",[id,'fixture-'+id,role,role==='customer'?'Отмена тестовый клиент':'Fixture']);
  await db.query("INSERT INTO service_zones(id,name_ru,city) VALUES($1,'Fixture',$2)",[zone,'fixture-'+user]);
  await db.query("INSERT INTO connected_houses(id,city,street_ru,house,zone_id) VALUES($1,$2,'Fixture','1',$3)",[house,'fixture-'+user,zone]);
  await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,apartment,area,verified_area) VALUES($1,$2,$3,'Fixture','1','103',67,67)",[address,user,'fixture-'+user]);
  await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,months,base_price) VALUES($1,'Изменённое название',4,3,1000)",[catalog]);
  await db.query("INSERT INTO catalog_addons(id,title_ru,price,duration_minutes) VALUES($1,'Окно',50,20)",[addon]);
  await t.test('forged callback cannot cancel payment or purchase',async()=>{
   const cp=await pkg(),p=await payment(cp,null);assert.equal((await callback(p,'cancel','wrong')).status,401);assert.equal((await db.query('SELECT status FROM customer_packages WHERE id=$1',[cp])).rows[0].status,'pending_payment');
  });
  await t.test('bot-created unpaid package and its bookings cancel; reserved bonuses refund once',async()=>{
   const cp=await pkg('pending_payment',true),o=await order(cp),p=await payment(cp,null,70,'invoice_requested',{createdBy:'bot'},30);botPayment=p;
   await bonus.spend(user,30,'fixture',undefined,p);const before=Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[user])).rows[0].bonus_balance);
   await db.query("INSERT INTO order_offers(order_id,cleaner_id,status,expires_at) VALUES($1,$2,'offered',NOW()+INTERVAL '1 hour')",[o,cleaner]);
   const time=new Date().toISOString();const replies=await Promise.all([callback(p,'cancel','fixture-cancel-hook',time),callback(p,'cancelled','fixture-cancel-hook',time)]);assert.ok(replies.every(r=>r.status===200),JSON.stringify(replies));
   assert.equal((await db.query('SELECT status FROM customer_packages WHERE id=$1',[cp])).rows[0].status,'cancelled');assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[o])).rows[0].status,'cancelled');assert.equal((await db.query('SELECT status FROM order_offers WHERE order_id=$1',[o])).rows[0].status,'expired');
   assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[user])).rows[0].bonus_balance),before+30);assert.equal((await db.query("SELECT COUNT(*)::int n FROM bonus_transactions WHERE payment_id=$1 AND type='refund'",[p])).rows[0].n,1);
   const effects=(await db.query("SELECT payload->'kaspiCancellation' e FROM payments WHERE id=$1",[p])).rows[0].e;assert.equal(effects.scope,'package');assert.deepEqual(effects.cancelledOrderIds,[o]);
  });
  await t.test('unpaid standalone cleaning cancels, while already started cleaning is protected',async()=>{
   const o=await order(null),p=await payment(null,o);assert.equal((await callback(p)).status,200);assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[o])).rows[0].status,'cancelled');
   const active=await order(null,'in_progress'),bill=await payment(null,active);assert.equal((await callback(bill)).status,200);assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[active])).rows[0].status,'in_progress');assert.equal((await db.query("SELECT payload#>>'{kaspiCancellation,requiresReview}' x FROM payments WHERE id=$1",[bill])).rows[0].x,'true');
  });
  await t.test('cancelled add-on invoice preserves paid cleaning, paid extras and package quota',async()=>{
   const cp=await pkg('active');await payment(cp,null,1000,'paid');const o=await order(cp,'in_progress'),p=await payment(null,o,50,'invoice_requested',{kind:'addon_request_payment'});
   await db.query('UPDATE service_orders SET base_amount=2000,total_amount=2050 WHERE id=$1',[o]);
   const ids=[randomUUID(),randomUUID(),randomUUID(),randomUUID()];
   for(let i=0;i<4;i++)await db.query(`INSERT INTO order_addons(id,order_id,addon_id,price,quantity,duration_minutes,payment_status,paid_separately,requires_customer_approval)
    VALUES($1,$2,$3,$4,1,$5,$6,$7,$8)`,[ids[i],o,addon,i===0?50:10,i===0?20:0,i===1?'paid':i===2?'draft':'pending',i===2,i===3]);
   assert.equal((await callback(p)).status,200);const row=(await db.query('SELECT * FROM service_orders WHERE id=$1',[o])).rows[0];assert.equal(row.status,'in_progress');assert.equal(row.estimated_duration_minutes,100);assert.equal(Number(row.payable_amount),0);assert.equal(Number(row.total_amount),2010);
   const states=(await db.query('SELECT id,payment_status FROM order_addons WHERE order_id=$1',[o])).rows;for(let i=0;i<4;i++)assert.equal(states.find(r=>r.id===ids[i]).payment_status,['cancelled','paid','draft','pending'][i]);
   assert.equal((await db.query('SELECT status,available_cleanings FROM customer_packages WHERE id=$1',[cp])).rows[0].status,'active');
  });
  await t.test('a late old-invoice cancellation preserves a newer payment attempt',async()=>{
   const cp=await pkg(),p=await payment(cp,null);await payment(cp,null,1100);assert.equal((await callback(p)).status,200);assert.equal((await db.query('SELECT status FROM customer_packages WHERE id=$1',[cp])).rows[0].status,'pending_payment');assert.equal((await db.query("SELECT payload#>>'{kaspiCancellation,retainedReason}' x FROM payments WHERE id=$1",[p])).rows[0].x,'other_payment_exists');
  });
  await t.test('payment cancellation and purchase cancellation roll back together on failure',async()=>{
   const cp=await pkg(),p=await payment(cp,null),query=db.query.bind(db);let fail=true;
   (db as any).query=async(sql:string,values:any[])=>{if(fail&&sql.includes("UPDATE customer_packages SET status='cancelled'")){fail=false;throw Error('fixture failure');}return query(sql,values);};
   try{assert.equal((await callback(p)).status,500);}finally{db.query=query;}
   assert.equal((await db.query('SELECT status FROM payments WHERE id=$1',[p])).rows[0].status,'invoice_requested');assert.equal((await db.query('SELECT status FROM customer_packages WHERE id=$1',[cp])).rows[0].status,'pending_payment');assert.equal((await callback(p)).status,200);
  });
  await t.test('paid payment is not cancelled by a delayed cancel event',async()=>{
   const p=await payment(null,null,1000,'paid');assert.equal((await callback(p)).status,200);assert.equal((await db.query('SELECT status FROM payments WHERE id=$1',[p])).rows[0].status,'paid');
  });
  await t.test('admin-only list contains bot origin, original tariff/address, all amounts and related orders',async()=>{
   assert.equal((await list('', 'customer')).status,403);assert.equal((await fetch(base+'/admin/cancelled-sales')).status,401);
   const response=await list('?search='+encodeURIComponent('Отмена тестовый'));assert.equal(response.status,200);const rows=response.body.data.items;assert.ok(response.body.data.total>=5);const bot=rows.find((r:any)=>r.id===botPayment);assert.ok(bot);assert.equal(bot.created_by,'bot');assert.equal(bot.package_name,'Квартальный тест');assert.equal(bot.address.apartment,'103');assert.equal(Number(bot.address.area),67);assert.equal(Number(bot.amount),70);assert.equal(Number(bot.bonus_amount),30);assert.ok(bot.customer_phone);assert.equal(bot.invoice_phone,payer);assert.equal(bot.package_orders.length,1);assert.equal(bot.payments.length,1);
   assert.equal((await list('?limit=bad')).status,400);assert.equal((await list('?dateFrom=bad')).status,400);assert.equal((await list('?kind=payment&limit=1&offset=1')).body.data.items.length,1);
  });
  assert.equal((await db.query("SELECT COUNT(*)::int n FROM moon_ai_outbox WHERE customer_id=$1 AND kind IN ('message','abandoned_checkout')",[user])).rows[0].n,0,'cancellation never queues a new WhatsApp message');
 }finally{
  await new Promise<void>(r=>server.close(()=>r()));
  await db.query('DELETE FROM audit_logs WHERE entity_id IN(SELECT id::text FROM payments WHERE customer_id=$1)',[user]);
  await db.query('DELETE FROM moon_ai_payment_callbacks WHERE phone=$1',[payer.slice(1)]);await db.query('DELETE FROM payment_events WHERE payment_id IN(SELECT id FROM payments WHERE customer_id=$1)',[user]);await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[user]);await db.query('DELETE FROM order_offers WHERE order_id IN(SELECT id FROM service_orders WHERE customer_id=$1)',[user]);await db.query('DELETE FROM order_status_history WHERE order_id IN(SELECT id FROM service_orders WHERE customer_id=$1)',[user]);await db.query('DELETE FROM order_addons WHERE order_id IN(SELECT id FROM service_orders WHERE customer_id=$1)',[user]);await db.query('DELETE FROM payments WHERE customer_id=$1',[user]);await db.query('DELETE FROM service_orders WHERE customer_id=$1',[user]);await db.query('DELETE FROM customer_packages WHERE customer_id=$1',[user]);await db.query('DELETE FROM customer_addresses WHERE id=$1',[address]);await db.query('DELETE FROM connected_houses WHERE id=$1',[house]);await db.query('DELETE FROM service_zones WHERE id=$1',[zone]);await db.query('DELETE FROM catalog_addons WHERE id=$1',[addon]);await db.query('DELETE FROM catalog_packages WHERE id=$1',[catalog]);await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[user,admin,cleaner]]);Object.assign(env,{moonAiEnabled:previous.enabled,moonAiWebhookToken:previous.hook});await db.close();
 }
});
