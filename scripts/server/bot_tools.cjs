// Runs inside the API container; credentials stay in its environment.
const base=`https://core.mooonai.com/api/v1/organizations/${process.env.MOON_AI_ORGANIZATION_ID||4649}/agents/${process.env.MOON_AI_AGENT_ID||6875}`;
const key=process.env.MOON_AI_REST_API_KEY;
function shape(v,depth=0){if(depth>7)return typeof v;if(Array.isArray(v))return v.slice(0,1).map(x=>shape(x,depth+1));if(v&&typeof v==='object')return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,/token|secret|password|authorization|api.key/i.test(k)?'<redacted>':shape(x,depth+1)]));return typeof v;}
(async()=>{
 if(!key)throw Error('rest_key_missing');
 for(const path of ['/functions/','/functions/8759','/functions/8759/integrations/','/prompts/']) {
  const r=await fetch(base+path,{headers:{Authorization:'Bearer '+key},signal:AbortSignal.timeout(45000)});
  const d=await r.json().catch(()=>null);
  console.log(JSON.stringify({path,status:r.status,shape:shape(d)}));
  function refs(v,p=''){if(!v||typeof v!=='object')return;for(const [k,x] of Object.entries(v)){if(k==='value_from')console.log(JSON.stringify({mapping:p,valueFrom:x}));else if(!/headers|token|secret|password/i.test(k))refs(x,p+'.'+k);}}
  if(path.includes('integrations'))refs(d);
  if(path.includes('integrations'))for(const i of d?.integrations??d?.agent_function_integrations??[]){const x=i.data??{};console.log(JSON.stringify({id:i.id,type:i.integration_type,method:x.method,path:x.url?new URL(x.url).pathname:null,path_params:x.path_params,query_params:x.query_params,json_params:x.json_params}));}
  const list=Array.isArray(d)?d:d?.results??d?.functions??[];
  if(path==='/functions/')for(const f of list)console.log(JSON.stringify({id:f.id,name:f.name,type:f.type,kind:f.function_type,shape:shape(f)}));
 }
})().catch(e=>{console.error('Bot tools inspection failed:',e.code||e.name);process.exitCode=1;});
