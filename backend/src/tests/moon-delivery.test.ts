import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Database} from '../infrastructure/db/Database';
import {env} from '../common/env';
import {ensureAssistantChat,queueMoonInvoice,processMoonOutbox,notifyMoonInvoiceFailures,moonTransportFailure} from '../modules/moonAi';

test('Moon transport errors are bounded codes and never exception text',()=>{
 assert.equal(moonTransportFailure({cause:{code:'ECONNREFUSED'},message:'secret'}),'ECONNREFUSED');
 assert.equal(moonTransportFailure({name:'TimeoutError',message:'secret'}),'request_timeout');
 assert.equal(moonTransportFailure({code:'secret',message:'secret'}),'delivery_unknown');
});

test('Moon invoice recovery with real PostgreSQL',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
 const saved={enabled:env.moonAiEnabled,url:env.moonAiChannelUrl,key:env.moonAiChannelApiKey,hook:env.moonAiWebhookToken};
 Object.assign(env,{moonAiEnabled:true,moonAiChannelUrl:'https://fixture.mooonai.com/messages',moonAiChannelApiKey:'fixture',moonAiWebhookToken:'fixture'});
 const user=randomUUID(),address=randomUUID(),zone=randomUUID(),house=randomUUID(),orders:string[]=[],payments:string[]=[];
 const row=async(id:string)=>(await db.query('SELECT * FROM moon_ai_outbox WHERE id=$1',[id])).rows[0];
 async function fixture(){
  const order=randomUUID(),payment=randomUUID();orders.push(order);payments.push(payment);
  await db.query("INSERT INTO service_orders(id,customer_id,address_id,scheduled_date,start_time,end_time,status) VALUES($1,$2,$3,CURRENT_DATE+1,'10:00','12:00','assigned')",[order,user,address]);
  await db.query("INSERT INTO payments(id,customer_id,order_id,provider,status,amount,invoice_phone) VALUES($1,$2,$3,'kaspi','pending',1000,'+77000000000')",[payment,user,order]);
  await queueMoonInvoice(db,(await db.query('SELECT * FROM payments WHERE id=$1',[payment])).rows[0],'Fixture');
  return (await db.query("SELECT id FROM moon_ai_outbox WHERE payment_id=$1 AND kind='invoice'",[payment])).rows[0].id;
 }
 let calls=0;
 const accept=(async(_url:any,init:any)=>{calls++;const body=JSON.parse(init.body);assert.equal(body.from_type,'user');return new Response(JSON.stringify({accepted:true,external_thread_id:body.thread_id,thread_id:'fixture-thread'}));}) as typeof fetch;
 try{
  await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[user,'fixture-'+user]);
  await db.query("INSERT INTO service_zones(id,name_ru,city) VALUES($1,'Fixture',$2)",[zone,'fixture-'+user]);
  await db.query("INSERT INTO connected_houses(id,city,street_ru,house,zone_id) VALUES($1,$2,'Fixture','1',$3)",[house,'fixture-'+user,zone]);
  await db.query("INSERT INTO customer_addresses(id,user_id,city,street,house,area,verified_area) VALUES($1,$2,$3,'Fixture','1',50,50)",[address,user,'fixture-'+user]);
  await ensureAssistantChat(db,user);
  await t.test('refused connection retries same request once then records acceptance',async()=>{
   const id=await fixture();let thread='';
   const refused=(async(_url:any,init:any)=>{thread=JSON.parse(init.body).thread_id;throw Object.assign(new TypeError('fixture'),{cause:{code:'ECONNREFUSED'}});}) as typeof fetch;
   await processMoonOutbox(db,refused,id);let r=await row(id);assert.equal(r.state,'pending');assert.equal(r.failure_code,'ECONNREFUSED');assert.ok(r.run_after>r.finished_at);
   await db.query('UPDATE moon_ai_outbox SET run_after=NOW() WHERE id=$1',[id]);
   await processMoonOutbox(db,accept,id);r=await row(id);assert.equal(r.state,'sent');assert.equal(r.failure_code,null);assert.equal(r.payload.apiDelivery.attempt,2);assert.equal(thread,id);
   const before=calls;await processMoonOutbox(db,accept,id);assert.equal(calls,before);
  });
  await t.test('ambiguous timeout is not replayed and alerts admin once',async()=>{
   const id=await fixture();let attempts=0;
   await processMoonOutbox(db,(async()=>{attempts++;throw Object.assign(new Error('fixture'),{name:'TimeoutError'});}) as typeof fetch,id);
   assert.equal((await row(id)).state,'uncertain');assert.equal((await row(id)).failure_code,'request_timeout');
   await processMoonOutbox(db,accept,id);assert.equal(attempts,1);
   let alerts=0;const notify={createAdminEvent:async(input:any)=>{assert.equal(input.targetType,'payment');alerts++;return [{}];}};
   await notifyMoonInvoiceFailures(db,notify as any);const before=alerts;await notifyMoonInvoiceFailures(db,notify as any);assert.equal(alerts,before);assert.ok(before>=1);
  });
  await t.test('bounded pre-connect retries stop after three attempts',async()=>{
   const id=await fixture();const fail=(async()=>{throw Object.assign(new Error('fixture'),{cause:{code:'EAI_AGAIN'}});}) as typeof fetch;
   for(let i=0;i<3;i++){await db.query('UPDATE moon_ai_outbox SET run_after=NOW() WHERE id=$1',[id]);await processMoonOutbox(db,fail,id);}
   const r=await row(id);assert.equal(r.state,'uncertain');assert.equal(r.payload.apiDelivery.attempt,3);
  });
  await t.test('worker crash before dispatch recovers; crash after dispatch never replays',async()=>{
   const safe=await fixture();await db.query(`UPDATE moon_ai_outbox SET state='processing',started_at=NOW()-INTERVAL '3 minutes',payload=payload || '{"apiDelivery":{"phase":"claimed","attempt":1}}'::jsonb WHERE id=$1`,[safe]);
   await processMoonOutbox(db,accept,safe);assert.equal((await row(safe)).state,'sent');
   for(const phase of ['http_started','legacy']){
    const id=await fixture();await db.query(`UPDATE moon_ai_outbox SET state='processing',started_at=NOW()-INTERVAL '3 minutes',payload=payload || $2::jsonb WHERE id=$1`,[id,phase==='legacy'?{}:{apiDelivery:{phase,attempt:1}}]);
    const before=calls;await processMoonOutbox(db,accept,id);const r=await row(id);assert.equal(calls,before);assert.equal(r.state,'uncertain');assert.equal(r.failure_code,'worker_interrupted');assert.ok(r.finished_at);
   }
  });
  await t.test('successful HTTP with invalid acceptance remains uncertain',async()=>{
   const id=await fixture();await processMoonOutbox(db,(async()=>new Response(JSON.stringify({accepted:false}))) as typeof fetch,id);
   assert.equal((await row(id)).state,'uncertain');assert.equal((await row(id)).failure_code,'invalid_acceptance');
  });
  await t.test('database failure after provider acceptance never replays the invoice',async()=>{
   const id=await fixture(),before=calls,query=db.query.bind(db);let fail=true;
   (db as any).query=async(sql:string,values:any[])=>{
    if(fail&&sql.includes("state='sent',provider_thread_id")){fail=false;throw Object.assign(new Error('fixture DB outage'),{code:'ECONNREFUSED'});}
    return query(sql,values);
   };
   try{await processMoonOutbox(db,accept,id);}finally{db.query=query;}
   assert.equal((await row(id)).state,'uncertain');await processMoonOutbox(db,accept,id);assert.equal(calls-before,1);
  });
  await t.test('alerts skip closed payments and finish deduplicated notification recovery',async()=>{
   const id=await fixture(),r=await row(id),targets:string[]=[];
   await db.query("UPDATE moon_ai_outbox SET state='uncertain' WHERE id=$1",[id]);
   await db.query("UPDATE payments SET status='cancelled' WHERE id=$1",[r.payment_id]);
   const notify={createAdminEvent:async(input:any)=>{targets.push(input.targetId);return [];}};
   await notifyMoonInvoiceFailures(db,notify as any);assert.equal(targets.includes(r.payment_id),false);
   const before=targets.length;await notifyMoonInvoiceFailures(db,notify as any);assert.equal(targets.length,before);
  });
  await t.test('a suspended old worker cannot send after its pre-dispatch lease is recovered',async()=>{
   const id=await fixture(),before=calls,query=db.query.bind(db);let park=true,release!:()=>void,parked!:()=>void;
   const wait=new Promise<void>(resolve=>{release=resolve;}),ready=new Promise<void>(resolve=>{parked=resolve;});
   (db as any).query=async(sql:string,values:any[])=>{
    if(park&&sql.includes("'{apiDelivery,phase}'")){park=false;parked();await wait;}
    return query(sql,values);
   };
   const old=processMoonOutbox(db,accept,id);
   try{
    await ready;await query("UPDATE moon_ai_outbox SET started_at=NOW()-INTERVAL '3 minutes' WHERE id=$1",[id]);
    await processMoonOutbox(db,accept,id);release();await old;assert.equal(calls-before,1);assert.equal((await row(id)).state,'sent');
   }finally{release();await old;db.query=query;}
  });
  await t.test('concurrent processors send an invoice only once',async()=>{
   const id=await fixture(),before=calls;await Promise.all(Array.from({length:4},()=>processMoonOutbox(db,accept,id)));assert.equal(calls-before,1);assert.equal((await row(id)).state,'sent');
  });
 }finally{
  await db.query('DELETE FROM moon_ai_outbox WHERE customer_id=$1',[user]);
  await db.query('DELETE FROM payments WHERE customer_id=$1',[user]);await db.query('DELETE FROM service_orders WHERE customer_id=$1',[user]);
  await db.query('DELETE FROM chat_participants WHERE user_id=$1',[user]);await db.query('DELETE FROM chats WHERE customer_id=$1',[user]);await db.query('DELETE FROM customer_addresses WHERE id=$1',[address]);await db.query('DELETE FROM connected_houses WHERE id=$1',[house]);await db.query('DELETE FROM service_zones WHERE id=$1',[zone]);await db.query('DELETE FROM app_users WHERE id=$1',[user]);
  Object.assign(env,{moonAiEnabled:saved.enabled,moonAiChannelUrl:saved.url,moonAiChannelApiKey:saved.key,moonAiWebhookToken:saved.hook});await db.close();
 }
});
