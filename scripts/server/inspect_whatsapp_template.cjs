// Refresh and inspect template moderation status. No conversations or messages accessed.
(async()=>{
 const e=process.env;
 const url=`https://core.mooonai.com/api/v1/organizations/${e.MOON_AI_ORGANIZATION_ID}/agents/${e.MOON_AI_AGENT_ID}/channels/${e.MOON_AI_WABA_CHANNEL_ID}/whatsapp-templates?status=APPROVED`;
 const refresh=await fetch(url.split('?')[0]+'/refresh-statuses',{method:'POST',headers:{Authorization:`Bearer ${e.MOON_AI_REST_API_KEY}`},signal:AbortSignal.timeout(30000)});
 if(!refresh.ok)throw Error('Template status refresh HTTP '+refresh.status);
 const r=await fetch(url.replace('?status=APPROVED',''),{headers:{Authorization:`Bearer ${e.MOON_AI_REST_API_KEY}`},signal:AbortSignal.timeout(30000)});
 if(!r.ok)throw Error('Template lookup HTTP '+r.status);
 const data=await r.json();const t=(data.templates||[]).find(x=>String(x.id)===e.MOON_AI_WABA_TEMPLATE_ID);
 if(!t)throw Error('Configured approved template missing');
 for(const item of (data.templates||[]).filter(x=>String(x.id)===e.MOON_AI_WABA_TEMPLATE_ID || x.name==='domly_welcome_alena_formal_20261027'))
  console.log(JSON.stringify({id:item.id,name:item.name,status:item.status,components:item.components}));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
