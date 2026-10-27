// One explicitly authorized test. Durable attempt record prevents duplicate sends.
const {Client}=require('pg');const {createHash,randomUUID}=require('node:crypto');
const {sendMessengerFollowup,signupWelcomeTemplate,messengerPhone}=require('./dist/modules/moonMessenger');
(async()=>{
 const phone=messengerPhone(process.env.WELCOME_PHONE);
 if(!phone)throw Error('Invalid authorized recipient');
 const key=createHash('sha256').update(signupWelcomeTemplate+':'+phone).digest('hex');
 const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();
 try{
  await db.query('SELECT pg_advisory_lock(hashtextextended($1,0))',[key]);
  const previous=(await db.query("SELECT payload FROM audit_logs WHERE action='whatsapp.welcome.test' AND payload->>'key'=$1 ORDER BY created_at DESC LIMIT 1",[key])).rows[0]?.payload;
  if(previous && previous.state!=='blocked'){console.log(JSON.stringify({duplicatePrevented:true,state:previous.state,delivery:previous.delivery}));return;}
  const opted=(await db.query("SELECT 1 FROM app_users WHERE phone=$1 AND settings->>'whatsappOptOut'='true' LIMIT 1",['+'+phone])).rows.length;
  if(opted)throw Error('Recipient opted out');
  const id=randomUUID();const payload={key,state:'attempted',operationId:process.env.WELCOME_OPERATION_ID,template:signupWelcomeTemplate};
  await db.query("INSERT INTO audit_logs(id,action,entity_type,payload) VALUES($1,'whatsapp.welcome.test','messenger_test',$2::jsonb)",[id,JSON.stringify(payload)]);
  try{
   const delivery=await sendMessengerFollowup({id,kind:'inactive_signup',text:'',phone:'+'+phone});
   await db.query("UPDATE audit_logs SET payload=payload || $2::jsonb WHERE id=$1",[id,JSON.stringify({state:'submitted',delivery})]);
   console.log(JSON.stringify({state:'submitted',delivery}));
  }catch(e){
   // Only known pre-send lookup/template failures permit another attempt.
   const blocked=['whatsapp_template_not_approved','whatsapp_template_not_configured','whatsapp_not_configured','whatsapp_conversation_paused','whatsapp_lookup_unavailable','whatsapp_lookup_invalid'].includes(e.failureCode);
   const state=blocked?'blocked':'uncertain';
   await db.query("UPDATE audit_logs SET payload=payload || $2::jsonb WHERE id=$1",[id,JSON.stringify({state,failureCode:e.failureCode||e.name})]);
   console.log(JSON.stringify({state,failureCode:e.failureCode||e.name}));process.exitCode=2;
  }
 }finally{await db.end();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
