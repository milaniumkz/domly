import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import express from 'express';
import {AddressInfo} from 'node:net';
import {Database} from '../infrastructure/db/Database';
import {configureAuthDatabase,signAccessToken} from '../common/auth';
import {errorHandler} from '../common/api';
import {buildV1Router} from '../http/routes/v1';

test('customer CRM: private admin notes, revisions, filters and pagination against PostgreSQL',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);configureAuthDatabase(db);
 const users=[randomUUID(),randomUUID(),randomUUID()],admin=randomUUID(),cleaner=randomUUID();
 const prefix='CRM-'+randomUUID(),sentinel='PRIVATE-NOTE-'+randomUUID();
 const app=express();app.use(express.json(),buildV1Router({db} as any),errorHandler);
 const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
 const auth=(role:'superadmin'|'customer'|'cleaner')=>signAccessToken({id:role==='superadmin'?admin:role==='cleaner'?cleaner:users[0],role,phone:'fixture'});
 async function request(path:string,method='GET',body?:any,role:'superadmin'|'customer'|'cleaner'|null='superadmin'){
  const r=await fetch(base+path,{method,headers:{...(role?{Authorization:'Bearer '+auth(role)}:{}),'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});return{status:r.status,body:await r.json() as any,cache:r.headers.get('cache-control')};
 }
 const list=(query='')=>request('/admin/customer-crm?search='+encodeURIComponent(prefix)+query);
 try{
  for(const [id,role] of [[admin,'superadmin'],[cleaner,'cleaner']])await db.query("INSERT INTO app_users(id,phone,role,status,full_name) VALUES($1,$2,$3,'approved','Fixture admin')",[id,'fixture-'+id,role]);
  for(let i=0;i<users.length;i++)await db.query("INSERT INTO app_users(id,phone,role,status,full_name,created_at) VALUES($1,$2,'customer','approved',$3,$4)",[users[i],'crm-'+users[i],prefix+' '+i,new Date(Date.UTC(2026,10,10+i)).toISOString()]);
  await db.query("INSERT INTO customer_addresses(user_id,city,street,house,area,verified_area) VALUES($1,'Астана','Тестовая','43',67,67)",[users[0]]);
  await db.query("INSERT INTO customer_addresses(user_id,city,street,house,area) VALUES($1,'Алматы','Другая','7',80)",[users[1]]);
  await db.query("INSERT INTO payments(customer_id,provider,status,amount,paid_at,applied_at) VALUES($1,'kaspi','paid',1000,NOW(),NOW()),($2,'kaspi','invoice_requested',500,NULL,NULL)",[users[0],users[1]]);
  await t.test('customer/cleaner/anonymous cannot read or write administrative CRM',async()=>{
   for(const role of ['customer','cleaner',null] as const){
    assert.equal((await request('/admin/customer-crm','GET',undefined,role)).status,role?403:401);
    assert.equal((await request('/admin/customer-crm/'+users[0]+'/notes','GET',undefined,role)).status,role?403:401);
    assert.equal((await request('/admin/customer-crm/'+users[0]+'/notes','POST',{body:'forged'},role)).status,role?403:401);
    assert.equal((await request('/admin/customer-crm/'+users[0],'PATCH',{stage:'refused',revision:0},role)).status,role?403:401);
   }
  });
  await t.test('default newest/oldest ordering, dates and explicit filters cover all customers',async()=>{
   let r=await list();assert.equal(r.status,200,JSON.stringify(r.body));assert.equal(r.cache,'no-store');assert.equal(r.body.data.total,3);assert.deepEqual(r.body.data.items.map((v:any)=>v.id),[users[2],users[1],users[0]]);
   assert.deepEqual((await list('&sort=oldest')).body.data.items.map((v:any)=>v.id),users);
   assert.equal((await list('&purchase=paid')).body.data.items[0].id,users[0]);assert.equal((await list('&purchase=pending')).body.data.items[0].id,users[1]);assert.equal((await list('&purchase=none')).body.data.items[0].id,users[2]);
   assert.equal((await list('&area=verified')).body.data.items[0].id,users[0]);assert.equal((await list('&area=unverified')).body.data.items[0].id,users[1]);assert.equal((await list('&area=missing')).body.data.items[0].id,users[2]);
   assert.equal((await list('&city='+encodeURIComponent('Астана')+'&house=43')).body.data.total,1);
   assert.equal((await list('&dateFrom=2026-11-11T00%3A00%3A00Z&dateTo=2026-11-11T23%3A59%3A59Z')).body.data.items[0].id,users[1]);
   assert.equal((await list('&paidMin=900&paidMax=1100')).body.data.items[0].id,users[0]);
   assert.equal((await list('&limit=1&offset=1')).body.data.items[0].id,users[1]);
   for(const q of ['&limit=-1','&stage=arbitrary','&dateFrom=invalid','&paidMin=-1','&sort=DROP'])assert.equal((await list(q)).status,400);
   assert.equal((await request('/admin/customer-crm?search='+encodeURIComponent("' OR true --"))).body.data.total,0);
  });
  let noteId='';
  await t.test('notes are admin-only, retain author/time, and never enter customer profiles or audit bodies',async()=>{
   const r=await request('/admin/customer-crm/'+users[0]+'/notes','POST',{body:sentinel});assert.equal(r.status,201);noteId=r.body.data.id;assert.equal(r.body.data.revision,1);
   const notes=await request('/admin/customer-crm/'+users[0]+'/notes');assert.equal(notes.status,200);assert.equal(notes.body.data.items[0].body,sentinel);assert.equal(notes.body.data.items[0].author_name,'Fixture admin');assert.ok(notes.body.data.items[0].created_at);
   const profiles=(await db.query('SELECT to_jsonb(u) profile FROM app_users u WHERE id=ANY($1::uuid[])',[users])).rows;assert.equal(JSON.stringify(profiles).includes(sentinel),false);
   const audit=(await db.query('SELECT payload FROM audit_logs WHERE entity_id=$1',[users[0]])).rows;assert.equal(JSON.stringify(audit).includes(sentinel),false);
   const own=await request('/me','GET',undefined,'customer');assert.equal(own.status,200);assert.equal(JSON.stringify(own.body).includes(sentinel),false);
   assert.equal((await list('&notes=with')).body.data.total,1);assert.equal((await list('&notes=without')).body.data.total,2);
   assert.equal((await list('&notes=with')).body.data.items[0].latest_note,sentinel);
   assert.equal((await request('/admin/customer-crm?search='+encodeURIComponent(sentinel))).body.data.items[0].id,users[0]);
   assert.equal((await request('/admin/customer-crm/'+admin+'/notes','POST',{body:'wrong-role'})).status,404);
   assert.equal((await request('/admin/customer-crm/'+users[0]+'/notes','POST',{body:' '})).status,400);
  });
  await t.test('note edits detect concurrent stale revisions and cannot move a note to another customer',async()=>{
   const path='/admin/customer-crm/'+users[0]+'/notes/'+noteId;
   assert.equal((await request(path,'PATCH',{body:sentinel+' edited',revision:1})).status,200);
   assert.equal((await request(path,'PATCH',{body:'lost update',revision:1})).status,409);
   assert.equal((await request('/admin/customer-crm/'+users[1]+'/notes/'+noteId,'PATCH',{body:'other-customer',revision:2})).status,409);
   const note=(await request('/admin/customer-crm/'+users[0]+'/notes')).body.data.items[0];assert.equal(note.body,sentinel+' edited');assert.equal(note.revision,2);
  });
  await t.test('stages are independent from account status and use optimistic revision protection',async()=>{
   assert.equal((await list('&stage=purchased')).body.data.items[0].id,users[0]);
   assert.equal((await request('/admin/customer-crm/'+users[1],'PATCH',{stage:'working',revision:0})).status,200);
   const replies=await Promise.all(['refused','processed'].map(stage=>request('/admin/customer-crm/'+users[1],'PATCH',{stage,revision:1})));assert.deepEqual(replies.map(r=>r.status).sort(),[200,409]);
   assert.equal((await db.query('SELECT status FROM app_users WHERE id=$1',[users[1]])).rows[0].status,'approved');
   const stage=(await db.query('SELECT stage FROM admin_customer_crm WHERE customer_id=$1',[users[1]])).rows[0].stage;
   assert.equal((await list('&stage='+stage)).body.data.items[0].id,users[1]);assert.equal((await list('&sort=activity')).body.data.items[0].id,users[1]);
  });
 }finally{
  await new Promise<void>(r=>server.close(()=>r()));await db.query('DELETE FROM audit_logs WHERE entity_id=ANY($1::text[])',[users]);await db.query('DELETE FROM payments WHERE customer_id=ANY($1::uuid[])',[users]);await db.query('DELETE FROM customer_addresses WHERE user_id=ANY($1::uuid[])',[users]);await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])',[[...users,admin,cleaner]]);await db.close();
 }
});
