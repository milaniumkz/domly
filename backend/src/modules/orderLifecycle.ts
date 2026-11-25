import { ApiError } from '../common/api';
import { first } from '../common/sql';
import { Database } from '../infrastructure/db/Database';
import { NotificationInput, NotificationService } from './domainServices';

// Persist the transition, history and personal notifications together. Push failures
// must not roll back a customer's confirmation or a cleaner's completed work.
export async function transitionOrder(db: Database, notifications: NotificationService, id: string,
  actor: {id: string; role: string}, action: string) {
  const result = await db.transaction(async tx => {
    await tx.query("SELECT pg_advisory_xact_lock(hashtextextended('domly:booking-create-reschedule',0))");
    const order = first<any>((await tx.query('SELECT * FROM service_orders WHERE id=$1 FOR UPDATE', [id])).rows);
    if (!order) throw new ApiError(404, 'not_found', 'Заказ не найден.');
    const member=actor.role==='cleaner'?(await tx.query<any>("SELECT * FROM order_team_members WHERE order_id=$1 AND cleaner_id=$2 AND status IN ('accepted','in_progress','completed') FOR UPDATE",[id,actor.id])).rows[0]:null;
    const confirming = action === 'confirm_start' || action === 'reject_start';
    if (confirming ? actor.role !== 'customer' || order.customer_id !== actor.id
      : actor.role === 'cleaner' ? !member && order.cleaner_id !== actor.id : !['admin','superadmin'].includes(actor.role)) {
      throw new ApiError(403, 'forbidden', 'Нет доступа к этому заказу.');
    }
    if(member && action==='in_progress'){
      if(member.status==='completed')throw new ApiError(409,'part_completed','Ваша часть уборки уже завершена.');
      if(!['assigned','start_pending','in_progress'].includes(order.status))throw new ApiError(409,'team_not_ready','Дождитесь подтверждения всех участников команды.');
      await tx.query("UPDATE order_team_members SET started_at=COALESCE(started_at,NOW()),status=CASE WHEN $2 THEN 'in_progress' ELSE status END,updated_at=NOW() WHERE id=$1",[member.id,order.status==='in_progress']);
      if(order.status!=='assigned')return {order,deliveries:[]};
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
        const checklist = (await tx.query(`SELECT r.id FROM checklist_reports r WHERE r.order_id=$1 AND ($2::uuid IS NULL OR r.cleaner_id=$2) AND r.requirements_initialized
          AND EXISTS(SELECT 1 FROM checklist_report_items i WHERE i.report_id=r.id AND i.required)
          AND NOT EXISTS(SELECT 1 FROM checklist_report_items i WHERE i.report_id=r.id AND i.required AND NOT i.checked)`,[id,member?actor.id:null])).rows;
        if(!checklist.length)throw new ApiError(409,'checklist_required','Заполните все обязательные пункты чек-листа перед завершением уборки.');
        const report = first<any>((await tx.query(`SELECT photo_urls FROM ${Number(order.required_cleaners)>1?'team_photo_reports':'photo_reports'} WHERE order_id=$1 AND ($2::uuid IS NULL OR cleaner_id=$2)`, [id,member?actor.id:null])).rows);
        if (!Array.isArray(report?.photo_urls) || report.photo_urls.length < 3) throw new ApiError(409, 'photo_report_required', 'Добавьте минимум три фотографии уборки.');
      }
      if(member){
        if(member.status==='completed')return {order:{...order,status:'completed',team_order_status:order.status},deliveries:[]};
        if(!member.started_at)throw new ApiError(409,'part_not_started','Сначала начните свою часть уборки.');
        await tx.query("UPDATE order_team_members SET status='completed',completed_at=NOW(),updated_at=NOW() WHERE id=$1",[member.id]);
        await tx.query("INSERT INTO order_status_history(order_id,old_status,new_status,actor_id,comment) VALUES($1,$2,$2,$3,'Участник команды завершил свою часть уборки')",[id,order.status,actor.id]);
        const remaining=(await tx.query("SELECT id FROM order_team_members WHERE order_id=$1 AND status<>'completed'",[id])).rows.length;
        if(remaining)return {order:{...order,status:'completed',team_order_status:order.status},deliveries:[]};
      }
      title = 'Уборка завершена';
    } else throw new ApiError(400, 'invalid_status', 'Недопустимый статус заказа.');
    if(action==='confirm_start')await tx.query("UPDATE order_team_members SET status='in_progress',updated_at=NOW() WHERE order_id=$1 AND status='accepted' AND started_at IS NOT NULL",[id]);
    if(action==='reject_start')await tx.query("UPDATE order_team_members SET status='accepted',started_at=NULL,updated_at=NOW() WHERE order_id=$1 AND status IN ('accepted','in_progress')",[id]);
    if(status==='completed' && actor.role!=='cleaner')await tx.query("UPDATE order_team_members SET status='completed',completed_at=COALESCE(completed_at,NOW()),updated_at=NOW() WHERE order_id=$1",[id]);
    const updated = first<any>((await tx.query(`UPDATE service_orders SET status=$2,
      start_requires_customer_confirmation=CASE WHEN $2='start_pending' THEN TRUE ELSE start_requires_customer_confirmation END,
      cleaning_start_confirmed=CASE WHEN $2='in_progress' THEN TRUE WHEN $2='start_pending' THEN FALSE ELSE cleaning_start_confirmed END,
      cleaning_start_rejected=$3,
      started_at=CASE WHEN $2='in_progress' THEN COALESCE(started_at,NOW()) ELSE started_at END,
      completed_at=CASE WHEN $2='completed' THEN NOW() ELSE completed_at END,updated_at=NOW()
      WHERE id=$1 RETURNING *`, [id,status,action==='reject_start'])).rows)!;
    await tx.query(`INSERT INTO order_status_history(order_id,old_status,new_status,actor_id) VALUES($1,$2,$3,$4)`, [id,order.status,status,actor.id]);
    const deliveries = [];
    for (const recipient of new Set([order.customer_id, order.cleaner_id,...(await tx.query<{cleaner_id:string}>('SELECT cleaner_id FROM order_team_members WHERE order_id=$1',[id])).rows.map(r=>r.cleaner_id)].filter(Boolean))) {
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
    await tx.query("SELECT pg_advisory_xact_lock(hashtextextended('domly:booking-create-reschedule',0))");
    const order = first<any>((await tx.query('SELECT * FROM service_orders WHERE id=$1 FOR UPDATE',[id])).rows);
    const member=(await tx.query<any>("SELECT * FROM order_team_members WHERE order_id=$1 AND cleaner_id=$2 AND status='accepted' FOR UPDATE",[id,cleanerId])).rows[0];
    if (!order || !member && order.cleaner_id !== cleanerId) throw new ApiError(403,'forbidden','Нет доступа к назначению.');
    if (order.status !== 'assigned') throw new ApiError(409,'invalid_transition','Отказаться можно только до начала уборки.');
    // Kazakhstan service dates are local time (UTC+5), not the server timezone.
    const early = first<{allowed:boolean}>((await tx.query(`SELECT (scheduled_date+start_time) AT TIME ZONE 'Asia/Almaty' >= NOW()+INTERVAL '12 hours' AS allowed FROM service_orders WHERE id=$1`,[id])).rows);
    if (early?.allowed !== true) throw new ApiError(409,'too_late','Отказаться можно минимум за 12 часов до начала.');
    const updated=first<any>((await tx.query(`UPDATE service_orders SET cleaner_id=NULL,status='pending_assignment',start_requires_customer_confirmation=FALSE,cleaning_start_confirmed=FALSE,cleaning_start_rejected=FALSE,updated_at=NOW() WHERE id=$1 RETURNING *`,[id])).rows)!;
    if(member){
      await tx.query("UPDATE order_team_members SET cleaner_id=NULL,status='reserved',accepted_at=NULL,started_at=NULL,updated_at=NOW() WHERE id=$1",[member.id]);
      await tx.query('DELETE FROM chat_participants cp USING chats c WHERE cp.chat_id=c.id AND c.order_id=$1 AND cp.user_id=$2',[id,cleanerId]);
      await tx.query("UPDATE order_offers SET status='declined' WHERE order_id=$1 AND cleaner_id=$2",[id,cleanerId]);
    }else await tx.query("UPDATE order_offers SET status=CASE WHEN cleaner_id=$2 THEN 'declined' ELSE 'expired' END WHERE order_id=$1",[id,cleanerId]);
    await tx.query("INSERT INTO order_status_history(order_id,old_status,new_status,actor_id,comment) VALUES($1,'assigned','pending_assignment',$2,'Уборщица отказалась от назначения')",[id,cleanerId]);
    input.userId=order.customer_id;
    const saved=await notifications.persist(input,tx);
    return {order:updated,saved};
  });
  if (result.saved.created && result.saved.notification) await notifications.deliver(result.saved.notification,input);
  return result.order;
}
