// Read-only approved template inspection. No conversations or messages accessed.
(async()=>{
 const e=process.env;
 const url=`https://core.mooonai.com/api/v1/organizations/${e.MOON_AI_ORGANIZATION_ID}/agents/${e.MOON_AI_AGENT_ID}/channels/${e.MOON_AI_WABA_CHANNEL_ID}/whatsapp-templates?status=APPROVED`;
 const r=await fetch(url,{headers:{Authorization:`Bearer ${e.MOON_AI_REST_API_KEY}`},signal:AbortSignal.timeout(30000)});
 if(!r.ok)throw Error('Template lookup HTTP '+r.status);
 const data=await r.json();const t=(data.templates||[]).find(x=>String(x.id)===e.MOON_AI_WABA_TEMPLATE_ID);
 if(!t)throw Error('Configured approved template missing');
 console.log(JSON.stringify({id:t.id,name:t.name,status:t.status,body:t.body,components:t.components,text:t.text}));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
