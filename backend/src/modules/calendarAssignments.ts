import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';
import {NotificationService,SchedulingService} from './domainServices';
import {Queryable} from '../domain/repositories/UnitOfWork';

type Move={orderId:string;fromCleanerId:string;toCleanerId:string};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function validateMove(move:Move){
 if(!move||![move.orderId,move.fromCleanerId,move.toCleanerId].every(v=>typeof v==='string'&&uuid.test(v))||move.fromCleanerId===move.toCleanerId)
  throw new ApiError(400,'invalid_assignment','Выберите заказ и разных уборщиц.');
}
async function source(tx:Queryable,move:Move){
 const order=(await tx.query<any>('SELECT o.*,o.scheduled_date::text AS service_date,COALESCE(NULLIF(o.area,0),(SELECT COALESCE(a.verified_area,a.area) FROM customer_addresses a WHERE a.id=o.address_id),0) AS area FROM service_orders o WHERE o.id=$1 FOR UPDATE',[move.orderId])).rows[0];
 if(!order)throw new ApiError(404,'not_found','Заказ не найден.');
 if(!['assigned','pending_assignment','waiting_cleaner'].includes(order.status))throw new ApiError(409,'invalid_transition','Передать можно только ещё не начатый заказ.');
 const members=(await tx.query<any>('SELECT * FROM order_team_members WHERE order_id=$1 ORDER BY slot_number FOR UPDATE',[order.id])).rows;
 const member=members.find(m=>m.cleaner_id===move.fromCleanerId);
 if(members.length?(!member||member.status!=='accepted'):order.cleaner_id!==move.fromCleanerId)
  throw new ApiError(409,'assignment_changed','Назначение изменилось. Обновите календарь.');
 const future=(await tx.query('SELECT $1::date+$2::time > NOW() AT TIME ZONE \'Asia/Almaty\' AS future',[order.service_date,order.start_time])).rows[0]?.future;
 if(!future)throw new ApiError(409,'order_already_due','Передавать можно только предстоящие заказы.');
 if(members.some(m=>m.cleaner_id===move.toCleanerId))throw new ApiError(409,'already_in_team','Эта уборщица уже входит в команду заказа.');
 return {order,member,area:Number(member?.allocated_area??order.area??0),move};
}

export async function calendarTransferCandidates(db:Database,orderId:string,fromCleanerId:string){
 if(!uuid.test(orderId)||!uuid.test(fromCleanerId))throw new ApiError(400,'invalid_assignment','Выберите заказ и уборщицу.');
 return db.transaction(async tx=>{
  const item=await source(tx,{orderId,fromCleanerId,toCleanerId:'00000000-0000-4000-8000-000000000000'});
  const rows=await new SchedulingService(db).availableCleaners(item.order.service_date,item.order.start_time,item.order.end_time,undefined,tx,true,Number(item.order.estimated_duration_minutes),item.area,orderId);
  const members=(await tx.query('SELECT cleaner_id FROM cleaner_order_workloads WHERE id=$1',[orderId])).rows;
  return rows.filter(c=>c.id!==fromCleanerId&&!members.some(m=>m.cleaner_id===c.id));
 });
}

