const {Pool}=require('pg');
const {signAccessToken}=require('./dist/common/auth');
const {env}=require('./dist/common/env');
(async()=>{
 const db=new Pool({connectionString:process.env.DATABASE_URL});
 try {
  const admin=(await db.query("SELECT id,role FROM app_users WHERE role IN ('admin','superadmin') AND deleted_at IS NULL LIMIT 1")).rows[0];
  if(!admin)throw Error('admin_missing');
  const token=signAccessToken({...admin,phone:'server-audit'});
  const expected=(await db.query(`SELECT DISTINCT ON(q.id) q.id,e.evidence->>'documentUrl' AS url
    FROM quality_check_requests q JOIN bot_area_events e
    ON e.customer_id=q.customer_id AND e.result->>'qualityCheckId'=q.id::text
    WHERE q.status='approved' AND e.evidence->>'documentType'='technical_plan'
      AND e.evidence->>'documentUrl' LIKE 'https://%'
    ORDER BY q.id,e.created_at DESC,e.event_id DESC LIMIT 20`)).rows;
  let checked=0;
  for(const row of expected) {
    const response=await fetch('http://127.0.0.1:'+env.port+'/api/v1/admin/quality-checks/'+row.id+'/details',{headers:{Authorization:'Bearer '+token}});
    if(response.status!==200)throw Error('admin_details_unavailable');
    const result=await response.json();
    if(result.data?.qualityCheck?.document_url!==row.url || result.data?.qualityCheck?.areaTechnicalPlanUrl!==row.url)throw Error('approved_plan_missing');
    checked++;
  }
  const {areaPlanEvidenceJoin}=require('./dist/modules/areaPlanEvidence');
  if(!areaPlanEvidenceJoin.includes('e.customer_id=q.customer_id'))throw Error('customer_scope_missing');
  console.log('BOT_PLAN_CHECK '+JSON.stringify({approvedBotRequests:expected.length,detailsChecked:checked,planUrlsMatch:true,customerScoped:true,readOnly:true}));
 } finally {await db.end()}
})().catch(e=>{console.error('BOT_PLAN_CHECK_FAILED',e.code||'verification_failed');process.exit(1)});
