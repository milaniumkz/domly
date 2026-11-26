import {durationAfterAddonChange} from './cleaningDuration';
import { ApiError } from '../common/api';
import { Queryable } from '../domain/repositories/UnitOfWork';

export const maxCleanerDailyArea = 250;
export interface CleaningTeamPlan {
  cleanerIds: string[];
  requiredCleaners: number;
  durationMinutes: number;
  laborMinutes: number;
  areaShares: number[];
  endTime: string;
}

// Split integer minor units so neither area nor remuneration is created by rounding.
export function equalShares(total: number, members: number): number[] {
  if (!Number.isFinite(total) || total < 0 || !Number.isSafeInteger(members) || members < 1) throw new Error('Invalid team allocation');
  const units = Math.round(total * 100);
  if (!Number.isSafeInteger(units)) throw new Error('Allocation is too large');
  return Array.from({length: members}, (_, i) => (Math.floor(units / members) + (i < units % members ? 1 : 0)) / 100);
}

export function minimumTeamSize(area: number): number {
  if (!Number.isFinite(area) || area <= 0) throw new ApiError(400, 'invalid_area', 'Укажите площадь недвижимости.');
  return Math.max(1, Math.ceil(area / maxCleanerDailyArea));
}

export function teamEndTime(start: string, minutes: number): string {
  const match = /^(\d{2}):(\d{2})(?::\d{2})?$/.exec(start);
  if (!match || Number(match[1]) > 23 || Number(match[2]) > 59 || !Number.isSafeInteger(minutes) || minutes < 1) throw new ApiError(400, 'invalid_order_time', 'Проверьте время уборки.');
  const end = (Number(match[1]) * 60 + Number(match[2]) + minutes) % 1440;
  return `${String(Math.floor(end / 60)).padStart(2, '0')}:${String(end % 60).padStart(2, '0')}`;
}

