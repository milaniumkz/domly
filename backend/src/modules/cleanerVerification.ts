import { ApiError } from '../common/api';
import { first } from '../common/sql';
import { Database } from '../infrastructure/db/Database';
import { NotificationInput, NotificationService } from './domainServices';

export async function verifyCleaner(db: Database, notifications: NotificationService, cleanerId: string, status: string, actorId: string) {
  if (!['approved','rejected','blocked','pending'].includes(status)) throw new ApiError(400,'invalid_status','Укажите корректный статус уборщицы.');
  const input: NotificationInput = {
    userId: cleanerId,
    titleRu: status==='approved'?'Верификация пройдена':'Статус верификации изменён',
    bodyRu: status==='approved'?'Ваш профиль уборщицы подтверждён.':'Проверьте статус профиля в приложении.',
    targetType:'cleaner_profile',targetId:cleanerId,
  };
  const result = await db.transaction(async tx => {
    const previous=first<any>((await tx.query(`SELECT u.status,cp.registration_status,cp.verification_status
      FROM app_users u LEFT JOIN cleaner_profiles cp ON cp.user_id=u.id
      WHERE u.id=$1 AND u.role='cleaner' AND u.deleted_at IS NULL FOR UPDATE OF u`,[cleanerId])).rows);
    if (!previous) throw new ApiError(404,'not_found','Уборщица не найдена.');
    const cleaner=first((await tx.query(`UPDATE app_users SET status=$2::profile_status,updated_at=NOW()
      WHERE id=$1 RETURNING id,phone,full_name,status`,[cleanerId,status])).rows);
    const profile=first((await tx.query(`INSERT INTO cleaner_profiles(user_id,registration_status,verification_status,work_start_date,verified_at)
      VALUES($1,$2::profile_status,$2::profile_status,CASE WHEN $2::text='approved' THEN CURRENT_DATE END,CASE WHEN $2::text='approved' THEN NOW() END)
      ON CONFLICT(user_id) DO UPDATE SET registration_status=EXCLUDED.registration_status,
      verification_status=EXCLUDED.verification_status,
      work_start_date=CASE WHEN EXCLUDED.verification_status='approved' THEN COALESCE(cleaner_profiles.work_start_date,CURRENT_DATE) ELSE cleaner_profiles.work_start_date END,
      verified_at=CASE WHEN EXCLUDED.verification_status='approved' THEN COALESCE(cleaner_profiles.verified_at,NOW()) ELSE NULL END,updated_at=NOW()
      RETURNING *`,[cleanerId,status])).rows);
    const documents=await tx.query('UPDATE cleaner_documents SET status=$2::profile_status WHERE cleaner_id=$1 AND status<>$2::profile_status',[cleanerId,status]);
    const changed=previous.status!==status || previous.registration_status!==status || previous.verification_status!==status || Boolean(documents.rowCount);
    let saved;
    if (changed) {
      saved=await notifications.persist(input,tx);
      await tx.query(`INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload) VALUES($1,'cleaner.verification','cleaner',$2,$3)`,[actorId,cleanerId,{status}]);
    }
    return {cleaner,profile,saved};
  });
  if (result.saved?.created && result.saved.notification) await notifications.deliver(result.saved.notification,input);
  return {cleaner:result.cleaner,profile:result.profile};
}
