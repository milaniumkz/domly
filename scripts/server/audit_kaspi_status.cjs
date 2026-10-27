// Read-only, aggregate diagnostics; no names, phones, tokens or payment payloads.
const {Client}=require('pg');
(async()=>{
 const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();
 try {
  await db.query('BEGIN READ ONLY');
  const queries={
   payments:`SELECT status,count(*)::int FROM payments WHERE provider='kaspi' GROUP BY status`,
   callbacks:`SELECT status,resolution,count(*)::int,max(received_at) AS latest FROM moon_ai_payment_callbacks GROUP BY status,resolution`,
   sample:`SELECT status,amount,created_at,updated_at,invoice_requested_at,customer_package_id IS NOT NULL AS package_purchase, payload ? 'moonAiReview' AS review, payload->'moonAi'->>'status' AS callback_status FROM payments WHERE provider='kaspi' AND amount=129600 ORDER BY created_at DESC LIMIT 20`,
   events:`SELECT event_type,status,count(*)::int FROM payment_events WHERE provider='kaspi' GROUP BY event_type,status`
  };
  for(const [name,sql]of Object.entries(queries))console.log(JSON.stringify({[name]:(await db.query(sql)).rows}));
  await db.query('ROLLBACK');
 }finally{await db.end();}
 const e=process.env;
 const base=`https://core.mooonai.com/api/v1/organizations/${e.MOON_AI_ORGANIZATION_ID}/agents/${e.MOON_AI_AGENT_ID}/functions/`;
 const r=await fetch(base,{headers:{Authorization:`Bearer ${e.MOON_AI_REST_API_KEY}`},signal:AbortSignal.timeout(30000)});
 if(!r.ok)throw Error('Function metadata HTTP '+r.status);
 const body=await r.json();const list=Array.isArray(body)?body:(body.functions||body.items||body.data||[]);
 console.log(JSON.stringify({functionResponseKeys:Object.keys(body),functions:Array.isArray(list)?list.map(x=>({id:x.id,name:x.name,type:x.type})):[]}));
 for(const id of [8759,8517]){
  const response=await fetch(base+id,{headers:{Authorization:`Bearer ${e.MOON_AI_REST_API_KEY}`},signal:AbortSignal.timeout(30000)});
  if(!response.ok)throw Error('Function detail HTTP '+response.status);
  const f=await response.json();
  console.log(JSON.stringify({functionId:id,keys:Object.keys(f),name:f.name,parameters:(f.parameters||[]).map(x=>({name:x.name,type:x.type,required:x.required})),reactionKeys:Object.keys(f.reaction||{})}));
  if(id===8517){
   const r=await fetch(base+id+'/integrations/',{headers:{Authorization:`Bearer ${e.MOON_AI_REST_API_KEY}`},signal:AbortSignal.timeout(30000)});
   if(!r.ok)throw Error('Integrations metadata HTTP '+r.status);
   const data=await r.json();
   const shape=(x,depth=0)=>depth>8?'...':Array.isArray(x)?x.map(v=>shape(v,depth+1)):x&&typeof x==='object'?Object.fromEntries(Object.entries(x).map(([k,v])=>[k,/^(id|type|integration_type|method|name)$/.test(k)?v:shape(v,depth+1)])):typeof x;
   console.log(JSON.stringify({integrationShape:shape(data)}));
  }

 }


})().catch(e=>{console.error(e.message);process.exitCode=1;});
