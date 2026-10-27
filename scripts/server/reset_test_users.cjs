// Explicitly authorized operator reset. Never called by the application.
const crypto=require('crypto');
const q=n=>'"'+n.replaceAll('"','""')+'"';
const users="SELECT id FROM reset_users";
const owned=`IN (${users})`;
const orderIds='IN (SELECT id FROM reset_orders)';
const packageIds='IN (SELECT id FROM reset_packages)';
const chatIds='IN (SELECT id FROM reset_chats)';
const installationIds='IN (SELECT id FROM reset_installations)';
const preserved=['catalog_packages','catalog_addons','addon_groups','checklist_templates','checklist_template_items','promotions','banners','app_settings','translations','content_pages','service_zones','connected_houses','training_videos','city_directory','package_plans','addons','cleaning_slots','closed_days','status_config','assignment_config','legacy_firestore_documents'];
async function digest(db,table,where='TRUE'){
 const r=await db.query(`SELECT count(*)::int AS count, md5(COALESCE(string_agg(h,'' ORDER BY h),'')) AS hash FROM (SELECT md5(to_jsonb(t)::text) h FROM ${q(table)} t WHERE ${where}) s`);return r.rows[0];
}
async function snapshot(db){
 const tables=(await db.query("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename")).rows.map(x=>x.tablename);
 const counts={};for(const t of tables)counts[t]=(await db.query(`SELECT count(*)::int n FROM ${q(t)}`)).rows[0].n;
 const keep={};for(const t of tables.filter(t=>preserved.includes(t)||t.startsWith('tech_')))keep[t]=await digest(db,t);
 keep.administrators=await digest(db,'app_users',"role::text IN ('admin','superadmin')");
 const roles=(await db.query('SELECT role::text, count(*)::int AS count FROM app_users GROUP BY role ORDER BY role')).rows;
 const ids=(await db.query(`SELECT 'user:'||id::text x FROM app_users WHERE role::text NOT IN ('admin','superadmin') UNION ALL SELECT 'payment:'||id::text FROM payments UNION ALL SELECT 'order:'||id::text FROM service_orders UNION ALL SELECT 'package:'||id::text FROM customer_packages ORDER BY x`)).rows;
 return {counts,roles,preserved:keep,planHash:crypto.createHash('sha256').update(JSON.stringify(ids)).digest('hex')};
}
async function reset(db,{mode='audit',expectedPlan,operationId='test'}={}){
 await db.query('BEGIN');
 try{
  await db.query("SET LOCAL lock_timeout='15s'; SET LOCAL statement_timeout='120s'");
  // Freeze writes during the transaction; the workflow also stops API/workers for backup.
  const tables=(await db.query("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename")).rows.map(x=>x.tablename);
  if(mode!=='audit')await db.query('LOCK TABLE '+tables.map(q).join(',')+' IN SHARE ROW EXCLUSIVE MODE');
  const before=await snapshot(db);
  if(mode==='audit'){await db.query('ROLLBACK');return {mode,before};}
  if(!['apply','rehearse'].includes(mode))throw Error('Invalid mode');
  if(!before.preserved.administrators.count)throw Error('No administrator: reset refused');
  if(expectedPlan!==before.planHash)throw Error('Audited target set changed: reset refused');
  await db.query(`CREATE TEMP TABLE reset_users ON COMMIT DROP AS SELECT id,phone FROM app_users WHERE role::text NOT IN ('admin','superadmin');
CREATE TEMP TABLE reset_payments ON COMMIT DROP AS SELECT id FROM payments;
CREATE TEMP TABLE reset_orders ON COMMIT DROP AS SELECT id FROM service_orders WHERE customer_id ${owned} OR cleaner_id ${owned};
CREATE TEMP TABLE reset_packages ON COMMIT DROP AS SELECT id FROM customer_packages WHERE customer_id ${owned};
CREATE TEMP TABLE reset_chats ON COMMIT DROP AS SELECT id FROM chats WHERE customer_id ${owned} OR order_id ${orderIds} OR id IN (SELECT chat_id FROM chat_participants WHERE user_id ${owned});
CREATE TEMP TABLE reset_installations ON COMMIT DROP AS SELECT id FROM assistant_installations WHERE customer_id ${owned} OR chat_id ${chatIds};
INSERT INTO reset_chats SELECT id FROM chats WHERE installation_id ${installationIds} AND id NOT IN (SELECT id FROM reset_chats)`);
  const changed={};const del=async(t,w='TRUE')=>{changed[t]=(await db.query(`DELETE FROM ${q(t)} WHERE ${w}`)).rowCount;};
  // Keep immutable operational evidence and uploaded files; detach deleted owners only.
  changed.auditActors=(await db.query(`UPDATE audit_logs SET actor_id=NULL WHERE actor_id ${owned}`)).rowCount;
  changed.fileOwners=(await db.query(`UPDATE files SET owner_id=NULL WHERE owner_id ${owned}`)).rowCount;
  await del('moon_ai_outbox',`customer_id ${owned} OR payment_id IS NOT NULL OR chat_id ${chatIds} OR installation_id ${installationIds}`);
  await del('moon_ai_payment_callbacks');
  await del('payment_events');
  await del('area_package_adjustments',`customer_package_id ${packageIds} OR payment_id IS NOT NULL`);
  await del('bot_area_events',`customer_id ${owned}`);
  await del('quality_check_requests',`customer_id ${owned} OR order_id ${orderIds} OR customer_package_id ${packageIds}`);
  await del('preorders',`customer_id ${owned} OR customer_package_id ${packageIds} OR payment_id IS NOT NULL`);
  await del('bonus_transactions',`user_id ${owned} OR order_id ${orderIds} OR payment_id IS NOT NULL`);
  await del('promotion_redemptions',`customer_id ${owned} OR customer_package_id ${packageIds} OR payment_id IS NOT NULL`);
  await del('payments');
  await db.query(`UPDATE assistant_installations SET chat_id=NULL WHERE id ${installationIds}; UPDATE chats SET installation_id=NULL WHERE id ${chatIds}`);
  await del('assistant_installations',`id ${installationIds}`);
  await del('chats',`id ${chatIds}`);
  await del('chat_messages',`sender_id ${owned}`);
  await del('complaints',`customer_id ${owned} OR cleaner_id ${owned} OR order_id ${orderIds}`);
  await del('reviews',`customer_id ${owned} OR cleaner_id ${owned} OR order_id ${orderIds}`);
  await del('service_orders',`id ${orderIds}`);
  await del('customer_packages',`id ${packageIds}`);
  await del('payouts',`cleaner_id ${owned}`);
  await del('user_referrals',`customer_id ${owned} OR inviter_id ${owned}`);
  await del('house_waitlist',`user_id ${owned}`);
  await del('service_address_requests',`customer_id ${owned}`);
  await del('notifications',`user_id ${owned} OR target_id IN (SELECT id::text FROM reset_users UNION SELECT id::text FROM reset_orders UNION SELECT id::text FROM reset_packages UNION SELECT id::text FROM reset_payments)`);
  await del('auth_otp_codes',`phone IN (SELECT phone FROM reset_users) AND (role IS NULL OR role::text NOT IN ('admin','superadmin'))`);
  // Legacy scheduling data are user/order data, not catalogue configuration.
  for(const t of ['assignments','orders','scheduled_cleanings','user_packages','custom_package_drafts','custom_packages','cleaner_status_history','cleaner_monthly_stats','cleaners','apartments'])await del(t);
  await del('app_users',`id ${owned}`);
  const after=await snapshot(db);
  if(JSON.stringify(before.preserved)!==JSON.stringify(after.preserved))throw Error('Preserved data changed: rollback');
  if(after.roles.some(x=>!['admin','superadmin'].includes(x.role))||after.counts.payments||after.counts.service_orders||after.counts.customer_packages)throw Error('Reset postconditions failed: rollback');
  const report={mode,operationId,before,changed,after};
  await db.query("INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('operator.authorized_user_reset','maintenance',$1,$2)",[operationId,JSON.stringify({planHash:before.planHash,changed,preservedVerified:true})]);
  await db.query(mode==='rehearse'?'ROLLBACK':'COMMIT');return report;
 }catch(e){await db.query('ROLLBACK');throw e;}
}
module.exports={reset,snapshot};
if(!module.parent){
 const {Client}=require('pg');const db=new Client({connectionString:process.env.DATABASE_URL});
 (async()=>{await db.connect();try{console.log(JSON.stringify(await reset(db,{mode:process.env.RESET_MODE||'audit',expectedPlan:process.env.RESET_EXPECTED_PLAN,operationId:process.env.RESET_OPERATION_ID})));}finally{await db.end();}})().catch(e=>{console.error(JSON.stringify({error:e.code||e.message}));process.exitCode=1;});
}
