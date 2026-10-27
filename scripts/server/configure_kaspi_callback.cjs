// Configure the existing callback only. Never invokes create_order or changes payments.
const {isDeepStrictEqual}=require('node:util');
async function configureKaspiCallback({env=process.env,send=fetch,saveBackup}) {
 const base=`https://core.mooonai.com/api/v1/organizations/${env.MOON_AI_ORGANIZATION_ID}/agents/${env.MOON_AI_AGENT_ID}/functions/8517`;
 const request=async(path,method='GET',body)=>{
  const r=await send(base+path,{method,headers:{Authorization:`Bearer ${env.MOON_AI_REST_API_KEY}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});
  if(!r.ok)throw Error(`Callback configuration ${method} HTTP ${r.status}`);
  return r.status===204?null:r.json();
 };
 const fn=await request(''),integration=await request('/integrations/9025');
 if(fn.name!=='set_info'||!fn.is_active||integration.integration_type!=='api'||integration.data.method!=='POST')throw Error('Unexpected callback configuration');
 const url=new URL(integration.data.url);
 if(url.origin!=='https://domly.kz'||url.pathname!=='/api/v1/payments/moon-ai/kaspi-status'||url.search)throw Error('Unexpected callback destination');
 const fields=integration.data.json_params;
 for(const name of ['phone','amount','status','dateTime'])if(fields?.[name]?.value_from!==name||fields[name].value!==null)throw Error('Unexpected existing callback field mapping');
 let param=fn.parameters.find(p=>p.name==='paymentId');
 if(param&&(param.parameter_type!=='text'||param.required!==false))throw Error('Conflicting existing paymentId parameter');
 const binding={value:null,value_from:'paymentId'};
 if(fields.paymentId&&!isDeepStrictEqual(fields.paymentId,binding))throw Error('Conflicting paymentId mapping');
 await saveBackup({function:fn,integration});
 if(!param)param=await request('/parameters/','POST',{name:'paymentId',parameter_type:'text',required:false,description:'UUID платежа DOMLY из служебного запроса paymentId=... . Передавайте неизменным при каждом статусе только этого счёта. Не угадывайте и не используйте ID другого счёта. Для старого запроса без ID оставьте пустым (null).'});
 const expected={integration_type:integration.integration_type,data:{...integration.data,json_params:{...fields,paymentId:binding}}};
 if(!fields.paymentId)await request('/integrations/9025','PUT',expected);
 const after=await request('/integrations/9025'),afterFn=await request('');
 if(!isDeepStrictEqual(after.data,expected.data)||after.integration_type!==expected.integration_type)throw Error('Callback mapping verification failed');
 const actual=afterFn.parameters.find(p=>p.name==='paymentId');
 if(!actual||actual.parameter_type!=='text'||actual.required!==false)throw Error('Callback parameter verification failed');
 const beforeOthers=fn.parameters.filter(p=>p.name!=='paymentId'),afterOthers=afterFn.parameters.filter(p=>p.name!=='paymentId');
 if(!isDeepStrictEqual(beforeOthers,afterOthers))throw Error('Existing parameters changed unexpectedly');
 return {configured:true,functionId:8517,integrationId:9025,parameterId:actual.id,alreadyConfigured:Boolean(fields.paymentId),paymentMutations:0};
}
module.exports={configureKaspiCallback};
if(require.main===module)configureKaspiCallback({saveBackup:async backup=>{
 const fs=require('node:fs'),dir='/tmp/domly-kaspi-config-backup';fs.mkdirSync(dir,{recursive:true,mode:0o700});
 const file=dir+'/'+process.env.GITHUB_RUN_ID+'.json';fs.writeFileSync(file,JSON.stringify(backup),{mode:0o600,flag:'wx'});
 console.log(JSON.stringify({backupFile:file}));
}}).then(r=>console.log(JSON.stringify(r))).catch(e=>{console.error(e.message);process.exitCode=1;});
