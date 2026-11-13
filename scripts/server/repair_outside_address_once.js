let operationStage='initialize';
const {Database}=require('./dist/infrastructure/db/Database');
const {NotificationService}=require('./dist/modules/domainServices');
const {FcmService}=require('./dist/modules/integrations');
const {invalidateServiceAddress}=require('./dist/modules/serviceCoverage');
const {processMoonOutbox}=require('./dist/modules/moonAi');
(async()=>{
 const db=new Database(process.env.DATABASE_URL),notifications=new NotificationService(db,new FcmService());
 try{
  const enabled=(await db.query('SELECT domly_service_zones_enforced() AS enabled')).rows[0].enabled;
  if(!enabled)throw Error('Service-zone protection is not enabled');
  // Exact diagnosed record timestamp + locality; no customer PII is embedded in this script.
  operationStage='select_diagnosed_address';
  const matches=(await db.query(`SELECT a.id,a.user_id FROM customer_addresses a JOIN app_users u ON u.id=a.user_id
   WHERE a.created_at>='2026-11-12T10:13:02.607Z'::timestamptz AND a.created_at<'2026-11-12T10:13:02.608Z'::timestamptz AND domly_city_key(a.city)='астана'
    AND lower(a.street) ~ '(қос[шщ]|кос[шщ]|kossh|qossh|kosh)' AND u.deleted_at IS NULL`)).rows;
  if(matches.length!==1)throw Error('Target address missing or ambiguous; no changes made');
  const target=matches[0];
  let result;
  operationStage='repair_transaction';
  await db.atomic(async()=>{
   await db.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[target.user_id]);
   await db.query('SELECT id FROM quality_check_requests WHERE address_id=$1 ORDER BY id FOR UPDATE',[target.id]);
   const current=(await db.query('SELECT city,street FROM customer_addresses WHERE id=$1 AND user_id=$2 FOR UPDATE',[target.id,target.user_id])).rows[0];
   if(!current||!/(қос[шщ]|кос[шщ]|kossh|qossh|kosh)/i.test(current.street))throw Error('Address was already changed; no changes made');
   const before=(await db.query('SELECT id,status,total_cleanings,available_cleanings,period_end FROM customer_packages WHERE customer_id=$1 ORDER BY id',[target.user_id])).rows;
   const payments=(await db.query('SELECT id,status,amount,bonus_amount,paid_at FROM payments WHERE customer_id=$1 ORDER BY id',[target.user_id])).rows;
   result=await invalidateServiceAddress(db,notifications,target.id,target.user_id);
   const after=(await db.query('SELECT id,status,total_cleanings,available_cleanings,period_end FROM customer_packages WHERE customer_id=$1 ORDER BY id',[target.user_id])).rows;
   const afterPayments=(await db.query('SELECT id,status,amount,bonus_amount,paid_at FROM payments WHERE customer_id=$1 ORDER BY id',[target.user_id])).rows;
   if(JSON.stringify(before)!==JSON.stringify(after)||JSON.stringify(payments)!==JSON.stringify(afterPayments))throw Error('Unexpected financial change; rollback');
  });
  operationStage='deliver_requested_message';
  const outbox=(await db.query("SELECT id,state FROM moon_ai_outbox WHERE dedupe_key=$1",['replace-outside-address:'+target.id])).rows[0];
  if(outbox?.state==='pending')await processMoonOutbox(db,fetch,outbox.id);
  operationStage='confirm_delivery_state';
  let delivery;
  for(let i=0;i<20;i++){
   delivery=(await db.query(`SELECT a.service_status,a.area_reverification_required,a.verified_area IS NULL AS old_area_cleared,
    EXISTS(SELECT 1 FROM notifications n WHERE n.user_id=a.user_id AND n.dedupe_key=$2) AS app_notification_created,
    EXISTS(SELECT 1 FROM notifications n JOIN notification_deliveries d ON d.notification_id=n.id WHERE n.user_id=a.user_id AND n.dedupe_key=$2 AND d.delivered_at IS NOT NULL) AS app_delivery_processed,
    (SELECT state FROM moon_ai_outbox WHERE dedupe_key=$2) AS whatsapp_state,
    (SELECT failure_code FROM moon_ai_outbox WHERE dedupe_key=$2) AS whatsapp_failure
    FROM customer_addresses a WHERE a.id=$1`,[target.id,'replace-outside-address:'+target.id])).rows[0];
   if(delivery.app_delivery_processed&&['sent','failed','uncertain','cancelled'].includes(delivery.whatsapp_state))break;
   await new Promise(r=>setTimeout(r,1000));
  }
  console.log(JSON.stringify({zoneProtectionEnabled:enabled,accountRepair:delivery,packagesPreserved:true,paymentsPreserved:true,duplicateMessagesPrevented:true}));
 }finally{await db.close();}
})().catch(error=>{console.error(JSON.stringify({operationStage,code:/^[A-Z0-9_]{5,40}$/.test(error.code??'')?error.code:'operation_failed'}));process.exitCode=1;});
