'use strict';
// Explicitly scoped, read-only payment verification. No credentials, phone or card data in logs.
const crypto=require('node:crypto');
function encrypt(report,pub){
 const key=crypto.randomBytes(32),iv=crypto.randomBytes(12),cipher=crypto.createCipheriv('aes-256-gcm',key,iv),payload=Buffer.concat([cipher.update(JSON.stringify(report)),cipher.final()]);
 return {version:1,key:crypto.publicEncrypt({key:pub,oaepHash:'sha256',padding:crypto.constants.RSA_PKCS1_OAEP_PADDING},key).toString('base64'),iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),payload:payload.toString('base64')};
}
(async()=>{
 const suffix=process.env.AUDIT_PHONE_SUFFIX||'',encoded=process.env.AUDIT_REPORT_KEY||'';
 if(!/^\d{4}$/.test(suffix))throw Error('Four phone digits required');
 const pub=crypto.createPublicKey({key:Buffer.from(encoded,'base64'),format:'der',type:'spki'});
 const {Database}=require('/app/dist/infrastructure/db/Database.js'),db=new Database(process.env.DATABASE_URL);
 try{
  const report=await db.transaction(async tx=>{
   await tx.query('SET TRANSACTION READ ONLY');
   const users=(await tx.query("SELECT id FROM app_users WHERE role='customer' AND deleted_at IS NULL AND status<>'blocked' AND right(regexp_replace(phone,'[^0-9]','','g'),4)=$1",[suffix])).rows;
   if(users.length!==1)return {matchedCustomers:users.length,stopped:true};
   const payments=(await tx.query(`SELECT id,numeric_id,amount,bonus_amount,status,created_at,paid_at,applied_at,approval_source,order_id,customer_package_id,external_id,
     payload->>'bccBankStatus' AS bank_status,payload->>'bccTestMode' AS test_mode,
     payload->'bccBankResult'->>'ACTION' AS bank_action,payload->'bccBankResult'->>'RC' AS bank_rc,
     payload->'bccBankResult'->>'AMOUNT' AS bank_amount,payload->'bccBankResult'->>'CURRENCY' AS bank_currency
     FROM payments WHERE customer_id=$1 AND provider='bcc' AND created_at>NOW()-INTERVAL '2 hours' ORDER BY created_at DESC LIMIT 6`,[users[0].id])).rows;
   for(const payment of payments){
    payment.callbackEvents=(await tx.query("SELECT event_type,status,created_at FROM payment_events WHERE payment_id=$1 AND provider='bcc' AND event_type='verified_status' ORDER BY created_at DESC LIMIT 5",[payment.id])).rows;
    if(payment.order_id){
     payment.order=(await tx.query('SELECT status,payable_amount FROM service_orders WHERE id=$1 AND customer_id=$2',[payment.order_id,users[0].id])).rows[0];
     payment.addons=(await tx.query(`SELECT a.title_ru,oa.quantity,oa.price,oa.payment_status,oa.paid_separately FROM order_addons oa JOIN catalog_addons a ON a.id=oa.addon_id WHERE oa.order_id=$1`,[payment.order_id])).rows;
    }
    if(payment.customer_package_id)payment.wallet=(await tx.query('SELECT status,total_cleanings,available_cleanings FROM customer_packages WHERE id=$1 AND customer_id=$2',[payment.customer_package_id,users[0].id])).rows[0];
   }
   return {matchedCustomers:1,checkedAt:new Date().toISOString(),payments};
  });
  console.log('BCC_PAYMENT_AUDIT='+Buffer.from(JSON.stringify(encrypt(report,pub))).toString('base64'));
  console.log('Read-only BCC payment audit completed.');
 }finally{await db.close();}
})().catch(error=>{console.error('Payment audit stopped. Code:',error.code||'BCC_AUDIT_STOPPED');process.exitCode=1;});
