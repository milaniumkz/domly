// Operational diagnostics: no credentials, phone numbers, text or payloads.
const {Pool}=require('pg');
const {Queue}=require('bullmq');
(async()=>{
 console.log('OTP configuration:',JSON.stringify({showCode:process.env.OTP_SHOW_CODE==='true'||process.env.OTP_SHOW_CODE==='1',legacyWindowActive:Date.parse(process.env.OTP_FAILURE_FALLBACK_UNTIL||'')>Date.now(),provider:process.env.OTP_PROVIDER||'wapi',deliveryConfigured:process.env.OTP_PROVIDER==='greenapi'?!!process.env.GREEN_API_INSTANCE_ID&&!!process.env.GREEN_API_TOKEN:!!process.env.WAPI_TOKEN&&!!process.env.WAPI_PROFILE_ID}));
 console.log('MoonAI configuration:',JSON.stringify({enabled:process.env.MOON_AI_ENABLED==='true',channelUrlConfigured:!!process.env.MOON_AI_CHANNEL_URL,channelKeyConfigured:!!process.env.MOON_AI_CHANNEL_API_KEY,webhookConfigured:!!process.env.MOON_AI_WEBHOOK_TOKEN}));
 const apiBase=`https://core.mooonai.com/api/v1/organizations/${process.env.MOON_AI_ORGANIZATION_ID||4649}/agents/${process.env.MOON_AI_AGENT_ID||6875}`;
 const apiKey=process.env.MOON_AI_REST_API_KEY||process.env.MOON_AI_CHANNEL_API_KEY;
 async function read(path){const r=await fetch(apiBase+path,{headers:{Authorization:'Bearer '+apiKey},signal:AbortSignal.timeout(15000)});const data=await r.json().catch(()=>null);console.log('MoonAI read-only API:',JSON.stringify({path,status:r.status,keys:data&&!Array.isArray(data)?Object.keys(data).slice(0,15):[]}));return r.ok?data:null;}
 const raw=await read('/channels');const channels=Array.isArray(raw)?raw:(raw?.results||raw?.channels||raw?.items||[]);
 for(const c of channels){console.log('MoonAI channel:',JSON.stringify({id:c.id,type:c.channel_type||c.type||c.messenger,status:c.status,is_connected:c.is_connected,enabled:c.enabled,keys:Object.keys(c).slice(0,20)}));
  if(/whatsapp|waba/i.test(String(c.channel_type||c.type||c.messenger))){const t=await read('/channels/'+c.id+'/whatsapp-templates?status=APPROVED');for(const x of (t?.templates||t?.results||[]))console.log('MoonAI approved template:',JSON.stringify({channelId:c.id,id:x.id,name:x.name,status:x.status,language:x.language,body:JSON.stringify(x.components?.body||x.components?.find?.(v=>v.type==='BODY')||{}).slice(0,900)}));}
 }
 const threads=await read('/threads?limit=1');console.log('MoonAI thread schema:',JSON.stringify({count:threads?.count,keys:threads?.results?.[0]?Object.keys(threads.results[0]):[]}));
 if(process.env.MOON_AI_WABA_CHANNEL_ID){const templates=await read('/channels/'+process.env.MOON_AI_WABA_CHANNEL_ID+'/whatsapp-templates?status=APPROVED');
  console.log('Configured WABA template:',JSON.stringify({channelId:process.env.MOON_AI_WABA_CHANNEL_ID,templateId:process.env.MOON_AI_WABA_TEMPLATE_ID,approved:(templates?.templates||[]).some(t=>String(t.id)===process.env.MOON_AI_WABA_TEMPLATE_ID&&t.status==='APPROVED')}));}
 const db=new Pool({connectionString:process.env.DATABASE_URL});
 try{
  if(/^[a-f0-9]{64}$/.test(process.env.OTP_PHONE_SHA256||'')) console.log('Requested OTP account:',JSON.stringify((await db.query("SELECT role,status FROM app_users WHERE encode(sha256(convert_to(phone,'UTF8')),'hex')=$1",[process.env.OTP_PHONE_SHA256])).rows));
  console.log('OTP account eligibility:',JSON.stringify((await db.query("SELECT role,status,COUNT(*)::int AS count FROM app_users GROUP BY role,status ORDER BY role,status")).rows));
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
