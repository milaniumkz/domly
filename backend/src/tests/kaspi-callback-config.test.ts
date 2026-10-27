import test from 'node:test';
import assert from 'node:assert/strict';
const {configureKaspiCallback}=require('../../../scripts/server/configure_kaspi_callback.cjs');
function fixture() {
 const fn:any={name:'set_info',is_active:true,parameters:['phone','amount','status','dateTime'].map((name,id)=>({id,name,parameter_type:'text',required:true}))};
 const integration:any={id:9025,integration_type:'api',data:{url:'https://domly.kz/api/v1/payments/moon-ai/kaspi-status',method:'POST',headers:{'X-MoonAI-Token':{value:'fixture-secret',value_from:null}},json_params:Object.fromEntries(fn.parameters.map((p:any)=>[p.name,{value:null,value_from:p.name}]))}};
 const writes:string[]=[],backups:any[]=[];
 const send=async(url:string,init:any)=>{
  const path=new URL(url).pathname.split('/functions/8517')[1];
  if(init.method!=='GET'){
   assert.equal(backups.length>0,true,'backup before any provider mutation');writes.push(path);
   if(path==='/parameters/')fn.parameters.push({id:99,...JSON.parse(init.body)});
   else if(path==='/integrations/9025')Object.assign(integration,JSON.parse(init.body));
   else throw Error('Unexpected mutation');
  }
  return new Response(JSON.stringify(path==='/integrations/9025'?integration:path==='/parameters/'?fn.parameters.at(-1):fn),{status:200});
 };
 return {fn,integration,writes,backups,options:{env:{MOON_AI_ORGANIZATION_ID:'test',MOON_AI_AGENT_ID:'test',MOON_AI_REST_API_KEY:'fixture'},send,saveBackup:async(value:any)=>backups.push(structuredClone(value))}};
}
test('callback configuration preserves auth and old fields, verifies and is idempotent',async()=>{
 const f=fixture(),before=structuredClone(f.integration);
 assert.equal((await configureKaspiCallback(f.options)).configured,true);
 assert.deepEqual(f.integration.data.headers,before.data.headers);
 for(const key of Object.keys(before.data.json_params))assert.deepEqual(f.integration.data.json_params[key],before.data.json_params[key]);
 assert.deepEqual(f.integration.data.json_params.paymentId,{value:null,value_from:'paymentId'});
 assert.equal(f.fn.parameters.at(-1).required,false);
 assert.deepEqual(f.backups[0].integration,before);
 assert.equal((await configureKaspiCallback(f.options)).alreadyConfigured,true);assert.equal(f.writes.length,2);
});
test('callback configuration refuses unknown endpoint or field bindings',async()=>{
 for(const change of [(f:any)=>f.integration.data.url='https://example.com/other',(f:any)=>f.integration.data.json_params.phone.value_from='other']){
  const f=fixture();change(f);await assert.rejects(configureKaspiCallback(f.options));assert.equal(f.writes.length,0);
 }
});
test('backup failure prevents all configuration mutations',async()=>{
 const f=fixture();await assert.rejects(configureKaspiCallback({...f.options,saveBackup:async()=>{throw Error('backup failed')}}));assert.equal(f.writes.length,0);
});
test('conflicting payment ID configuration is never overwritten',async()=>{
 const f=fixture();f.fn.parameters.push({name:'paymentId',parameter_type:'number',required:true});await assert.rejects(configureKaspiCallback(f.options));assert.equal(f.writes.length,0);
});
