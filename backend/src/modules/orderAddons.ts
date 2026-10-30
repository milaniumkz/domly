import {customerTierDiscount,discountedServicePrice} from './customerProgress';
import {durationAfterAddonChange} from './cleaningDuration';
import {notifySpecialistAddons} from './specialistAddons';
import type {NotificationService} from './domainServices';
import { Database } from '../infrastructure/db/Database';
import { first } from '../common/sql';
import { ApiError } from '../common/api';

export async function updateOrderAddons(db: Database, orderId: string, customerId: string, desired: any[],notifications?:NotificationService) {
  if (!Array.isArray(desired) || desired.length>100) throw new ApiError(400,'invalid_addons','Проверьте список услуг.');
  return db.atomic(()=>db.transaction(async tx => {
    const order = first<any>((await tx.query('SELECT * FROM service_orders WHERE id=$1 AND customer_id=$2 FOR UPDATE',[orderId,customerId])).rows);
    if (!order) throw new ApiError(404,'order_not_found','Заказ не найден.');
    if (['completed','cancelled'].includes(order.status)) throw new ApiError(409,'order_not_editable','Этот заказ нельзя изменить.');
    const invoice = first((await tx.query("SELECT id FROM payments WHERE order_id=$1 AND status IN ('pending','invoice_requested') LIMIT 1",[orderId])).rows);
    if (invoice) throw new ApiError(409,'pending_invoice','Сначала оплатите или отмените выставленный счёт.');
    const existing = (await tx.query<any>('SELECT * FROM order_addons WHERE order_id=$1',[orderId])).rows;
    const selected = new Map<string,number>();
    for (const item of desired) {
      const id = String(item.id ?? item.addonId ?? item.key ?? '');
      const quantity = Number(item.quantity ?? 1);
      if (!/^[0-9a-f-]{36}$/i.test(id) || !Number.isInteger(quantity) || quantity<1 || quantity>100 || selected.has(id)) throw new ApiError(400,'invalid_addons','Проверьте количество услуг.');
      selected.set(id,quantity);
    }
    const paid = new Map<string,number>();
    for (const row of existing.filter(row=>row.payment_status==='paid')) paid.set(row.addon_id,(paid.get(row.addon_id) ?? 0)+Number(row.quantity));
    for (const [id,quantity] of paid) if ((selected.get(id) ?? 0)<quantity) throw new ApiError(409,'paid_addon','Оплаченные услуги нельзя удалить без возврата.');
    await tx.query("DELETE FROM order_addons WHERE order_id=$1 AND payment_status<>'paid' AND requires_customer_approval IS DISTINCT FROM TRUE",[orderId]);
    const tierPercent=await customerTierDiscount(tx,customerId);
    for (const [id,totalQuantity] of selected) {
      const quantity = totalQuantity-(paid.get(id) ?? 0);
      if (quantity<=0) continue;
      const addon = first<any>((await tx.query('SELECT * FROM catalog_addons WHERE id=$1 AND active=TRUE',[id])).rows);
      if (!addon) throw new ApiError(400,'invalid_addons','Услуга недоступна.');
      const address = first<any>((await tx.query('SELECT area FROM customer_addresses WHERE id=$1',[order.address_id])).rows);
      const unit = Number(addon.price) * (['per_m2','per_sqm'].includes(addon.pricing_type)?Number(address?.area ?? order.area):1);
      const price=addon.paid_separately?unit:discountedServicePrice(unit,tierPercent);
      await tx.query("INSERT INTO order_addons (order_id,addon_id,quantity,price,duration_minutes,payment_status,paid_separately,requires_customer_approval) VALUES ($1,$2,$3,$4,$5,$6,$7,FALSE)",[orderId,id,quantity,price,addon.paid_separately?0:Number(addon.duration_minutes)*quantity,addon.paid_separately?'draft':'pending',addon.paid_separately]);
    }
    const totals = first<any>((await tx.query(`SELECT COALESCE(SUM(price*quantity) FILTER (WHERE paid_separately=FALSE AND requires_customer_approval IS DISTINCT FROM TRUE),0) AS total,
      COALESCE(SUM(price*quantity) FILTER (WHERE payment_status<>'paid' AND paid_separately=FALSE AND requires_customer_approval IS DISTINCT FROM TRUE),0) AS pending,
      COALESCE(SUM(duration_minutes) FILTER (WHERE requires_customer_approval IS DISTINCT FROM TRUE),0) AS duration FROM order_addons WHERE order_id=$1`,[orderId])).rows);
    const oldDuration = existing.filter(row=>row.requires_customer_approval!==true).reduce((sum,row)=>sum+Number(row.duration_minutes),0);
    const duration = durationAfterAddonChange(order,oldDuration,Number(totals.duration));
    if (order.cleaner_id) {
      const overlap=first((await tx.query(`SELECT id FROM service_orders WHERE cleaner_id=$1
        AND id<>$3 AND status NOT IN ('cancelled','completed') AND scheduled_date+start_time<($2::date+$4::time+$5::int*INTERVAL '1 minute')
        AND cleaning_end_at(scheduled_date,start_time,end_time,estimated_duration_minutes)>$2::date+$4::time LIMIT 1`,[order.cleaner_id,order.scheduled_date,order.id,order.start_time,duration])).rows);
      if (overlap) throw new ApiError(409,'cleaner_unavailable','Дополнительные услуги пересекаются со следующим заказом уборщицы.');
    }
    const updated = first((await tx.query(`UPDATE service_orders SET addon_amount=$2,total_amount=$2,payable_amount=$3,
      estimated_duration_minutes=$4,end_time=start_time+($4::int*INTERVAL '1 minute'),updated_at=NOW()
      WHERE id=$1 RETURNING *`,[orderId,totals.total,totals.pending,duration])).rows);
    if(notifications)await notifySpecialistAddons(tx,notifications,orderId);
    return {order: updated,payableAmount:Number(totals.pending)};
  }));
}
