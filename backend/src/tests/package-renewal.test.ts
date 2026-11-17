import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Database} from '../infrastructure/db/Database';
import {env} from '../common/env';
import {queuePackageRenewals,packageRenewalStillEligible,packageRenewalText} from '../modules/packageRenewal';
import {sendMessengerFollowup} from '../modules/moonMessenger';

test('renewal messages use the renewal text, not the abandoned-payment prompt',async()=>{
 const old={enabled:env.moonAiEnabled,key:env.moonAiRestApiKey,org:env.moonAiOrganizationId,agent:env.moonAiAgentId};
 Object.assign(env,{moonAiEnabled:true,moonAiRestApiKey:'fixture',moonAiOrganizationId:'1',moonAiAgentId:'2'});
 const sent:any[]=[];
 try{await sendMessengerFollowup({id:randomUUID(),kind:'package_renewal',text:packageRenewalText,phone:'+77000000001'},async(url:any,input:any)=>{
  if(input.method==='GET')return new Response(JSON.stringify({results:[{id:'fixture',channel_type:'whatsapp_business',metadata:{phone_number:'77000000001'},status:'active',free_form_window_expires_at:new Date(Date.now()+3600000).toISOString()}]}));
  if(input.method==='POST'){sent.push(JSON.parse(input.body));return new Response(JSON.stringify({id:'fixture-message'}));}
  return new Response('{}');
 });assert.equal(sent.length,1);assert.ok(sent[0].data.text.includes(packageRenewalText));assert.equal(sent[0].data.text.includes('не завершена'),false);
 }finally{Object.assign(env,{moonAiEnabled:old.enabled,moonAiRestApiKey:old.key,moonAiOrganizationId:old.org,moonAiAgentId:old.agent});}
});

test('package renewal: completed credits only, one message, newer plan and opt-out protection',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async t=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),user=randomUUID(),catalog=randomUUID();const old=env.moonAiEnabled;env.moonAiEnabled=true;
 const ids:string[]=[];
 async function pkg(available=0,status='active'){
  const id=randomUUID();ids.push(id);
  await db.query(`INSERT INTO customer_packages(id,customer_id,package_id,total_cleanings,available_cleanings,status) VALUES($1,$2,$3,1,$4,$5)`,[id,user,catalog,available,status]);
  await db.query("INSERT INTO payments(customer_id,customer_package_id,provider,status,amount,paid_at,applied_at) VALUES($1,$2,'kaspi','paid',100,NOW(),NOW())",[user,id]);return id;
 }
 try{
  await db.query("INSERT INTO app_users(id,phone,role,status) VALUES($1,$2,'customer','approved')",[user,'+770'+String(Math.floor(Math.random()*1e8)).padStart(8,'0')]);
  await db.query("INSERT INTO catalog_packages(id,name_ru,cleaning_count,months,base_price) VALUES($1,'Fixture renewal',1,1,100)",[catalog]);
  const cp=await pkg();const eligible=()=>packageRenewalStillEligible(db,user,cp);
  await t.test('zero free credits from a reserved visit do not trigger renewal',async()=>{
   await db.query("INSERT INTO service_orders(customer_id,customer_package_id,package_id,scheduled_date,start_time,end_time,status) VALUES($1,$2,$3,CURRENT_DATE,'10:00','11:00','assigned')",[user,cp,catalog]);assert.equal(await eligible(),false);
  });
  await t.test('completion queues one message, repeat scans never duplicate',async()=>{
   await db.query("UPDATE service_orders SET status='completed' WHERE customer_id=$1",[user]);assert.equal(await eligible(),true);
   await queuePackageRenewals(db);await queuePackageRenewals(db);
   const rows=(await db.query("SELECT * FROM moon_ai_outbox WHERE customer_id=$1 AND kind='package_renewal'",[user])).rows;assert.equal(rows.length,1);assert.equal(rows[0].payload.text,packageRenewalText);
  });
  await t.test('another paid package, a pending visit, opted-out and deleted users are excluded',async()=>{
   const next=await pkg(2);assert.equal(await eligible(),false);
   await db.query("UPDATE customer_packages SET status='cancelled' WHERE id=$1",[next]);await db.query('DELETE FROM payments WHERE customer_package_id=$1',[next]);assert.equal(await eligible(),true);
   await db.query("UPDATE app_users SET settings=settings||'{\"whatsappOptOut\":true}'::jsonb WHERE id=$1",[user]);assert.equal(await eligible(),false);
   await db.query("UPDATE app_users SET settings='{}',deleted_at=NOW() WHERE id=$1",[user]);assert.equal(await eligible(),false);
  });
  await t.test('monthly expiry without completed visits does not qualify',async()=>{
   await db.query('UPDATE app_users SET deleted_at=NULL WHERE id=$1',[user]);const expired=await pkg(0,'expired');assert.equal(await packageRenewalStillEligible(db,user,expired),false);
  });
 }finally{
  env.moonAiEnabled=old;
  await db.query('DELETE FROM audit_logs WHERE entity_id=ANY($1::text[])',[ids]);
  await db.query('DELETE FROM moon_ai_outbox WHERE customer_id=$1',[user]);await db.query('DELETE FROM chat_participants WHERE user_id=$1',[user]);await db.query('DELETE FROM chats WHERE customer_id=$1',[user]);
  await db.query('DELETE FROM service_orders WHERE customer_id=$1',[user]);await db.query('DELETE FROM payments WHERE customer_id=$1',[user]);await db.query('DELETE FROM customer_packages WHERE customer_id=$1',[user]);await db.query('DELETE FROM app_users WHERE id=$1',[user]);await db.query('DELETE FROM catalog_packages WHERE id=$1',[catalog]);await db.close();
 }
});
