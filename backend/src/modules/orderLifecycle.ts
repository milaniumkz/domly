import { ApiError } from '../common/api';
import { first } from '../common/sql';
import { Database } from '../infrastructure/db/Database';
import { NotificationInput, NotificationService } from './domainServices';

// Persist the transition, history and personal notifications together. Push failures
// must not roll back a customer's confirmation or a cleaner's completed work.
export async function transitionOrder(db: Database, notifications: NotificationService, id: string,
  actor: {id: string; role: string}, action: string) {
  const result = await db.transaction(async tx => {
    const order = first<any>((await tx.query('SELECT * FROM service_orders WHERE id=$1 FOR UPDATE', [id])).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
    const confirming = action === 'confirm_start' || action === 'reject_start';
    if (confirming ? actor.role !== 'customer' || order.customer_id !== actor.id
      : actor.role === 'cleaner' ? order.cleaner_id !== actor.id : !['admin','superadmin'].includes(actor.role)) {
      throw new ApiError(403, 'forbidden', 'Нет доступа к этому заказу.');
    }
    let status: string;
    let title: string;
    if (confirming) {
      status = action === 'confirm_start' ? 'in_progress' : 'assigned';
      if (order.status === status && (action === 'confirm_start' ? order.cleaning_start_confirmed : order.cleaning_start_rejected)) return {order, deliveries: []};
      if (order.status !== 'start_pending') throw new ApiError(409, 'invalid_transition', 'Нет запроса на подтверждение начала уборки.');
      title = action === 'confirm_start' ? 'Клиент подтвердил начало уборки' : 'Клиент не подтвердил начало уборки';
    } else if (action === 'in_progress') {
      status = actor.role === 'cleaner' ? 'start_pending' : 'in_progress';
      if (order.status === status) return {order, deliveries: []};
      if (order.status !== 'assigned') throw new ApiError(409, 'invalid_transition', 'Начать можно только назначенный заказ.');
      title = status === 'start_pending' ? 'Подтвердите начало уборки' : 'Уборка началась';
    } else if (action === 'completed') {
      status = 'completed';
      if (order.status === status) return {order, deliveries: []};
      if (order.status !== 'in_progress') throw new ApiError(409, 'invalid_transition', 'Сначала подтвердите начало уборки.');
      if (actor.role === 'cleaner') {
        const report = first<any>((await tx.query('SELECT photo_urls FROM photo_reports WHERE order_id=$1', [id])).rows);
        if (!Array.isArray(report?.photo_urls) || report.photo_urls.length < 3) throw new ApiError(409, 'photo_report_required', 'Добавьте минимум три фотографии уборки.');
      }
      title = 'Уборка завершена';
    } else throw new ApiError(400, 'invalid_status', 'Недопустимый статус заказа.');
    const updated = first<any>((await tx.query(`UPDATE service_orders SET status=$2,
      start_requires_customer_confirmation=CASE WHEN $2='start_pending' THEN TRUE ELSE start_requires_customer_confirmation END,
      cleaning_start_confirmed=CASE WHEN $2='in_progress' THEN TRUE WHEN $2='start_pending' THEN FALSE ELSE cleaning_start_confirmed END,
      cleaning_start_rejected=$3,
      started_at=CASE WHEN $2='in_progress' THEN COALESCE(started_at,NOW()) ELSE started_at END,
      completed_at=CASE WHEN $2='completed' THEN NOW() ELSE completed_at END,updated_at=NOW()
      WHERE id=$1 RETURNING *`, [id,status,action==='reject_start'])).rows)!;
    await tx.query(`INSERT INTO order_status_history(order_id,old_status,new_status,actor_id) VALUES($1,$2,$3,$4)`, [id,order.status,status,actor.id]);
    const deliveries = [];
    for (const recipient of new Set([order.customer_id, order.cleaner_id].filter(Boolean))) {
      const input: NotificationInput = {userId:recipient, titleRu:title, bodyRu:`Заказ №${order.numeric_id}. ${title}.`, targetType:'order', targetId:id};
      const saved = await notifications.persist(input,tx);
      deliveries.push({input,saved});
    }
    return {order:updated,deliveries};
  });
  for (const {input,saved} of result.deliveries) if (saved.created && saved.notification) await notifications.deliver(saved.notification,input);
  return result.order;
}

export async function releaseCleanerAssignment(db: Database, notifications: NotificationService, id: string, cleanerId: string) {
  const input: NotificationInput = {titleRu:'Подбираем другую уборщицу',bodyRu:'Уборщица отказалась от назначенного заказа. Дата, время и оплата сохраняются.',targetType:'order',targetId:id};
  const result = await db.transaction(async tx => {
    const order = first<any>((await tx.query('SELECT * FROM service_orders WHERE id=$1 FOR UPDATE',[id])).rows);
    if (!order || order.cleaner_id !== cleanerId) throw new ApiError(403,'forbidden','Нет доступа к назначению.');
    if (order.status !== 'assigned') throw new ApiError(409,'invalid_transition','Отказаться можно только до начала уборки.');
    // Kazakhstan service dates are local time (UTC+5), not the server timezone.
    const early = first<{allowed:boolean}>((await tx.query(`SELECT (scheduled_date+start_time) AT TIME ZONE 'Asia/Almaty' >= NOW()+INTERVAL '12 hours' AS allowed FROM service_orders WHERE id=$1`,[id])).rows);
    if (early?.allowed !== true) throw new ApiError(409,'too_late','Отказаться можно минимум за 12 часов до начала.');
    const updated=first<any>((await tx.query(`UPDATE service_orders SET cleaner_id=NULL,status='pending_assignment',start_requires_customer_confirmation=FALSE,cleaning_start_confirmed=FALSE,cleaning_start_rejected=FALSE,updated_at=NOW() WHERE id=$1 RETURNING *`,[id])).rows)!;
    await tx.query("UPDATE order_offers SET status=CASE WHEN cleaner_id=$2 THEN 'declined' ELSE 'expired' END WHERE order_id=$1",[id,cleanerId]);
    await tx.query("INSERT INTO order_status_history(order_id,old_status,new_status,actor_id,comment) VALUES($1,'assigned','pending_assignment',$2,'Уборщица отказалась от назначения')",[id,cleanerId]);
    input.userId=order.customer_id;
    const saved=await notifications.persist(input,tx);
    return {order:updated,saved};
  });
  if (result.saved.created && result.saved.notification) await notifications.deliver(result.saved.notification,input);
  return result.order;
}