// Every candidate works the whole parallel interval. The largest rounded area
// share is checked for everyone; no participant can exceed the daily 250 m² cap.
export async function planCleaningTeam(db: Queryable, input: {
  date: string; startTime: string; area: number; laborMinutes: number;
  expandForTime?: boolean; excludeOrderId?: string; zoneId?: string;
  requiredCleanerIds?: string[];
}): Promise<CleaningTeamPlan | null> {
  const minimum = minimumTeamSize(input.area);
  if (!Number.isSafeInteger(input.laborMinutes) || input.laborMinutes < 1) throw new ApiError(400, 'invalid_duration', 'Проверьте длительность уборки.');
  const rows = (await db.query<{size: number; ids: string[]}>(`
    WITH eligible AS MATERIALIZED (
      SELECT u.id, u.created_at FROM app_users u
      JOIN cleaner_profiles cp ON cp.user_id=u.id
      WHERE u.role='cleaner' AND u.status='approved' AND cp.verification_status='approved'
        AND ($8::uuid IS NULL OR EXISTS(SELECT 1 FROM cleaner_zones cz WHERE cz.cleaner_id=u.id AND cz.zone_id=$8))
    ), sizes AS (
      SELECT generate_series($6::int, CASE WHEN $7::boolean THEN (SELECT COUNT(*)::int FROM eligible) ELSE $6::int END) AS size
    )
    SELECT sizes.size, candidates.ids FROM sizes CROSS JOIN LATERAL (
      SELECT array_agg(c.id ORDER BY c.created_at,c.id) AS ids, MAX(c.eligible_count) AS free_count FROM (
        SELECT e.*,COUNT(*) OVER() AS eligible_count FROM eligible e
        WHERE domly_cleaner_slot_allowed(e.id,$1::date,$2::time,
          ($2::time+CEIL($4::numeric/sizes.size)*INTERVAL '1 minute')::time,
          CEIL($4::numeric/sizes.size)::int,CEIL($3::numeric*100/sizes.size)/100,$5::uuid)
        AND NOT EXISTS(SELECT 1 FROM order_offers f JOIN service_orders prior ON prior.id=f.order_id
          WHERE f.cleaner_id=e.id AND f.status='offered' AND f.expires_at>NOW() AND prior.cleaner_id IS NULL
            AND prior.status IN ('pending_assignment','waiting_cleaner') AND prior.payable_amount<=0
            AND prior.scheduled_date=$1::date AND ($5::uuid IS NULL OR prior.id<>$5)
            AND NOT EXISTS(SELECT 1 FROM order_team_members tm WHERE tm.order_id=prior.id))
        AND NOT EXISTS(SELECT 1 FROM cleaner_order_workloads w WHERE w.cleaner_id=e.id
          AND ($5::uuid IS NULL OR w.id<>$5) AND w.status NOT IN ('cancelled','completed','draft')
          AND w.scheduled_date+w.start_time<$1::date+$2::time+CEIL($4::numeric/sizes.size)*INTERVAL '1 minute'
          AND cleaning_end_at(w.scheduled_date,w.start_time,w.end_time,w.estimated_duration_minutes)>$1::date+$2::time)
        ORDER BY (e.id=ANY($9::uuid[])) DESC,e.created_at,e.id LIMIT sizes.size
      ) c
    ) candidates
    WHERE cardinality(candidates.ids)=sizes.size
      AND candidates.free_count >= sizes.size + (SELECT COUNT(*) FROM service_orders pending
        WHERE pending.cleaner_id IS NULL AND pending.status IN ('pending_payment','pending_assignment','waiting_cleaner')
          AND ($5::uuid IS NULL OR pending.id<>$5)
          AND NOT EXISTS(SELECT 1 FROM order_team_members tm WHERE tm.order_id=pending.id)
          AND NOT EXISTS(SELECT 1 FROM order_offers f WHERE f.order_id=pending.id AND f.status='offered' AND f.expires_at>NOW() AND pending.payable_amount<=0)
          AND pending.scheduled_date+pending.start_time<$1::date+$2::time+(CEIL($4::numeric/sizes.size)+GREATEST(domly_cleaner_gap_minutes(pending.scheduled_date),domly_cleaner_gap_minutes($1::date)))*INTERVAL '1 minute'
          AND cleaning_end_at(pending.scheduled_date,pending.start_time,pending.end_time,pending.estimated_duration_minutes)+GREATEST(domly_cleaner_gap_minutes(pending.scheduled_date),domly_cleaner_gap_minutes($1::date))*INTERVAL '1 minute'>$1::date+$2::time)
      AND $9::uuid[] <@ candidates.ids
    ORDER BY sizes.size LIMIT 1`,
    [input.date,input.startTime,input.area,input.laborMinutes,input.excludeOrderId??null,minimum,input.expandForTime===true,input.zoneId??null,input.requiredCleanerIds??[]])).rows;
  if (!rows.length) return null;
  const size = Number(rows[0].size), durationMinutes = Math.ceil(input.laborMinutes / size);
  return {cleanerIds: rows[0].ids, requiredCleaners:size, durationMinutes, laborMinutes:input.laborMinutes,
    areaShares:equalShares(input.area,size), endTime:teamEndTime(input.startTime,durationMinutes)};
}

export async function reserveCleaningTeam(db: Queryable, orderId: string, plan: CleaningTeamPlan): Promise<void> {
  for (let slot = 0; slot < plan.requiredCleaners; slot++) await db.query(`INSERT INTO order_team_members(order_id,cleaner_id,slot_number,allocated_area) VALUES($1,$2,$3,$4)`,[orderId,plan.cleanerIds[slot],slot,plan.areaShares[slot]]);
  await db.query(`UPDATE service_orders SET required_cleaners=$2,labor_duration_minutes=$3,estimated_duration_minutes=$4,end_time=$5 WHERE id=$1`,[orderId,plan.requiredCleaners,plan.laborMinutes,plan.durationMinutes,plan.endTime]);
}

