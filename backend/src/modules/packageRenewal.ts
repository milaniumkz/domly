import {Database} from '../infrastructure/db/Database';
import {env} from '../common/env';

export const packageRenewalText='Вы использовали все уборки из оплаченных пакетов DomLY. Хотите купить ещё один пакет? Поможем подобрать подходящий вариант. Новый счёт оформим только по вашему запросу.';
// Completed visits, rather than zero free credits, distinguish consumption from
// reservations and monthly expiry. Never advertise while another paid plan remains.
export const renewalEligibleSql=`cp.available_cleanings=0 AND cp.total_cleanings>0
 AND cp.status IN ('active','expired')
 AND EXISTS(SELECT 1 FROM payments p WHERE p.customer_package_id=cp.id AND p.status='paid')
 AND (SELECT COUNT(*) FROM service_orders o WHERE o.customer_package_id=cp.id AND o.status='completed')>=cp.total_cleanings
 AND NOT EXISTS(SELECT 1 FROM customer_packages other WHERE other.customer_id=cp.customer_id
   AND other.status IN ('active','frozen') AND other.available_cleanings>0
   AND EXISTS(SELECT 1 FROM payments p WHERE p.customer_package_id=other.id AND p.status='paid'))
 AND NOT EXISTS(SELECT 1 FROM service_orders o WHERE o.customer_id=cp.customer_id AND o.status NOT IN ('completed','cancelled'))
 AND NOT EXISTS(SELECT 1 FROM customer_packages newer WHERE newer.customer_id=cp.customer_id
   AND (newer.created_at,newer.id)>(cp.created_at,cp.id)
   AND EXISTS(SELECT 1 FROM payments p WHERE p.customer_package_id=newer.id AND p.status='paid'))
 AND u.role='customer' AND u.deleted_at IS NULL AND u.status<>'blocked'
 AND u.phone ~ '^\\+7[0-9]{10}$' AND COALESCE(u.settings->>'whatsappOptOut','false')<>'true'`;

export async function packageRenewalStillEligible(db:Database,customerId:string,packageId:string){
 return Boolean((await db.query(`SELECT 1 FROM customer_packages cp JOIN app_users u ON u.id=cp.customer_id
  WHERE cp.id=$1 AND cp.customer_id=$2 AND ${renewalEligibleSql}`,[packageId,customerId])).rows.length);
}
export async function queuePackageRenewals(db:Database){
 if(!env.moonAiEnabled)return 0;
 const candidates=(await db.query(`SELECT cp.id,cp.customer_id FROM customer_packages cp JOIN app_users u ON u.id=cp.customer_id
  WHERE ${renewalEligibleSql} AND NOT EXISTS(SELECT 1 FROM moon_ai_outbox b WHERE b.dedupe_key='package-renewal:'||cp.id::text)
  ORDER BY cp.updated_at,cp.id LIMIT 100`)).rows;
 let count=0;
 for(const cp of candidates)await db.atomic(async()=>{
  await db.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[cp.customer_id]);
  if(!await packageRenewalStillEligible(db,cp.customer_id,cp.id))return;
  const chat=(await db.query(`INSERT INTO chats(type,customer_id) VALUES('assistant',$1)
   ON CONFLICT(customer_id) WHERE type='assistant' DO UPDATE SET customer_id=EXCLUDED.customer_id RETURNING id`,[cp.customer_id])).rows[0];
  await db.query('INSERT INTO chat_participants(chat_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING',[chat.id,cp.customer_id]);
  const queued=(await db.query(`INSERT INTO moon_ai_outbox(customer_id,chat_id,kind,dedupe_key,payload)
   VALUES($1,$2,'package_renewal',$3,$4) ON CONFLICT(dedupe_key) DO NOTHING RETURNING id`,
   [cp.customer_id,chat.id,'package-renewal:'+cp.id,{text:packageRenewalText,packageId:cp.id}])).rows[0];
  if(queued){count++;await db.query(`INSERT INTO audit_logs(action,entity_type,entity_id,payload)
    VALUES('bot.moon-ai.package_renewal_queued','customer_package',$1,$2)`,[cp.id,{actorKind:'bot',actorName:'MooonAI',customerId:cp.customer_id,packageId:cp.id,context:{customerPackageId:cp.id},outboxId:queued.id,summary:'Предложение купить новый пакет после использования всех уборок'}]);}
 });
 return count;
}
