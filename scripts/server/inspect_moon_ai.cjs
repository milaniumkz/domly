// Operational diagnostics: no credentials, phone numbers, text or payloads.
const {Pool}=require('pg');
const {Queue}=require('bullmq');
(async()=>{
 console.log('MoonAI configuration:',JSON.stringify({enabled:process.env.MOON_AI_ENABLED==='true',channelUrlConfigured:!!process.env.MOON_AI_CHANNEL_URL,channelKeyConfigured:!!process.env.MOON_AI_CHANNEL_API_KEY,webhookConfigured:!!process.env.MOON_AI_WEBHOOK_TOKEN}));
 const db=new Pool({connectionString:process.env.DATABASE_URL});
 try{
  console.log('Outbox:',JSON.stringify((await db.query('SELECT kind,state,failure_code,COUNT(*)::int AS count FROM moon_ai_outbox GROUP BY kind,state,failure_code ORDER BY kind,state')).rows));
  console.log('Recent technical deliveries:',JSON.stringify((await db.query("SELECT kind,state,failure_code,provider_thread_id FROM moon_ai_outbox WHERE installation_id IS NOT NULL ORDER BY created_at DESC LIMIT 5")).rows));
 }finally{await db.end();}
 const url=new URL(process.env.REDIS_URL);const queue=new Queue('moon-ai',{connection:{host:url.hostname,port:Number(url.port||6379),password:url.password||undefined}});
 try{
  console.log('MoonAI job counts:',JSON.stringify(await queue.getJobCounts('waiting','active','completed','failed','delayed')));
  const failed=await queue.getFailed(0,2);
  console.log('Worker failure kinds:',JSON.stringify(failed.map(j=>({name:j.name,errorKind:(j.failedReason||'').replace(/[^a-zA-Z_\s]/g,'').slice(0,120)}))));
 }finally{await queue.close();}
})().catch(e=>{console.error('Integration inspection failed:',e.code||e.name);process.exitCode=1;});