export async function teamOffers(db: Queryable, order: any, exclude: string[], ttl: number) {
  const members = (await db.query<any>('SELECT * FROM order_team_members WHERE order_id=$1 ORDER BY slot_number FOR UPDATE',[order.id])).rows;
  if (!members.length) return undefined;
  if (Number(order.payable_amount)>0 || !['pending_assignment','waiting_cleaner'].includes(order.status)) return null;
  for (const member of members) {
    if (['accepted','in_progress','completed'].includes(member.status)) continue;
    const prior=(await db.query(`SELECT * FROM order_offers WHERE order_id=$1 AND cleaner_id=$2`,[order.id,member.cleaner_id])).rows[0];
    if (prior?.status==='offered' && new Date(prior.expires_at).getTime()>Date.now()) continue;
    if (prior) {
      await db.query("UPDATE order_team_members SET cleaner_id=NULL,status='reserved',accepted_at=NULL,updated_at=NOW() WHERE id=$1",[member.id]);
      member.cleaner_id=null;
    }
    if (!member.cleaner_id) {
      const candidate=(await db.query<any>(`SELECT u.id FROM app_users u JOIN cleaner_profiles cp ON cp.user_id=u.id
        WHERE u.role='cleaner' AND u.status='approved' AND cp.verification_status='approved'
          AND NOT(u.id=ANY($7::uuid[])) AND NOT EXISTS(SELECT 1 FROM order_team_members m WHERE m.order_id=$1 AND m.cleaner_id=u.id)
          AND domly_cleaner_slot_allowed(u.id,$2::date,$3::time,$4::time,$5::int,$6::numeric,$1::uuid)
          AND NOT EXISTS(SELECT 1 FROM cleaner_order_workloads w WHERE w.cleaner_id=u.id AND w.id<>$1 AND w.status NOT IN ('cancelled','completed','draft')
            AND w.scheduled_date+w.start_time<cleaning_end_at($2::date,$3::time,$4::time,$5::int)
            AND cleaning_end_at(w.scheduled_date,w.start_time,w.end_time,w.estimated_duration_minutes)>$2::date+$3::time)
        ORDER BY u.created_at,u.id LIMIT 1`,[order.id,order.scheduled_date,order.start_time,order.end_time,order.estimated_duration_minutes,member.allocated_area,exclude])).rows[0];
      if (!candidate) continue;
      member.cleaner_id=candidate.id;
      await db.query("UPDATE order_team_members SET cleaner_id=$2,updated_at=NOW() WHERE id=$1",[member.id,candidate.id]);
    }
    await db.query(`INSERT INTO order_offers(order_id,cleaner_id,status,expires_at) VALUES($1,$2,'offered',NOW()+$3::int*INTERVAL '1 minute')
      ON CONFLICT(order_id,cleaner_id) DO UPDATE SET status='offered',expires_at=EXCLUDED.expires_at,created_at=NOW()`,[order.id,member.cleaner_id,Math.max(1,Math.round(ttl))]);
    await db.query("UPDATE order_team_members SET status='offered',updated_at=NOW() WHERE id=$1",[member.id]);
  }
  const offers=(await db.query<any>(`SELECT f.* FROM order_offers f JOIN order_team_members m ON m.order_id=f.order_id AND m.cleaner_id=f.cleaner_id
    WHERE f.order_id=$1 AND f.status='offered' AND f.expires_at>NOW() ORDER BY m.slot_number`,[order.id])).rows;
  return offers.length ? {...offers[0],teamOffers:offers} : null;
}

