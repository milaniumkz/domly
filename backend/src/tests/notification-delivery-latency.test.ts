import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Database} from '../infrastructure/db/Database';
import {NotificationService} from '../modules/domainServices';

test('committed operation returns without waiting for notification delivery', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL}, async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),id=randomUUID();
 let release!:()=>void;const gate=new Promise<void>(resolve=>{release=resolve});let delivered=0,finished=false;
 const service=new NotificationService(db,{} as any);service.deliver=async()=>{delivered++;await gate};
 let operation:Promise<any>|undefined;
 try {
  await db.query("INSERT INTO app_users(id,phone,role) VALUES($1,$2,'customer')",[id,'notification-latency-'+id]);
  operation=db.atomic(()=>service.create({userId:id,titleRu:'Заказ сохранён',bodyRu:'Тест',dedupeKey:id})).then(row=>{finished=true;return row});
  await Promise.race([operation,new Promise(resolve=>setTimeout(resolve,1000))]);
  assert.equal(finished,true,'HTTP operation must not wait for a slow notification transport');
  assert.equal(delivered,0,'delivery belongs to the durable worker, not the HTTP handler');
  const row=await operation;
  assert.equal((await db.query('SELECT notification_id FROM notification_deliveries WHERE notification_id=$1',[row.id])).rows.length,1);
 } finally {release();await operation;await db.query('DELETE FROM notifications WHERE user_id=$1',[id]);await db.query('DELETE FROM app_users WHERE id=$1',[id]);await db.close();}
});

test('notification outbox rolls back, retries failures and recovers expired worker leases', {skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL}, async()=>{
 const {processNotificationDeliveries}=await import('../modules/notificationDelivery');
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),id=randomUUID();
 const service=new NotificationService(db,{} as any);
 try {
  await db.query("INSERT INTO app_users(id,phone,role) VALUES($1,$2,'customer')",[id,'notification-retry-'+id]);
  await assert.rejects(db.atomic(async()=>{await service.create({userId:id,titleRu:'Откат',bodyRu:'Тест'});throw Error('rollback')}),/rollback/);
  assert.equal((await db.query('SELECT id FROM notifications WHERE user_id=$1',[id])).rows.length,0);
  const row=await service.create({userId:id,titleRu:'Заказ',bodyRu:'Тест',dedupeKey:id});
  await service.create({userId:id,titleRu:'Заказ',bodyRu:'Тест',dedupeKey:id});
  assert.equal((await db.query('SELECT * FROM notification_deliveries WHERE notification_id=$1',[row!.id])).rows.length,1);
  // Make our independent fixture first; unrelated concurrently running tests are not asserted here.
  await db.query("UPDATE notification_deliveries SET available_at=NOW()-INTERVAL '10 years' WHERE notification_id=$1",[row!.id]);
  let calls=0;
  const fail=async(n:any)=>{if(n.id===row!.id){calls++;throw Error('offline')}};
  await Promise.all([processNotificationDeliveries(db,fail,1),processNotificationDeliveries(db,fail,1)]);
  assert.equal(calls,1,'competing workers must not deliver one active lease twice');
  let state=(await db.query('SELECT * FROM notification_deliveries WHERE notification_id=$1',[row!.id])).rows[0];
  assert.equal(state.delivered_at,null);assert.equal(state.attempts,1);assert.equal(state.last_error,'Error');
  await db.query("UPDATE notification_deliveries SET available_at=NOW()-INTERVAL '10 years',lease_until=NOW()-INTERVAL '1 second',lease_token=$2 WHERE notification_id=$1",[row!.id,randomUUID()]);
  await processNotificationDeliveries(db,async(n,input)=>{if(n.id===row!.id){calls++;assert.equal(input.userId,id);assert.equal(input.titleRu,'Заказ')}},1);
  state=(await db.query('SELECT * FROM notification_deliveries WHERE notification_id=$1',[row!.id])).rows[0];
  assert.ok(state.delivered_at);assert.equal(state.attempts,2);assert.equal(state.last_error,null);assert.equal(calls,2);
 }finally{await db.query('DELETE FROM notifications WHERE user_id=$1',[id]);await db.query('DELETE FROM app_users WHERE id=$1',[id]);await db.close();}
});

test('queued cleaner offer does not ring after cancellation or expiry',async()=>{
 let alarms=0,pushes=0;
 const db={query:async()=>({rows:[]})} as any;
 const service=new NotificationService(db,{send:async()=>{pushes++}} as any,{cleanerAlarms:{add:async()=>{alarms++}}});
 await service.deliver({id:randomUUID(),user_id:randomUUID(),role:null},{userId:randomUUID(),targetType:'order_offer',targetId:randomUUID(),titleRu:'Заказ',bodyRu:'Тест'},{throwOnError:true});
 assert.equal(alarms,0);assert.equal(pushes,0);
});

test('durable delivery retries push errors returned by the provider',async()=>{
 const {sendLocalizedPush}=await import('../localization');
 const db={query:async()=>({rows:[{token:'fake-token',language:'ru'}]})} as any;
 for(const result of [{sent:0,failed:1},{sent:0,failed:0,skipped:true}]) {
  await assert.rejects(sendLocalizedPush(db,{send:async()=>result},{userId:'test',titleRu:'Тест',bodyRu:'Тест'},{},{requireDelivery:true}),/PushDeliveryFailed/);
 }
 await sendLocalizedPush(db,{send:async()=>({sent:1,failed:0})},{userId:'test',titleRu:'Тест',bodyRu:'Тест'},{},{requireDelivery:true});
});

test('invalid device tokens are disabled rather than retried forever',async()=>{
 const {sendLocalizedPush}=await import('../localization');let disabled:string[]=[];
 const db={query:async(sql:string,args:any[])=>{if(sql.startsWith('UPDATE device_tokens')){disabled=args[0];return {rows:[]}}return {rows:[{token:'expired-token',language:'ru'}]}} as any;
 await sendLocalizedPush(db,{send:async()=>({sent:0,failed:1,retryableFailed:0,invalidTokens:['expired-token']})},{userId:'test',titleRu:'Тест',bodyRu:'Тест'},{},{requireDelivery:true});
 assert.deepEqual(disabled,['expired-token']);
});
