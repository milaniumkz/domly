import {createHash} from 'node:crypto';
import {Queryable} from '../domain/repositories/UnitOfWork';
import type {NotificationService} from './domainServices';

/** These selections are requests for a separate specialist visit, never an invoice. */
export async function notifySpecialistAddons(db:Queryable,notifications:NotificationService,orderId:string) {
  const rows=(await db.query<{addon_id:string;title_ru:string;quantity:string;numeric_id:number}>(`
    SELECT oa.addon_id,a.title_ru,SUM(oa.quantity)::text AS quantity,o.numeric_id
    FROM order_addons oa JOIN catalog_addons a ON a.id=oa.addon_id
    JOIN service_orders o ON o.id=oa.order_id
    WHERE oa.order_id=$1 AND oa.paid_separately=TRUE
      AND oa.payment_status NOT IN ('cancelled','rejected','refunded')
    GROUP BY oa.addon_id,a.title_ru,o.numeric_id ORDER BY oa.addon_id`,[orderId])).rows;
  if(!rows.length)return;
  const fingerprint=createHash('sha256').update(JSON.stringify(rows)).digest('hex').slice(0,24);
  await notifications.createAdminEvent({event:'specialist_addons',titleRu:'Допуслуги с оплатой по факту',
    bodyRu:`Заказ №${rows[0].numeric_id}: ${rows.map(row=>`${row.title_ru} × ${row.quantity}`).join('; ')}. Требуются специалисты. Оплата отдельно по факту, счёт не выставлен.`,
    targetType:'order',targetId:orderId,dedupeKey:`specialist-addons-${orderId}-${fingerprint}`});
}
