const assert=require('node:assert/strict');
const {Pool}=require('pg');
const {signAccessToken}=require('./dist/common/auth');
const {env}=require('./dist/common/env');
const fs=require('node:fs');
(async()=>{
 const db=new Pool({connectionString:process.env.DATABASE_URL});
 try {
  const admin=(await db.query("SELECT id,role FROM app_users WHERE role IN ('admin','superadmin') AND deleted_at IS NULL LIMIT 1")).rows[0];assert.ok(admin);
  const token=signAccessToken({...admin,phone:'server-audit'});
  async function get(path){const response=await fetch('http://127.0.0.1:'+env.port+'/api/v1'+path,{headers:{Authorization:'Bearer '+token}});assert.equal(response.status,200);return (await response.json()).data;}
  const quality=await get('/admin/quality?limit=200');
  for(const q of quality)if(['pending','scheduled'].includes(q.review_status))assert.equal(q.status,'open');
  const orders=await get('/admin/orders?limit=200');let timed=0;
  for(const o of orders) {if(o.start_time){assert.match(o.start_time,/^\d{2}:\d{2}$/);timed++;}if(o.end_time)assert.match(o.end_time,/^\d{2}:\d{2}$/);}
  const route=fs.readFileSync('./dist/http/routes/v1.js','utf8');
  const bot=fs.readFileSync('./dist/modules/botIntegration.js','utf8');
  assert.ok(route.includes('document_required'));assert.ok(bot.includes('document_required'));
  console.log('AREA_DEPLOY_CHECK '+JSON.stringify({qualityRecords:quality.length,open:quality.filter(q=>q.status==='open').length,awaitingPlan:quality.filter(q=>!q.document_file_id&&q.status==='open').length,orderRecords:orders.length,timedOrders:timed,clocks:'HH:mm',customerPlanGuard:true,botPlanGuard:true}));
 } finally {await db.end()}
})().catch(e=>{console.error('AREA_DEPLOY_CHECK_ERROR',e.code||e.message);process.exit(1)});
