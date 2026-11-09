// Explicit owner request: one checkout-help message, no invoice or charge.
const requestKey='owner-checkout-help-20261109';
function receipt(row){return row?{state:row.state,failureCode:row.failure_code??null,
 startedAt:row.started_at,finishedAt:row.finished_at,
 delivery:row.payload?.messengerDelivery?.delivery??null,
 providerAccepted:row.state==='sent'&&!!row.provider_thread_id}: {state:'not_found'};}
async function checkoutHelpOnce(db,phoneHash,mode='queue'){
 if(!/^[a-f0-9]{64}$/.test(phoneHash)||!['queue','status'].includes(mode))throw Error('invalid_input');
 return db.transaction(async tx=>{
  const accounts=(await tx.query(`SELECT id,status,deleted_at,settings FROM app_users WHERE role='customer'
   AND encode(sha256(convert_to(regexp_replace(phone,'[^0-9]','','g'),'UTF8')),'hex')=$1`,[phoneHash])).rows;
  if(accounts.length!==1)throw Error('account_not_unique');
  const account=accounts[0];
  const row=(await tx.query(`SELECT * FROM moon_ai_outbox WHERE customer_id=$1 AND kind='abandoned_checkout'
   ORDER BY created_at DESC,id DESC LIMIT 1${mode==='queue'?' FOR UPDATE':''}`,[account.id])).rows[0];
  if(mode==='status')return receipt(row);
  if(account.deleted_at||['blocked','rejected'].includes(account.status)||account.settings?.whatsappOptOut===true)
   return {state:'not_queued',reason:'contact_not_allowed'};
  const paid=(await tx.query("SELECT 1 FROM payments WHERE customer_id=$1 AND (status='paid' OR paid_at IS NOT NULL) LIMIT 1",[account.id])).rows.length>0;
  if(paid)return {state:'not_queued',reason:'purchase_paid'};
  if(!row)return {state:'not_queued',reason:'reminder_not_found'};
  if(row.payload?.ownerRequestedReminder===requestKey||['sent','processing','uncertain','pending'].includes(row.state))return receipt(row);
  if(row.state!=='cancelled'||row.started_at||row.provider_thread_id||row.payload?.messengerDelivery)
   return {state:'not_queued',reason:'previous_delivery_requires_review'};
  const payment=(await tx.query('SELECT * FROM payments WHERE id=$1 AND customer_id=$2 FOR UPDATE',[row.payment_id,account.id])).rows[0];
  if(!payment||payment.status==='paid'||payment.paid_at||payment.status==='refunded')return {state:'not_queued',reason:'payment_closed'};
  await tx.query("INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('whatsapp.checkout_help.owner_requested','moon_ai_outbox',$1,$2::jsonb)",
   [row.id,JSON.stringify({requestKey,previous:{state:row.state,runAfter:row.run_after,finishedAt:row.finished_at,failureCode:row.failure_code??null}})]);
  const updated=(await tx.query(`UPDATE moon_ai_outbox SET state='pending',run_after=NOW(),finished_at=NULL,failure_code=NULL,
   payload=payload||jsonb_build_object('ownerRequestedReminder',$2::text) WHERE id=$1 RETURNING *`,[row.id,requestKey])).rows[0];
  return {...receipt(updated),queued:true};
 });
}
module.exports={checkoutHelpOnce};
if(!module.parent){
 const crypto=require('node:crypto');const {Database}=require('./dist/infrastructure/db/Database');
 const db=new Database(process.env.DATABASE_URL);
 (async()=>{
  const b64=process.env.REPORT_PUBLIC_KEY_B64||'';
  if(!/^[A-Za-z0-9+/=]{100,12000}$/.test(b64))throw Error('invalid_public_key');
  const publicKey=crypto.createPublicKey({key:Buffer.from(b64,'base64'),format:'der',type:'spki'});
  let result=await checkoutHelpOnce(db,process.env.TARGET_PHONE_SHA256||'',process.env.REMINDER_MODE||'queue');
  if(result.queued){for(let i=0;i<20&&['pending','processing'].includes(result.state);i++){
   await new Promise(resolve=>setTimeout(resolve,2000));
   result=await checkoutHelpOnce(db,process.env.TARGET_PHONE_SHA256||'','status');
  }}
  const key=crypto.randomBytes(32),iv=crypto.randomBytes(12);const cipher=crypto.createCipheriv('aes-256-gcm',key,iv);
  const data=Buffer.concat([cipher.update(JSON.stringify(result)),cipher.final()]);
  process.stdout.write(JSON.stringify({version:1,key:crypto.publicEncrypt({key:publicKey,padding:crypto.constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},key).toString('base64'),iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),data:data.toString('base64')}));
 })().catch(()=>{console.error('Checkout-help operation failed; no customer details logged.');process.exitCode=1;}).finally(()=>db.close());
}
