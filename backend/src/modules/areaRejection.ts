import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';
import type {NotificationService} from './domainServices';

export async function rejectAreaDocument(db:Database,notifications:NotificationService,id:string,adminId:string,input:unknown) {
  const reason=typeof input==='string'?input.trim():'';
  if(!reason||reason.length>1000)throw new ApiError(400,'rejection_reason_required','Укажите причину отклонения документа (до 1000 символов).');
  return db.atomic(async()=>{
    const current=(await db.query('SELECT * FROM quality_check_requests WHERE id=$1 FOR UPDATE',[id])).rows[0];
    if(!current)throw new ApiError(404,'not_found','Заявка проверки площади не найдена.');
    if(current.status==='rejected')return current;
    if(current.status==='cancelled')throw new ApiError(409,'quality_check_closed','Заявка закрыта.');
    const address=(await db.query(`SELECT id FROM customer_addresses WHERE user_id=$1
      AND ($2::uuid IS NULL OR id=$2) ORDER BY is_primary DESC,created_at DESC LIMIT 1 FOR UPDATE`,[current.customer_id,current.address_id])).rows[0];
    if(current.status==='approved'&&address) {
      // Rejecting an older review must not invalidate a later approval of this address.
      const newer=(await db.query(`SELECT 1 FROM quality_check_requests WHERE customer_id=$1
        AND (address_id=$2 OR address_id IS NULL) AND id<>$3 AND status='approved' AND updated_at>=$4 LIMIT 1`,
        [current.customer_id,address.id,id,current.updated_at])).rows.length;
      if(!newer)await db.query('UPDATE customer_addresses SET verified_area=NULL,updated_at=NOW() WHERE id=$1',[address.id]);
    }
    const row=(await db.query(`UPDATE quality_check_requests SET status='rejected',admin_comment=$2,admin_id=$3,updated_at=NOW()
      WHERE id=$1 RETURNING *`,[id,reason,adminId])).rows[0];
    await db.query(`INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload)
      VALUES($1,'quality_check.rejected','quality_check',$2,$3)`,[adminId,id,{reason,previousStatus:current.status}]);
    await notifications.create({userId:row.customer_id,titleRu:'Документ площади отклонён',titleKk:'Аудан құжаты қабылданбады',
      bodyRu:`Причина: ${reason}\nЗагрузите новое фото плана квартиры для повторной проверки.`,
      bodyKk:`Себебі: ${reason}\nҚайта тексеру үшін пәтер жоспарының жаңа фотосын жүктеңіз.`,
      targetType:'area_verification',targetId:address?.id??'',dedupeKey:`area-document-rejected-${id}`});
    return row;
  });
}
