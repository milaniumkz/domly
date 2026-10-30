import {randomUUID} from 'node:crypto';
import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';
import {NotificationService} from './domainServices';
import {storageKey} from './mediaLinks';

export async function submitCleanerPhoto(db:Database,notifications:NotificationService,cleanerId:string,url:string) {
  const key=storageKey(url);
  if(!key)throw new ApiError(400,'invalid_photo','Загрузите собственное фото через приложение.');
  return db.atomic(async()=>{
    const user=(await db.query('SELECT id,full_name FROM app_users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE',[cleanerId])).rows[0];
    if(!user)throw new ApiError(404,'not_found','Профиль не найден.');
    const file=(await db.query(`SELECT f.* FROM files f WHERE f.owner_id=$1 AND f.object_key=$2
      AND f.mime_type IN ('image/jpeg','image/png','image/webp')
      AND NOT EXISTS(SELECT 1 FROM banners b WHERE b.image_file_id=f.id OR b.image_url=f.public_url)
      AND NOT EXISTS(SELECT 1 FROM promotions p WHERE p.banner_file_id=f.id)`,[cleanerId,key])).rows[0];
    if(!file)throw new ApiError(400,'invalid_photo','Загрузите собственное фото через приложение.');
    const duplicate=(await db.query("SELECT * FROM cleaner_documents WHERE cleaner_id=$1 AND type='profile_photo' AND file_id=$2 AND status IN ('pending','approved') ORDER BY created_at DESC LIMIT 1",[cleanerId,file.id])).rows[0];
    if(duplicate)return duplicate;
    await db.query("UPDATE cleaner_documents SET status='rejected' WHERE cleaner_id=$1 AND type='profile_photo' AND status='pending'",[cleanerId]);
    const document=(await db.query("INSERT INTO cleaner_documents(id,cleaner_id,type,file_id,status) VALUES($1,$2,'profile_photo',$3,'pending') RETURNING *",[randomUUID(),cleanerId,file.id])).rows[0];
    // Profile-photo moderation is mandatory, independent of optional admin event filters.
    for(const role of ['admin','superadmin'] as const)await notifications.create({role,titleRu:'Новое фото уборщицы на проверку',bodyRu:`${user.full_name||'Уборщица'} отправила новое селфи. Требуется одобрение.`,targetType:'profile_photo',targetId:document.id,dedupeKey:`profile-photo-${role}-${document.id}`});
    return document;
  });
}

export async function reviewCleanerPhoto(db:Database,notifications:NotificationService,id:string,status:string,actorId:string) {
  if(!['approved','rejected'].includes(status))throw new ApiError(400,'invalid_status','Одобрите или отклоните фото.');
  return db.atomic(async()=>{
    const photo=(await db.query("SELECT * FROM cleaner_documents WHERE id=$1 AND type='profile_photo' FOR UPDATE",[id])).rows[0];
    if(!photo)throw new ApiError(404,'not_found','Заявка не найдена.');
    if(photo.status===status)return photo;
    if(photo.status!=='pending')throw new ApiError(409,'already_reviewed','Заявка уже рассмотрена или заменена новым фото.');
    const updated=(await db.query('UPDATE cleaner_documents SET status=$2 WHERE id=$1 RETURNING *',[id,status])).rows[0];
    await db.query("INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload) VALUES($1,'cleaner.photo.review','cleaner_document',$2,$3)",[actorId,id,{status,cleanerId:photo.cleaner_id}]);
    await notifications.create({userId:photo.cleaner_id,titleRu:status==='approved'?'Фото профиля одобрено':'Фото профиля отклонено',bodyRu:status==='approved'?'Новое фото отображается в вашем профиле.':'Загрузите другое селфи в профиле.',targetType:'profile_photo',targetId:photo.cleaner_id,dedupeKey:`profile-photo-reviewed-${id}`});
    return updated;
  });
}
