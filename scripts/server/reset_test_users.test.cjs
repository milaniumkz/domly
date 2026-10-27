const assert=require('node:assert/strict');
const {reset,snapshot}=require('./reset_test_users.cjs');
const {randomUUID}=require('crypto');
// Requires a disposable database whose name explicitly identifies this reset test.
async function main(){
 const {Client}=require('pg');const url=new URL(process.env.RESET_TEST_DATABASE_URL);
 if(!url.pathname.startsWith('/domly_reset_test_'))throw Error('Disposable database required');
 const db=new Client({connectionString:url.href});await db.connect();
 try{
  await db.query(require('fs').readFileSync(require('path').join(__dirname,'../../backend/sql/schema.sql'),'utf8'));
  const [admin,superadmin,customer,cleaner,pack,subscription,order,payment,chat,installation,file]=Array.from({length:11},randomUUID);
  for(const [id,role]of [[admin,'admin'],[superadmin,'superadmin'],[customer,'customer'],[cleaner,'cleaner']])await db.query("INSERT INTO app_users(id,phone,role,password_hash) VALUES($1,$2,$3,'preserve-credential')",[id,'reset-test-'+id,role]);
  await db.query("INSERT INTO files(id,owner_id,bucket,object_key) VALUES($1,$2,'test','preserved-file')",[file,customer]);
  await db.query("INSERT INTO banners(title_ru,image_file_id) VALUES('Preserve this banner',$1)",[file]);
  await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,base_price) VALUES($1,'Test tariff',4,100)",[pack]);
  await db.query("INSERT INTO customer_packages(id,customer_id,package_id,total_cleanings,available_cleanings) VALUES($1,$2,$3,4,4)",[subscription,customer,pack]);
  await db.query("INSERT INTO service_orders(id,customer_id,cleaner_id,customer_package_id) VALUES($1,$2,$3,$4)",[order,customer,cleaner,subscription]);
  await db.query("INSERT INTO payments(id,customer_id,order_id,provider,amount) VALUES($1,$2,$3,'kaspi',100)",[payment,customer,order]);
  await db.query("INSERT INTO payment_events(payment_id,provider,event_type) VALUES($1,'kaspi','test')",[payment]);
  await db.query("INSERT INTO bonus_transactions(user_id,order_id,payment_id,type,amount,balance_after,reason_ru) VALUES($1,$2,$3,'spend',-10,0,'test')",[customer,order,payment]);
  await db.query("INSERT INTO chats(id,type,customer_id,order_id) VALUES($1,'assistant',$2,$3)",[chat,customer,order]);
  await db.query("INSERT INTO assistant_installations(id,key_hash,customer_id,chat_id) VALUES($1,$2,$3,$4)",[installation,installation,customer,chat]);
  await db.query('UPDATE chats SET installation_id=$1 WHERE id=$2',[installation,chat]);
  await db.query('INSERT INTO chat_participants(chat_id,user_id) VALUES($1,$2),($1,$3)',[chat,customer,admin]);
  await db.query("INSERT INTO moon_ai_outbox(customer_id,chat_id,payment_id,kind,dedupe_key,payload) VALUES($1,$2,$3,'invoice','test','{}')",[customer,chat,payment]);
  await db.query("INSERT INTO audit_logs(actor_id,action,entity_type) VALUES($1,'preserve','test')",[customer]);
  await db.query("INSERT INTO notifications(user_id,title_ru,body_ru,target_id) VALUES($1,'Old payment','test',$2)",[admin,payment]);
  const initial=await snapshot(db);
  await assert.rejects(reset(db,{mode:'apply',expectedPlan:'wrong'}),/target set changed/);
  assert.deepEqual(await snapshot(db),initial);
  const rehearsal=await reset(db,{mode:'rehearse',expectedPlan:initial.planHash});
  assert.equal(rehearsal.after.counts.app_users,2);assert.equal(rehearsal.after.counts.payments,0);
  assert.deepEqual(await snapshot(db),initial);
  const applied=await reset(db,{mode:'apply',expectedPlan:initial.planHash});
  assert.equal(applied.after.counts.app_users,2);assert.equal(applied.after.counts.service_orders,0);
  assert.deepEqual(applied.before.preserved,applied.after.preserved);
  assert.equal((await db.query('SELECT owner_id FROM files WHERE id=$1',[file])).rows[0].owner_id,null);
  assert.equal((await db.query("SELECT count(*)::int n FROM audit_logs WHERE action='preserve'")).rows[0].n,1);
  const again=await snapshot(db);await reset(db,{mode:'apply',expectedPlan:again.planHash});
  assert.equal((await snapshot(db)).counts.app_users,2);
  console.log('PASS: stale-plan rollback, rehearsal rollback, administrators/configuration/files preserved, linked history deleted, repeat operation safe');
 }finally{await db.end();}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
