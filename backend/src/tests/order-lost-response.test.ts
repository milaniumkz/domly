import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import express from 'express';
import {Database} from '../infrastructure/db/Database';
import {buildV1Router} from '../http/routes/v1';
import {errorHandler} from '../common/api';
import {signAccessToken} from '../common/auth';
import {BonusService,NotificationService,PaymentService,SchedulingService} from '../modules/domainServices';

test('lost HTTP replies retain one order, one reservation and one cancellation refund', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),user=randomUUID(),catalog=randomUUID(),pkg=randomUUID(),address=randomUUID(),key=randomUUID();
 const bonuses=new BonusService(db),notifications=new NotificationService(db,{} as any);
 let dropCreate=true,dropCancel=true;
 const app=express();app.use(express.json());
 app.use((req,res,next)=>{const json=res.json.bind(res);res.json=((body:any)=>{
  if(req.method==='POST'&&req.path==='/orders'&&res.statusCode===201&&dropCreate){dropCreate=false;res.destroy();return res;}
  if(req.method==='POST'&&req.path.endsWith('/cancel')&&res.statusCode===200&&dropCancel){dropCancel=false;res.destroy();return res;}
  return json(body);
 }) as typeof res.json;next();});
 app.use(buildV1Router({db,bonuses,notifications,payments:new PaymentService(db,bonuses),scheduling:new SchedulingService(db)} as any),errorHandler);
 const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
 const url='http://127.0.0.1:'+(server.address() as any).port;
 const headers={Authorization:'Bearer '+signAccessToken({id:user,role:'customer',phone:'fixture'}),'Content-Type':'application/json'};
 const send=(path:string,body:object)=>fetch(url+path,{method:'POST',headers,body:JSON.stringify(body)});
 try {
  await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[user,'lost-reply-'+user]);
  await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,months,base_price,price_per_m2) VALUES($1,'Fixture',10,1,0,0)",[catalog]);
  await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area,verified_area) VALUES($1,$2,'Астана','Тест','1',100,100)",[address,user]);
  await db.query("INSERT INTO customer_packages(id,customer_id,package_id,address_id,total_cleanings,available_cleanings,status) VALUES($1,$2,$3,$4,10,10,'active')",[pkg,user,catalog,address]);
  const body={customerPackageId:pkg,date:'2035-01-02',startTime:'08:00',idempotencyKey:key};
  await assert.rejects(send('/orders',body),/fetch failed/);
  const saved=(await db.query("SELECT response,status_code FROM api_idempotency WHERE user_id=$1 AND scope='order_create' AND key=$2",[user,key])).rows[0];
  assert.equal(saved.status_code,201);const order=saved.response.data.order.id;
  for(let i=0;i<3;i++){const r=await send('/orders',body);assert.equal(r.status,201);assert.deepEqual(await r.json(),saved.response);}
  assert.equal((await db.query('SELECT count(*)::int AS n FROM service_orders WHERE customer_id=$1',[user])).rows[0].n,1);
  assert.equal((await db.query('SELECT available_cleanings FROM customer_packages WHERE id=$1',[pkg])).rows[0].available_cleanings,9);
  await assert.rejects(send('/orders/'+order+'/cancel',{}),/fetch failed/);
  assert.equal((await db.query('SELECT status FROM service_orders WHERE id=$1',[order])).rows[0].status,'cancelled');
  await send('/orders/'+order+'/cancel',{});
  assert.equal((await db.query('SELECT available_cleanings FROM customer_packages WHERE id=$1',[pkg])).rows[0].available_cleanings,10);
  assert.equal((await db.query("SELECT count(*)::int AS n FROM order_status_history WHERE order_id=$1 AND new_status='cancelled'",[order])).rows[0].n,1);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM payments WHERE order_id=$1',[order])).rows[0].n,0);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM bonus_transactions WHERE order_id=$1',[order])).rows[0].n,0);
 } finally {
  await new Promise<void>(r=>server.close(()=>r()));
  await db.query('DELETE FROM notifications WHERE user_id=$1 OR target_id IN(SELECT id::text FROM service_orders WHERE customer_id=$1)',[user]);
  await db.query('DELETE FROM service_orders WHERE customer_id=$1',[user]);
  await db.query('DELETE FROM api_idempotency WHERE user_id=$1',[user]);
  await db.query('DELETE FROM customer_packages WHERE id=$1',[pkg]);await db.query('DELETE FROM customer_addresses WHERE id=$1',[address]);
  await db.query('DELETE FROM catalog_packages WHERE id=$1',[catalog]);await db.query('DELETE FROM app_users WHERE id=$1',[user]);await db.close();
 }
});
