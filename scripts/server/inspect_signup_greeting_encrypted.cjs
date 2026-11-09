// Read-only support evidence. Never send a greeting or expose identifiers/text.
const crypto=require('node:crypto');
const {Pool}=require('pg');
(async()=>{
 const hash=process.env.TARGET_PHONE_SHA256||'';
 const recipient=process.env.REPORT_PUBLIC_KEY_B64||'';
 if(!/^[a-f0-9]{64}$/.test(hash)||!/^[A-Za-z0-9+/=]{100,12000}$/.test(recipient))throw Error('invalid_input');
 const publicKey=crypto.createPublicKey({key:Buffer.from(recipient,'base64'),format:'der',type:'spki'});
 const db=new Pool({connectionString:process.env.DATABASE_URL});
 let client;
 try{
  client=await db.connect();await client.query('BEGIN READ ONLY');
  const accounts=(await client.query(`SELECT id,created_at AS registered_at,is_phone_verified,
    status,(deleted_at IS NOT NULL) AS deleted,COALESCE((settings->>'whatsappOptOut')::boolean,FALSE) AS whatsapp_opt_out
    FROM app_users WHERE role='customer'
    AND encode(sha256(convert_to(regexp_replace(phone,'[^0-9]','','g'),'UTF8')),'hex')=$1`,[hash])).rows;
  if(accounts.length>1)throw Error('ambiguous_account');
  const report={version:1,readOnly:true,accountFound:accounts.length===1,accounts:[]};
  for(const account of accounts){
   const entries=(await client.query(`SELECT kind,state,created_at,run_after,started_at,finished_at,failure_code,
      (provider_thread_id IS NOT NULL) AS provider_thread_recorded,
      payload->>'deliveryChannel' AS delivery_channel,
      payload->'messengerDelivery'->>'delivery' AS delivery_result
      FROM moon_ai_outbox WHERE customer_id=$1 AND kind IN ('inactive_signup','abandoned_checkout','message')
      ORDER BY created_at LIMIT 100`,[account.id])).rows;
   const activity=(await client.query(`SELECT
     (SELECT MIN(created_at) FROM payments WHERE customer_id=$1) AS first_checkout_at,
     (SELECT MIN(created_at) FROM moon_ai_outbox WHERE customer_id=$1 AND kind='message') AS first_assistant_message_at`,[account.id])).rows[0];
   const {id,...safeAccount}=account;
   report.accounts.push({...safeAccount,entries,activity});
  }
  await client.query('ROLLBACK');
  const key=crypto.randomBytes(32),iv=crypto.randomBytes(12);
  const cipher=crypto.createCipheriv('aes-256-gcm',key,iv);
  const data=Buffer.concat([cipher.update(JSON.stringify(report),'utf8'),cipher.final()]);
  const sealed={version:1,algorithm:'RSA-OAEP-SHA256+AES-256-GCM',
    key:crypto.publicEncrypt({key:publicKey,padding:crypto.constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},key).toString('base64'),
    iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),data:data.toString('base64')};
  process.stdout.write(JSON.stringify(sealed));
 }finally{if(client)client.release();await db.end();}
})().catch(()=>{console.error('Read-only greeting audit failed; no customer details logged.');process.exitCode=1;});
