// Read-only verification. Never invokes message sending or creates customer rows.
const assert=require('node:assert/strict');
const {Pool}=require('pg');
const {env}=require('./dist/common/env');
const {moonAiReady,scheduleSignupFollowup}=require('./dist/modules/moonAi');
const {moonMessengerReady,signupWelcomeTemplate}=require('./dist/modules/moonMessenger');
(async()=>{
  assert.equal(moonAiReady(),true);assert.equal(moonMessengerReady(),true);
  assert(scheduleSignupFollowup.toString().includes("INTERVAL '10 minutes'"));
  const url=`https://core.mooonai.com/api/v1/organizations/${env.moonAiOrganizationId}/agents/${env.moonAiAgentId}/channels/${env.moonAiWabaChannelId}/whatsapp-templates?status=APPROVED`;
  const response=await fetch(url,{headers:{Authorization:`Bearer ${env.moonAiRestApiKey}`},signal:AbortSignal.timeout(30000)});
  assert.equal(response.status,200);
  const body=await response.json(),template=(body.templates??[]).find(t=>t.name===signupWelcomeTemplate&&t.status==='APPROVED');
  assert(template,'Signup welcome template must be approved');
  const pool=new Pool({connectionString:process.env.DATABASE_URL});
  try {
    const obsolete=(await pool.query("SELECT COUNT(*)::int n FROM moon_ai_outbox WHERE kind='inactive_signup' AND state='pending' AND started_at IS NULL AND run_after=created_at+INTERVAL '5 minutes'")).rows[0].n;
    assert.equal(obsolete,0);
    const queue=(await pool.query("SELECT state,COUNT(*)::int count FROM moon_ai_outbox WHERE kind='inactive_signup' GROUP BY state ORDER BY state")).rows;
    console.log('WHATSAPP_SIGNUP_AUDIT='+JSON.stringify({delaySeconds:600,integrationReady:true,templateName:template.name,templateStatus:template.status,oldFiveMinutePending:obsolete,queue}));
  }finally{await pool.end();}
})().catch(()=>{console.error('WhatsApp signup verification failed');process.exitCode=1;});
