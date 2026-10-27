// Create the owner's exact welcome template; never send a customer message.
const name='domly_welcome_alena_20261027';
const text='Привет! 👋 Я Алена из поддержки Domly. Вижу, вы только что установили приложение. Разобрались, как оно работает, или подсказать, какой вариант уборки лучше выбрать под вашу квартиру, чтобы сэкономить?';
(async()=>{
 const e=process.env;
 const url=`https://core.mooonai.com/api/v1/organizations/${e.MOON_AI_ORGANIZATION_ID}/agents/${e.MOON_AI_AGENT_ID}/channels/${e.MOON_AI_WABA_CHANNEL_ID}/whatsapp-templates`;
 async function request(method,body){const r=await fetch(url,{method,headers:{Authorization:`Bearer ${e.MOON_AI_REST_API_KEY}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});const data=await r.json();if(!r.ok)throw Error('Template operation HTTP '+r.status+': '+JSON.stringify(data));return data;}
 const list=await request('GET');let template=(list.templates||[]).find(t=>t.name===name);
 if(template && template.components?.body?.text!==text)throw Error('Existing template text differs');
 if(!template)template=await request('POST',{name,language:'ru',category:'MARKETING',components:{body:{text}}});
 console.log(JSON.stringify(template));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
