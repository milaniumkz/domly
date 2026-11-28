// Owner-authorized temporary promotion and one personal in-app/push announcement per existing user.
// No names, phones, tokens or financial records are printed.
const {Database}=require('/app/dist/infrastructure/db/Database');
const {NotificationService}=require('/app/dist/modules/domainServices');
const {FcmService}=require('/app/dist/modules/integrations');
const {setExpiryPromotion,readExpiryPromotion,announceExpiryPromotion}=require('/app/dist/modules/packageExpiryPromotion');
(async()=>{
 if(!process.env.EXPECTED_RELEASE||process.env.EXPECTED_RELEASE!==process.env.APP_RELEASE)throw new Error('deployed_release_mismatch');
 const action=process.env.EXPIRY_PROMOTION_ACTION;
 if(!['start','stop'].includes(action))throw new Error('explicit_promotion_action_required');
 const db=new Database(process.env.DATABASE_URL),key='packageExpiryPromotionAnnouncement_20261128';
 try{
  if(action==='stop'){
   const state=await setExpiryPromotion(db,false);console.log(JSON.stringify({active:state.active,action:'stopped',campaignId:state.campaign?.id}));return;
  }
  const campaign=await db.atomic(async()=>{
   await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))',[key]);
   const previous=(await db.query('SELECT value FROM app_settings WHERE key=$1',[key])).rows[0]?.value;
   if(previous){
    const state=await readExpiryPromotion(db);
    const existing=state.intervals.find(p=>p.id===previous.campaignId&&!p.endsAt);
    if(!existing)throw new Error('campaign_already_ended_requires_new_operation');
    return existing;
   }
   const state=await setExpiryPromotion(db,true);
   await db.query('INSERT INTO app_settings(key,value) VALUES($1,$2::jsonb)',[key,JSON.stringify({campaignId:state.campaign.id,startedAt:state.campaign.startsAt})]);
   return state.campaign;
  });
  const notifications=new NotificationService(db,new FcmService());
  const sent=await announceExpiryPromotion(db,notifications,campaign);
  const missing=Number((await db.query(`SELECT COUNT(*)::int n FROM app_users u WHERE u.deleted_at IS NULL AND u.created_at<=$2::timestamptz
   AND NOT EXISTS(SELECT 1 FROM notifications n WHERE n.user_id=u.id AND n.dedupe_key=$1)`,['package-expiry-promo:'+campaign.id,campaign.startsAt])).rows[0].n);
  if(missing)throw new Error('notification_population_incomplete');
  let delivery;
  for(let attempt=0;attempt<31;attempt++){
   delivery=(await db.query(`SELECT COUNT(*)::int AS stored,
    COUNT(*) FILTER(WHERE d.delivered_at IS NOT NULL)::int AS processed,
    COUNT(*) FILTER(WHERE d.delivered_at IS NULL)::int AS pending,
    COUNT(*) FILTER(WHERE d.delivered_at IS NULL AND d.last_error IS NOT NULL)::int AS retrying
    FROM notifications n LEFT JOIN notification_deliveries d ON d.notification_id=n.id WHERE n.dedupe_key=$1`,['package-expiry-promo:'+campaign.id])).rows[0];
   if(!delivery.pending||attempt===30)break;await new Promise(r=>setTimeout(r,2000));
  }
  await db.query("UPDATE app_settings SET value=value||jsonb_build_object('announcedAt',NOW(),'recipients',$2::int) WHERE key=$1",[key,sent.recipients]);
  console.log(JSON.stringify({active:true,campaignId:campaign.id,recipients:sent.recipients,createdThisRun:sent.created,missing,...delivery}));
 }finally{await db.close();}
})().catch(e=>{console.error('PACKAGE_EXPIRY_PROMOTION_FAILED',e.code||e.message||e.name);process.exitCode=1;});
