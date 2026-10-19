// Explicit operator repair: preserve account data, convert one blocked cleaner to customer.
// The workflow accepts a phone hash, never a phone number or credentials.
const {Database}=require('/app/dist/infrastructure/db/Database');
const {scheduleSignupFollowup}=require('/app/dist/modules/moonAi');
(async()=>{
 const hash=process.env.PHONE_SHA256||'';
 if(!/^[a-f0-9]{64}$/.test(hash))throw Error('Invalid phone hash');
 const db=new Database(process.env.DATABASE_URL);
 try{
  const id=await db.transaction(async tx=>{
   const rows=(await tx.query("SELECT id,role,status FROM app_users WHERE encode(sha256(convert_to(phone,'UTF8')),'hex')=$1 FOR UPDATE",[hash])).rows;
   if(rows.length!==1)throw Error('Expected exactly one account');
   const user=rows[0];
   if(user.role==='customer' && user.status==='approved')return user.id;
   if(user.role!=='cleaner'||user.status!=='blocked')throw Error('Only a blocked cleaner can be restored as customer');
   const active=(await tx.query("SELECT 1 FROM service_orders WHERE cleaner_id=$1 AND status::text NOT IN ('completed','cancelled') LIMIT 1",[user.id])).rows;
   if(active.length)throw Error('Account has active cleaner orders; preserve assignment before conversion');
   await tx.query("UPDATE app_users SET role='customer',status='approved',updated_at=NOW() WHERE id=$1",[user.id]);
   await tx.query('UPDATE refresh_sessions SET revoked_at=NOW() WHERE user_id=$1 AND revoked_at IS NULL',[user.id]);
   await tx.query('UPDATE auth_otp_codes SET consumed_at=NOW() WHERE phone=(SELECT phone FROM app_users WHERE id=$1) AND consumed_at IS NULL',[user.id]);
   await tx.query('UPDATE device_tokens SET enabled=FALSE WHERE user_id=$1',[user.id]);
   await tx.query("INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('user.restored_as_customer','user',$1,$2)",[user.id,{previousRole:user.role,previousStatus:user.status,role:'customer',status:'approved',source:'authorized_support_workflow'}]);
   return user.id;
  });
  await scheduleSignupFollowup(db,id);
  const followups=(await db.query("SELECT state,run_after,failure_code FROM moon_ai_outbox WHERE customer_id=$1 AND kind='inactive_signup'",[id])).rows;
  console.log(JSON.stringify({role:'customer',status:'approved',historyPreserved:true,followups}));
 }finally{await db.close();}
})().catch(e=>{console.error('Customer restore failed:',e.message);process.exitCode=1;});
