import {randomUUID} from 'crypto';
import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';

export async function requestAccountDeletion(db: Database, userId: string) {
  return db.transaction(async tx => {
    const user=(await tx.query('SELECT * FROM app_users WHERE id=$1 FOR UPDATE',[userId])).rows[0];
    if(!user)throw new ApiError(404,'not_found','Аккаунт не найден.');
    const existing=(await tx.query(`SELECT * FROM account_deletion_requests WHERE user_id=$1
      AND restored_at IS NULL AND anonymized_at IS NULL FOR UPDATE`,[userId])).rows[0];
    if(user.deleted_at && existing)return {deleted:true,restoreUntil:existing.restore_until};
    const busy=(await tx.query(`SELECT id FROM service_orders WHERE (customer_id=$1 OR cleaner_id=$1)
      AND status NOT IN ('completed','cancelled','canceled') LIMIT 1`,[userId])).rows[0];
    if(busy)throw new ApiError(409,'active_orders','Завершите или отмените текущие заказы перед удалением аккаунта.');
    const profile=(await tx.query('SELECT * FROM cleaner_profiles WHERE user_id=$1 FOR UPDATE',[userId])).rows[0];
    const deletion=(await tx.query(`INSERT INTO account_deletion_requests
      (user_id,previous_status,previous_registration_status,previous_verification_status,restore_until)
      VALUES($1,$2,$3,$4,NOW()+INTERVAL '30 days') RETURNING *`,
      [userId,user.status,profile?.registration_status??null,profile?.verification_status??null])).rows[0];
    await tx.query('DELETE FROM device_tokens WHERE user_id=$1',[userId]);
    await tx.query('UPDATE refresh_sessions SET revoked_at=NOW() WHERE user_id=$1',[userId]);
    await tx.query(`UPDATE app_users SET status='blocked',deleted_at=NOW(),
      auth_version=COALESCE(auth_version,0)+1,updated_at=NOW() WHERE id=$1`,[userId]);
    await tx.query("UPDATE cleaner_profiles SET registration_status='blocked',verification_status='blocked',updated_at=NOW() WHERE user_id=$1",[userId]);
    await tx.query(`INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload)
      VALUES($1::uuid,'account.deletion_requested','user',$1::text,$2)`,[userId,{restoreUntil:deletion.restore_until}]);
    return {deleted:true,restoreUntil:deletion.restore_until};
  });
}

export async function restoreDeletedAccount(db: Database,userId:string,actorId:string) {
  return db.transaction(async tx=>{
    const user=(await tx.query('SELECT * FROM app_users WHERE id=$1 FOR UPDATE',[userId])).rows[0];
    if(!user)throw new ApiError(404,'not_found','Клиент не найден.');
    if(!user.deleted_at)return {restored:true,changed:false};
    const deletion=(await tx.query(`SELECT *,restore_until>NOW() AS recoverable FROM account_deletion_requests
      WHERE user_id=$1 AND restored_at IS NULL AND anonymized_at IS NULL FOR UPDATE`,[userId])).rows[0];
    if(!deletion?.recoverable || user.phone.startsWith('deleted-'))
      throw new ApiError(410,'restore_expired','Срок восстановления аккаунта истёк или данные уже обезличены.');
    await tx.query(`UPDATE app_users SET status=$2::profile_status,deleted_at=NULL,
      auth_version=COALESCE(auth_version,0)+1,updated_at=NOW() WHERE id=$1`,[userId,deletion.previous_status]);
    if(deletion.previous_registration_status && deletion.previous_verification_status)
      await tx.query(`UPDATE cleaner_profiles SET registration_status=$2::profile_status,
        verification_status=$3::profile_status,updated_at=NOW() WHERE user_id=$1`,
        [userId,deletion.previous_registration_status,deletion.previous_verification_status]);
    await tx.query('UPDATE account_deletion_requests SET restored_at=NOW(),restored_by=$2 WHERE id=$1',[deletion.id,actorId]);
    await tx.query(`INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload)
      VALUES($1,'account.restored','user',$2,$3)`,[actorId,userId,{deletionRequestId:deletion.id}]);
    return {restored:true,changed:true};
  });
}

export async function anonymizeExpiredAccountDeletions(db: Database, limit=100) {
  const candidates=(await db.query(`SELECT d.user_id FROM account_deletion_requests d JOIN app_users u ON u.id=d.user_id
    WHERE d.restored_at IS NULL AND d.anonymized_at IS NULL AND d.restore_until<=NOW() AND u.deleted_at IS NOT NULL
    ORDER BY d.restore_until LIMIT $1`,[limit])).rows;
  let count=0;
  for(const candidate of candidates) {
    const changed=await db.transaction(async tx=>{
      const user=(await tx.query('SELECT id,deleted_at FROM app_users WHERE id=$1 FOR UPDATE',[candidate.user_id])).rows[0];
      if(!user?.deleted_at)return false;
      const deletion=(await tx.query(`SELECT * FROM account_deletion_requests WHERE user_id=$1
        AND restored_at IS NULL AND anonymized_at IS NULL AND restore_until<=NOW() FOR UPDATE`,[candidate.user_id])).rows[0];
      if(!deletion)return false;
      await tx.query(`UPDATE customer_addresses SET city='Удалено',settlement=NULL,street='Удалено',house='-',apartment=NULL,
        entrance=NULL,floor=NULL,intercom=NULL,access_comment=NULL,area=NULL,latitude=NULL,longitude=NULL WHERE user_id=$1`,[user.id]);
      await tx.query(`UPDATE cleaner_profiles SET home_address=NULL,emergency_contact_phone=NULL,
        emergency_contact_relation=NULL,updated_at=NOW() WHERE user_id=$1`,[user.id]);
      await tx.query('DELETE FROM house_waitlist WHERE user_id=$1',[user.id]);
      await tx.query(`UPDATE app_users SET phone=$2,full_name=NULL,email=NULL,password_hash=NULL,firebase_uid=NULL,
        auth_version=COALESCE(auth_version,0)+1,updated_at=NOW() WHERE id=$1`,[user.id,'deleted-'+randomUUID()]);
      await tx.query('UPDATE account_deletion_requests SET anonymized_at=NOW() WHERE id=$1',[deletion.id]);
      await tx.query(`INSERT INTO audit_logs(action,entity_type,entity_id,payload)
        VALUES('account.anonymized','user',$1,$2)`,[user.id,{deletionRequestId:deletion.id}]);
      return true;
    });
    if(changed)count++;
  }
  return {anonymized:count};
}