/** Remove both outgoing allocations inside one transaction before validating the final swap. */
export async function moveCalendarAssignments(db:Database,notifications:NotificationService,actorId:string,moves:Move[]){
 if(!Array.isArray(moves)||![1,2].includes(moves.length))throw new ApiError(400,'invalid_assignment','Выберите передачу или обмен двух заказов.');
 moves.forEach(validateMove);
 if(moves.length===2&&(moves[0].orderId===moves[1].orderId||moves[0].fromCleanerId!==moves[1].toCleanerId||moves[1].fromCleanerId!==moves[0].toCleanerId))
  throw new ApiError(400,'invalid_swap','Для обмена выберите два разных заказа у двух уборщиц.');
 return db.atomic(async()=>{
  await db.query("SELECT pg_advisory_xact_lock(hashtextextended('domly:booking-create-reschedule',0))");
  const ids=[...new Set(moves.flatMap(m=>[m.fromCleanerId,m.toCleanerId]))].sort();
  const users=(await db.query("SELECT u.id,u.status,u.deleted_at,p.verification_status FROM app_users u LEFT JOIN cleaner_profiles p ON p.user_id=u.id WHERE u.id=ANY($1::uuid[]) AND u.role='cleaner' ORDER BY u.id FOR UPDATE OF u",[ids])).rows;
  for(const move of moves)if(!users.some(u=>u.id===move.toCleanerId&&u.status==='approved'&&!u.deleted_at&&u.verification_status==='approved'))throw new ApiError(409,'cleaner_inactive','Выбранная уборщица не активна или не прошла проверку.');
  const items=[];for(const move of [...moves].sort((a,b)=>a.orderId.localeCompare(b.orderId)))items.push(await source(db,move));
  for(const item of items){
   if(item.member)await db.query('UPDATE order_team_members SET cleaner_id=NULL WHERE id=$1',[item.member.id]);
   else await db.query('UPDATE service_orders SET cleaner_id=NULL WHERE id=$1',[item.order.id]);
  }
  for(const item of items){
   const o=item.order,m=item.move;
   const allowed=(await db.query(`SELECT domly_cleaner_slot_allowed($1::uuid,$2::date,$3::time,$4::time,$5::int,$6::numeric,$7::uuid) AS allowed`,[m.toCleanerId,o.service_date,o.start_time,o.end_time,o.estimated_duration_minutes,item.area,o.id])).rows[0]?.allowed;
   if(!allowed)throw new ApiError(409,'cleaner_unavailable','Передача невозможна: проверьте график, другие заказы, перерыв между уборками и лимит 250 м² за день.');
   if(item.member){
    await db.query("UPDATE order_team_members SET cleaner_id=$2,accepted_at=NOW(),updated_at=NOW() WHERE id=$1",[item.member.id,m.toCleanerId]);
    await db.query("UPDATE service_orders SET cleaner_id=(SELECT cleaner_id FROM order_team_members WHERE order_id=$1 AND slot_number=0),updated_at=NOW() WHERE id=$1 AND status='assigned'",[o.id]);
   }else await db.query('UPDATE service_orders SET cleaner_id=$2,updated_at=NOW() WHERE id=$1',[o.id,m.toCleanerId]);
   await db.query("UPDATE order_offers SET status='expired' WHERE order_id=$1 AND cleaner_id=ANY($2::uuid[]) AND status='offered'",[o.id,[m.fromCleanerId,m.toCleanerId]]);
   await db.query('DELETE FROM chat_participants cp USING chats c WHERE cp.chat_id=c.id AND c.order_id=$1 AND cp.user_id=$2',[o.id,m.fromCleanerId]);
   await db.query('INSERT INTO chat_participants(chat_id,user_id) SELECT id,$2 FROM chats WHERE order_id=$1 ON CONFLICT DO NOTHING',[o.id,m.toCleanerId]);
   const comment=moves.length===2?'Администратор обменял заказы уборщиц':'Администратор передал заказ другой уборщице';
   await db.query('INSERT INTO order_status_history(order_id,old_status,new_status,actor_id,comment) VALUES($1,$2,$2,$3,$4)',[o.id,o.status,actorId,comment]);
   await db.query("INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload) VALUES($1,$2,'order',$3,$4::jsonb)",[actorId,moves.length===2?'order.cleaners_swapped':'order.transferred',o.id,JSON.stringify(m)]);
   for(const [userId,title,body] of [[m.fromCleanerId,'Заказ передан','Ваш заказ передан другой уборщице.'],[m.toCleanerId,'Вам передан заказ','Администратор назначил вам заказ. Проверьте дату и время.'],[o.customer_id,'Изменился исполнитель','На вашу уборку назначена другая уборщица. Дата и время сохранены.']])
    await notifications.create({userId,titleRu:title,bodyRu:`${body} Заказ №${o.numeric_id}, ${o.service_date}, ${String(o.start_time).slice(0,5)}.`,targetType:'order',targetId:o.id});
  }
  return {changed:true,orders:items.map(i=>i.order.id)};
 });
}
