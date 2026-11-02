// Explicit operator maintenance. Never imported by the API or migrations.
const crypto = require('crypto');
const ADMIN_ROLES = new Set(['admin', 'superadmin']);
const WIPE = [
  'account_deletion_requests','area_package_adjustments','assignments',
  'assistant_installation_tokens','assistant_installations','apartments',
  'bonus_transactions','bot_area_events','chat_messages','chat_participants','chats',
  'checklist_report_items','checklist_reports','cleaner_documents','cleaner_monthly_stats',
  'cleaner_profiles','cleaner_status_history','cleaner_work_schedule_requests',
  'cleaner_working_days','cleaner_zones','cleaners','complaints',
  'custom_package_drafts','custom_packages','customer_addresses','customer_packages',
  'house_waitlist','moon_ai_outbox','moon_ai_payment_callbacks','order_addons',
  'order_offers','order_status_history','orders','payment_events','payments','payouts',
  'photo_reports','preorders','promotion_redemptions','quality_check_requests',
  'reviews','scheduled_cleanings','service_address_requests','service_orders',
  'user_packages','user_referrals','video_views',
];
const MIXED = ['app_users','auth_otp_codes','refresh_sessions','device_tokens',
  'api_idempotency','audit_logs','notifications','notification_reads',
  'notification_deliveries','files'];
const CONTENT = ['app_settings','banners','promotions','catalog_addons',
  'catalog_packages','content_pages','training_videos','tech_files'];
