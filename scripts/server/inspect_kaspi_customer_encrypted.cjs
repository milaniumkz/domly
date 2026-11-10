// Read-only, owner-authorized invoice investigation. No invoice or message POSTs.
const crypto=require('node:crypto');const {Pool}=require('pg');
(async()=>{
 const recipient=process.env.REPORT_PUBLIC_KEY_B64||'';
 const target=Buffer.from(process.env.TARGET_NAME_B64||'','base64').toString('utf8').trim();
 if(!target||target.length>80||!/^[A-Za-z0-9+/=]{100,12000}$/.test(recipient))throw Error('invalid_input');
 const publicKey=crypto.createPublicKey({key:Buffer.from(recipient,'base64'),format:'der',type:'spki'});
 const db=new Pool({connectionString:process.env.DATABASE_URL});let client;
 const report={version:1,readOnly:true,matches:[],payments:[],invoiceJobs:[],events:[],callbacks:[],audit:[],upstream:[]};
 try{
  client=await db.connect();await client.query('BEGIN READ ONLY');
  const variants=target.toLowerCase()==='мадина'?['%мадина%','%мәдина%','%madina%']:['%'+target.replace(/[%_\\]/g,'')+'%'];
  const accounts=(await client.query(`SELECT id,full_name,RIGHT(regexp_replace(phone,'[^0-9]','','g'),4) AS phone_suffix,created_at
   FROM app_users WHERE role='customer' AND full_name ILIKE ANY($1::text[]) ORDER BY created_at DESC LIMIT 6`,[variants])).rows;
  report.matches=accounts.map(({id,...safe})=>safe);
  if(accounts.length===1){
   const id=accounts[0].id;
   report.payments=(await client.query(`SELECT p.id,p.provider,p.status,p.amount,p.bonus_amount,p.created_at,p.updated_at,p.invoice_requested_at,p.paid_at,p.approval_source,
    (NULLIF(p.invoice_phone,'') IS NOT NULL) AS invoice_phone_present,(p.external_id IS NOT NULL) AS external_reference_present,
    pkg.name_ru AS package_name,cp.status AS package_status,
    p.payload->>'kind' AS payment_kind,p.payload->'moonAi'->>'status' AS callback_status
    FROM payments p LEFT JOIN customer_packages cp ON cp.id=p.customer_package_id
    LEFT JOIN catalog_packages pkg ON pkg.id=cp.package_id WHERE p.customer_id=$1 ORDER BY p.created_at DESC LIMIT 20`,[id])).rows;
   const ids=report.payments.map(p=>p.id);
   report.invoiceJobs=(await client.query(`SELECT id,payment_id,kind,state,created_at,run_after,started_at,finished_at,failure_code,provider_thread_id
    FROM moon_ai_outbox WHERE customer_id=$1 AND kind='invoice' ORDER BY created_at DESC LIMIT 30`,[id])).rows;
   if(ids.length){
    report.events=(await client.query(`SELECT payment_id,event_type,status,created_at,payload->>'code' AS error_code,payload->>'message' AS message
     FROM payment_events WHERE payment_id=ANY($1::uuid[]) ORDER BY created_at DESC LIMIT 50`,[ids])).rows;
    report.callbacks=(await client.query(`SELECT payment_id,status,resolution,event_time,received_at
     FROM moon_ai_payment_callbacks WHERE payment_id=ANY($1::uuid[]) OR candidate_ids && $1::uuid[] ORDER BY received_at DESC LIMIT 50`,[ids])).rows;
    report.audit=(await client.query(`SELECT action,entity_id,created_at,payload->>'source' AS source
     FROM audit_logs WHERE entity_type='payment' AND entity_id=ANY($1::text[]) ORDER BY created_at DESC LIMIT 50`,[ids])).rows;
   }
  }
  await client.query('ROLLBACK');
 }finally{if(client)client.release();await db.end();}
 const apiKey=process.env.MOON_AI_REST_API_KEY;
 const org=process.env.MOON_AI_ORGANIZATION_ID||'4649',agent=process.env.MOON_AI_AGENT_ID||'6875';
 if(apiKey&&/^\d+$/.test(org||'')&&/^\d+$/.test(agent||'')){
  const base=`https://core.mooonai.com/api/v1/organizations/${org}/agents/${agent}`;
  for(const job of report.invoiceJobs.filter(j=>j.provider_thread_id).slice(0,3)){
   const item={paymentId:job.payment_id,threadId:job.provider_thread_id};
   try{
    const response=await fetch(base+'/threads/'+encodeURIComponent(job.provider_thread_id)+'/messages?limit=50',
     {method:'GET',headers:{Authorization:'Bearer '+apiKey},signal:AbortSignal.timeout(30000)});
    item.httpStatus=response.status;const raw=await response.json().catch(()=>null);
    const messages=Array.isArray(raw)?raw:raw?.results||raw?.messages||raw?.items||[];
    item.responseKeys=raw&&!Array.isArray(raw)?Object.keys(raw):[];
    item.messages=messages.slice(0,50).map(m=>({id:m.id,from:m.from_type||m.sender_type,type:m.message_type||m.type,at:m.created||m.at||m.created_at,
      data:JSON.stringify(m.data??m.text??m.content??m.message??'').slice(0,6000)}));
   }catch(e){item.errorKind=e.name;}
   report.upstream.push(item);
  }
 }
 const key=crypto.randomBytes(32),iv=crypto.randomBytes(12),cipher=crypto.createCipheriv('aes-256-gcm',key,iv);
 const data=Buffer.concat([cipher.update(JSON.stringify(report)),cipher.final()]);
 process.stdout.write(JSON.stringify({version:1,key:crypto.publicEncrypt({key:publicKey,padding:crypto.constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},key).toString('base64'),iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),data:data.toString('base64')}));
})().catch(()=>{console.error('Read-only Kaspi invoice audit failed; no customer details logged.');process.exitCode=1;});