export async function assignTeamMember(db:Queryable,order:any,cleanerId:string,actorId:string,slotNumber?:number){
 const members=(await db.query<any>('SELECT * FROM order_team_members WHERE order_id=$1 ORDER BY slot_number FOR UPDATE',[order.id])).rows;
 if(!members.length)return undefined;
 const actor=(await db.query('SELECT role FROM app_users WHERE id=$1',[actorId])).rows[0];
 if(!['admin','superadmin'].includes(actor?.role))throw new ApiError(403,'forbidden','Назначать участников команды может только администратор.');
 const member=slotNumber===undefined?members.find(m=>!m.cleaner_id)??members.find(m=>m.status!=='accepted')??members[0]:members.find(m=>m.slot_number===slotNumber);
 if(!member)throw new ApiError(400,'invalid_team_slot','Выберите участника команды для замены.');
 if(member.cleaner_id===cleanerId&&member.status==='accepted')return {order,changed:false};
 if(members.some(m=>m.id!==member.id&&m.cleaner_id===cleanerId))throw new ApiError(409,'already_in_team','Этот клинер уже входит в команду.');
 const allowed=(await db.query(`SELECT 1 FROM app_users u JOIN cleaner_profiles p ON p.user_id=u.id WHERE u.id=$1 AND u.status='approved' AND p.verification_status='approved'
   AND domly_cleaner_slot_allowed($1::uuid,$2::date,$3::time,$4::time,$5::int,$6::numeric,$7::uuid)
   AND NOT EXISTS(SELECT 1 FROM cleaner_order_workloads w WHERE w.cleaner_id=$1 AND w.id<>$7 AND w.status NOT IN ('cancelled','completed','draft')
     AND w.scheduled_date+w.start_time<cleaning_end_at($2::date,$3::time,$4::time,$5::int)
     AND cleaning_end_at(w.scheduled_date,w.start_time,w.end_time,w.estimated_duration_minutes)>$2::date+$3::time)`,[cleanerId,order.scheduled_date,order.start_time,order.end_time,order.estimated_duration_minutes,member.allocated_area,order.id])).rows.length;
 if(!allowed)throw new ApiError(409,'cleaner_capacity_exceeded','Клинер занят, превышен лимит площади или время его смены.');
 await db.query("UPDATE order_offers SET status='expired' WHERE order_id=$1 AND cleaner_id=$2",[order.id,member.cleaner_id]);
 await db.query("UPDATE order_team_members SET cleaner_id=$2,status='accepted',accepted_at=NOW(),started_at=NULL,completed_at=NULL,updated_at=NOW() WHERE id=$1",[member.id,cleanerId]);
 if(member.cleaner_id)await db.query('DELETE FROM chat_participants cp USING chats c WHERE cp.chat_id=c.id AND c.order_id=$1 AND cp.user_id=$2',[order.id,member.cleaner_id]);
 await db.query('INSERT INTO chat_participants(chat_id,user_id) SELECT id,$2 FROM chats WHERE order_id=$1 ON CONFLICT DO NOTHING',[order.id,cleanerId]);
 const pending=(await db.query("SELECT id FROM order_team_members WHERE order_id=$1 AND status<>'accepted'",[order.id])).rows.length;
 const primary=pending?null:(await db.query('SELECT cleaner_id FROM order_team_members WHERE order_id=$1 ORDER BY slot_number LIMIT 1',[order.id])).rows[0].cleaner_id;
 const updated=(await db.query("UPDATE service_orders SET cleaner_id=$2,status=$3,updated_at=NOW() WHERE id=$1 RETURNING *",[order.id,primary,pending?'pending_assignment':'assigned'])).rows[0];
 await db.query("INSERT INTO order_status_history(order_id,old_status,new_status,actor_id,comment) VALUES($1,$2,$3,$4,'Администратор назначил участника команды')",[order.id,order.status,updated.status,actorId]);
 return {order:updated,changed:true};
}

/** Keep person-minutes and elapsed wall time separate when adding services. */
export function teamDurationAfterAddonChange(order:any,previous:number,next:number,remaining?:number){
 const size=Number(order.required_cleaners??1);
 const labor=Math.max(1,Number(order.labor_duration_minutes??Number(order.estimated_duration_minutes)*size)-previous+next);
 const working=Math.max(1,remaining??size),extra=Math.max(0,Math.ceil((next-previous)/working));
 const nominal=working===size?Math.ceil(labor/size):Math.max(1,Number(order.estimated_duration_minutes)+Math.ceil((next-previous)/working));
 return {labor,duration:Math.max(nominal,durationAfterAddonChange({...order,estimated_duration_minutes:nominal-extra},0,extra))};
}

export async function assertTeamInterval(db:Queryable,order:any,duration:number){
 const members=(await db.query<any>('SELECT * FROM order_team_members WHERE order_id=$1',[order.id])).rows;
 for(const member of members){
  if(!member.cleaner_id)throw new ApiError(409,'team_incomplete','Дождитесь назначения всей команды перед изменением услуг.');
  const allowed=(await db.query(`SELECT domly_cleaner_slot_allowed($1::uuid,$2::date,$3::time,$4::time,$5::int,$6::numeric,$7::uuid) AS allowed`,[member.cleaner_id,order.scheduled_date,order.start_time,teamEndTime(order.start_time,duration),duration,member.allocated_area,order.id])).rows[0]?.allowed;
  if(!allowed)throw new ApiError(409,'cleaner_capacity_exceeded','Для допуслуг недостаточно времени в графике команды.');
  const conflict=(await db.query(`SELECT id FROM cleaner_order_workloads WHERE cleaner_id=$1 AND id<>$2 AND status NOT IN ('cancelled','completed','draft')
    AND scheduled_date+start_time<$3::date+$4::time+$5::int*INTERVAL '1 minute'
    AND cleaning_end_at(scheduled_date,start_time,end_time,estimated_duration_minutes)>$3::date+$4::time LIMIT 1`,[member.cleaner_id,order.id,order.scheduled_date,order.start_time,duration])).rows.length;
  if(conflict)throw new ApiError(409,'cleaner_unavailable','Для допуслуг недостаточно времени до следующего заказа участника команды.');
 }
 return members;
}