const qi = value => { if (!/^[a-z_][a-z_0-9]*$/.test(value)) throw Error('Invalid identifier'); return '"'+value+'"'; };
const digest = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
function references(value, ids) {
  if (typeof value === 'string') return ids.has(value);
  if (Array.isArray(value)) return value.some(x=>references(x,ids));
  return !!value && typeof value === 'object' && Object.values(value).some(x=>references(x,ids));
}
function deleteOrder(tables, fks) {
  const remaining = new Set(tables), ordered = [];
  while (remaining.size) {
    const ready=[...remaining].filter(parent=>!fks.some(f=>f.parent===parent && f.child!==parent && remaining.has(f.child) && !(f.child==='chats' && f.parent==='assistant_installations'))).sort();
    if (!ready.length) throw Error('Unexpected FK cycle; no deletion permitted');
    for (const name of ready) { ordered.push(name); remaining.delete(name); }
  }
  return ordered;
}
async function metadata(c) {
  const tables=(await c.query("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename")).rows.map(x=>x.tablename);
  const fks=(await c.query(`SELECT child.relname child,parent.relname parent,ca.attname child_column,pa.attname parent_column
    FROM pg_constraint k JOIN pg_class child ON child.oid=k.conrelid JOIN pg_class parent ON parent.oid=k.confrelid
    JOIN pg_attribute ca ON ca.attrelid=k.conrelid AND ca.attnum=k.conkey[1]
    JOIN pg_attribute pa ON pa.attrelid=k.confrelid AND pa.attnum=k.confkey[1]
    WHERE k.contype='f' AND k.connamespace='public'::regnamespace ORDER BY 1,2,3`)).rows;
  return {tables,fks};
}
async function rows(c, table) { return (await c.query(`SELECT ctid::text locator,to_jsonb(t) data FROM ${qi(table)} t ORDER BY ctid`)).rows; }
async function inspect(c, meta) {
  for (const name of [...WIPE,...MIXED,...CONTENT]) if (!meta.tables.includes(name)) throw Error('Required table missing: '+name);
  const source={};for(const t of [...WIPE,...MIXED]) source[t]=await rows(c,t);
  const admins=source.app_users.filter(x=>ADMIN_ROLES.has(x.data.role));
  if (!admins.length || admins.some(x=>x.data.deleted_at || x.data.status==='blocked')) throw Error('No active administrator to retain');
  const removed=source.app_users.filter(x=>!ADMIN_ROLES.has(x.data.role));
  const adminIds=new Set(admins.map(x=>x.data.id)), userIds=new Set(removed.map(x=>x.data.id));
  // Do not erase purchases or profiles owned by a retained administrator.
  for (const t of ['customer_addresses','customer_packages','service_orders','quality_check_requests','payments','cleaner_profiles']) {
    if(source[t].some(x=>adminIds.has(x.data.customer_id ?? x.data.user_id))) throw Error('Administrator owns domain data: '+t);
  }
  const targets={};for(const t of WIPE)targets[t]=source[t];
  targets.app_users=removed;
  const ids=new Set(userIds);
  for (const list of Object.values(targets)) for(const {data} of list) {
    for(const key of ['id','event_id','legacy_firestore_id','firebase_uid']) if(typeof data[key]==='string')ids.add(data[key]);
  }
  const adminPhones=new Set(admins.map(x=>x.data.phone));
  targets.auth_otp_codes=source.auth_otp_codes.filter(x=>!adminPhones.has(x.data.phone) || (x.data.role && !ADMIN_ROLES.has(x.data.role)));
  for(const t of ['refresh_sessions','device_tokens'])targets[t]=source[t].filter(x=>userIds.has(x.data.user_id));
  targets.api_idempotency=source.api_idempotency.filter(x=>userIds.has(x.data.user_id)||references(x.data.response,ids));
  targets.audit_logs=source.audit_logs.filter(x=>userIds.has(x.data.actor_id)||ids.has(x.data.entity_id)||references(x.data.payload,ids));
  targets.notifications=source.notifications.filter(x=>userIds.has(x.data.user_id)||['customer','cleaner'].includes(x.data.role)||ids.has(x.data.target_id));
  const notificationIds=new Set(targets.notifications.map(x=>x.data.id));
  targets.notification_reads=source.notification_reads.filter(x=>userIds.has(x.data.user_id)||notificationIds.has(x.data.notification_id));
  targets.notification_deliveries=source.notification_deliveries.filter(x=>notificationIds.has(x.data.notification_id));
  // Files used by catalog/content/technical records must survive even if uploaded by a removed user.
  const shared=[];for(const t of CONTENT) shared.push(...(await rows(c,t)).map(x=>x.data));
  shared.push(...admins.map(x=>x.data));
  const sharedText=JSON.stringify(shared);
  const domainText=JSON.stringify(Object.fromEntries(WIPE.map(t=>[t,source[t].map(x=>x.data)])));
  const detachFiles=[];targets.files=[];
  for(const row of source.files){
    const f=row.data, tokens=[f.id,f.public_url,f.object_key].filter(x=>typeof x==='string'&&x.length>10);
    const candidate=userIds.has(f.owner_id)||tokens.some(x=>domainText.includes(x));
    const sharedFile=tokens.some(x=>sharedText.includes(x));
    if(candidate && !sharedFile)targets.files.push(row);
    else if(userIds.has(f.owner_id))detachFiles.push(f.id);
  }
  // Any live-schema FK crossing into untouched data is a blocker, never a cascade.
  for(const f of meta.fks){
    if(!targets[f.parent]?.length)continue;
    const parentIds=new Set(targets[f.parent].map(x=>x.data[f.parent_column]));
    const children=source[f.child]??await rows(c,f.child);
    const deletedLocators=new Set((targets[f.child]??[]).map(x=>x.locator));
    if(children.some(x=>parentIds.has(x.data[f.child_column])&&!deletedLocators.has(x.locator) &&
      !(f.child==='files'&&f.child_column==='owner_id'&&detachFiles.includes(x.data.id))))throw Error('Untouched FK reference: '+f.child+'.'+f.child_column);
  }
  const identity=row=>{
    const d=row.data;
    if(d.id)return d.id;
    return digest(Object.fromEntries(Object.entries(d).filter(([key])=>key.endsWith('_id')||['scope','key','month','work_date','token'].includes(key)).sort()));
  };
  const planHash=digest({version:1,admins:admins.map(x=>x.data.id).sort(),targets:Object.fromEntries(Object.entries(targets).sort().map(([t,list])=>[t,list.map(identity).sort()])),detachFiles:[...detachFiles].sort()});
  return {targets,detachFiles,admins,ids,planHash,summary:{planHash,retainedAdmins:admins.map(x=>({numericId:x.data.numeric_id,role:x.data.role,phoneSuffix:x.data.phone.slice(-4)})),deleteCounts:Object.fromEntries(Object.entries(targets).map(([t,list])=>[t,list.length])),sharedFilesRetained:detachFiles.length}};
}
async function tableHash(c,t) {
  return (await c.query(`SELECT COUNT(*)::int count,md5(COALESCE(string_agg(h,'' ORDER BY h),'')) hash FROM (SELECT md5(to_jsonb(t)::text) h FROM ${qi(t)} t) s`)).rows[0];
}
async function cleanup(c, {mode='audit',expectedPlan='',operationId='local-test',backupVerified=false,afterDelete}={}) {
  let committed=false;
  await c.query(mode==='apply'?'BEGIN':'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
  try {
    const meta=await metadata(c);
    if(mode==='apply') {
      if(!backupVerified||!/^\d+$/.test(operationId))throw Error('Verified backup and operation ID required');
      await c.query("SET LOCAL lock_timeout='10s'");
      await c.query("SET LOCAL statement_timeout='120s'");
      await c.query(`LOCK TABLE ${meta.tables.map(qi).join(',')} IN SHARE ROW EXCLUSIVE MODE`);
    }
    const plan=await inspect(c,meta);
    if(mode!=='apply'){await c.query('COMMIT');committed=true;return plan.summary;}
    if(plan.planHash!==expectedPlan)throw Error('Cleanup plan changed; run audit again');
    const untouched=meta.tables.filter(t=>!WIPE.includes(t)&&!MIXED.includes(t));
    const protectedBefore={};for(const t of untouched)protectedBefore[t]=await tableHash(c,t);
    const adminBefore=digest(plan.admins.map(x=>x.data));
    await c.query('UPDATE chats SET installation_id=NULL WHERE installation_id IS NOT NULL');
    if(plan.detachFiles.length)await c.query('UPDATE files SET owner_id=NULL WHERE id=ANY($1::uuid[])',[plan.detachFiles]);
    const actual={};
    for(const t of deleteOrder(Object.keys(plan.targets),meta.fks)){
      const intended=plan.targets[t];
      if(WIPE.includes(t))actual[t]=(await c.query(`DELETE FROM ${qi(t)}`)).rowCount;
      else actual[t]=intended.length?(await c.query(`DELETE FROM ${qi(t)} WHERE ctid=ANY($1::tid[])`,[intended.map(x=>x.locator)])).rowCount:0;
      if(actual[t]!==intended.length)throw Error('Unexpected deletion count: '+t);
    }
    if(afterDelete)await afterDelete(c);
    for(const t of WIPE)if(Number((await c.query(`SELECT COUNT(*) n FROM ${qi(t)}`)).rows[0].n))throw Error('Remaining user data: '+t);
    const currentAdmins=(await rows(c,'app_users')).map(x=>x.data);
    if(digest(currentAdmins)!==adminBefore)throw Error('Administrator changed');
    for(const t of untouched)if(digest(await tableHash(c,t))!==digest(protectedBefore[t]))throw Error('Protected data changed: '+t);
    await c.query(`INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload) VALUES($1,'ops.user_cleanup','maintenance',$2,$3)`,[plan.admins[0].data.id,operationId,JSON.stringify({planHash:plan.planHash,deleted:actual,sharedFilesRetained:plan.detachFiles.length,protectedTablesVerified:untouched.length})]);
    await c.query('COMMIT');committed=true;
    return {...plan.summary,applied:true,protectedTablesVerified:untouched.length,remainingUsers:currentAdmins.length,deletedEntityIds:[...plan.ids],deletedNotificationIds:plan.targets.notifications.map(x=>x.data.id)};
  }finally{if(!committed)await c.query('ROLLBACK');}
}
async function main(){
  const {Pool}=require('pg');const p=new Pool({connectionString:process.env.DATABASE_URL,max:1});const c=await p.connect();
  try{const result=await cleanup(c,{mode:process.env.CLEANUP_MODE,expectedPlan:process.env.CLEANUP_EXPECTED_PLAN,operationId:process.env.CLEANUP_OPERATION_ID,backupVerified:process.env.CLEANUP_BACKUP_VERIFIED==='true'});
    const {deletedEntityIds,deletedNotificationIds,...summary}=result;
    if(result.applied && process.env.CLEANUP_REDIS==='true') {
      const IORedis=require('ioredis'),{Queue}=require('bullmq');
      const connection=new IORedis(process.env.REDIS_URL,{maxRetriesPerRequest:1});
      const ids=new Set([...deletedEntityIds,...deletedNotificationIds]);summary.removedQueueJobs={};
      try { for(const name of ['notifications','cleaner-alarms','payments','maintenance','moon-ai']) {
        const queue=new Queue(name,{connection});let count=0;
        try { const jobs=await queue.getJobs(['wait','active','delayed','prioritized','failed','completed','waiting-children','paused'],0,-1);
          for(const job of jobs)if(references(job.data,ids)){await job.remove();count++;}
          summary.removedQueueJobs[name]=count;
        }finally{await queue.close();}
      }}finally{await connection.quit();}
    }
    console.log('USER_CLEANUP_RESULT='+JSON.stringify(summary));}
  finally{c.release();await p.end();}
}
module.exports={WIPE,MIXED,references,deleteOrder,cleanup};
if(require.main===module || !require.main)main().catch(error=>{console.error('User cleanup stopped:',error.message);process.exitCode=1;});
