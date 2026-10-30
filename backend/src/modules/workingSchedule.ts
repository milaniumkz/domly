import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';

const dayMs=86400000;
export function workingScheduleWeeks(now=Date.now()) {
  const local=new Date(now+5*3600000);
  const day=new Date(local.toISOString().slice(0,10)+'T00:00:00Z');
  const offset=(day.getUTCDay()+6)%7;
  const monday=new Date(day.getTime()-offset*dayMs);
  return {today:day.toISOString().slice(0,10),currentWeekStart:monday.toISOString().slice(0,10),
    nextWeekStart:new Date(monday.getTime()+7*dayMs).toISOString().slice(0,10)};
}
export function workWeekDates(week:string) {
  return Array.from({length:7},(_,i)=>new Date(Date.parse(week+'T00:00:00Z')+i*dayMs).toISOString().slice(0,10));
}
export function normalizeWorkSchedule(input:any,now=Date.now()) {
  const weeks=workingScheduleWeeks(now),week=String(input.weekStart??'');
  if(![weeks.currentWeekStart,weeks.nextWeekStart].includes(week))throw new ApiError(400,'invalid_work_week','Настроить можно текущую и следующую недели.');
  const dates=workWeekDates(week);
  if(!Array.isArray(input.days)||input.days.length!==7)throw new ApiError(400,'invalid_work_days','Укажите режим работы на каждый из семи дней.');
  const seen=new Set<string>();
  const days=input.days.map((day:any)=>{
    const date=String(day.date??'');
    if(!dates.includes(date)||seen.has(date)||typeof day.working!=='boolean')throw new ApiError(400,'invalid_work_days','Проверьте даты графика.');
    seen.add(date);
    if(!day.working)return {date,working:false};
    const start=String(day.startTime??''),end=String(day.endTime??'');
    const clock=/^([01]\d|2[0-3]):[0-5]\d$/;
    if(!clock.test(start)||!clock.test(end)||end<=start)throw new ApiError(400,'invalid_work_time','Время окончания работы должно быть позже начала.');
    return {date,working:true,startTime:start,endTime:end};
  }).sort((a:any,b:any)=>a.date.localeCompare(b.date));
  const key=input.clientRequestId===undefined?null:String(input.clientRequestId);
  if(key!==null&&(!key||key.length>160))throw new ApiError(400,'invalid_request_key','Обновите окно графика.');
  return {week,days,key};
}
/** Only the appointment's start must be inside the approved interval. */
export function approvedWorkStartSql(cleaner:string,date:string,start:string) {
  return `EXISTS(SELECT 1 FROM cleaner_working_days wd JOIN cleaner_work_schedule_requests wr ON wr.id=wd.request_id
    WHERE wr.status='approved' AND wd.cleaner_id=${cleaner} AND wd.work_date=(${date})::date
      AND wd.start_time<=(${start})::time AND wd.end_time>=(${start})::time)`;
}
export async function readWorkingSchedule(db:Database,cleanerId:string) {
  const weeks=workingScheduleWeeks();
  const requests=(await db.query(`SELECT * FROM cleaner_work_schedule_requests WHERE cleaner_id=$1 AND week_start IN ($2::date,$3::date)
    ORDER BY created_at DESC,id DESC`,[cleanerId,weeks.currentWeekStart,weeks.nextWeekStart])).rows;
  const approved=(await db.query(`SELECT wd.* FROM cleaner_working_days wd JOIN cleaner_work_schedule_requests wr ON wr.id=wd.request_id
    WHERE wd.cleaner_id=$1 AND wr.status='approved' AND wd.work_date>=$2::date AND wd.work_date<$2::date+14 ORDER BY wd.work_date`,[cleanerId,weeks.currentWeekStart])).rows;
  return {...weeks,requests,approved};
}
export async function submitWorkingSchedule(db:Database,cleanerId:string,input:any) {
  const {week,days,key}=normalizeWorkSchedule(input);
  return db.atomic(async()=>{
    await db.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[cleanerId]);
    if(key){const previous=(await db.query('SELECT * FROM cleaner_work_schedule_requests WHERE cleaner_id=$1 AND client_request_id=$2',[cleanerId,key])).rows[0];if(previous)return previous;}
    // Different request keys and concurrent devices must not duplicate an unchanged week.
    const unchanged=(await db.query(`SELECT * FROM cleaner_work_schedule_requests
      WHERE cleaner_id=$1 AND week_start=$2 AND status IN ('pending','approved') AND days=$3::jsonb
      ORDER BY created_at DESC,id DESC LIMIT 1`,[cleanerId,week,JSON.stringify(days)])).rows[0];
    if(unchanged)return unchanged;
    // A revised week waits for approval; its previous version no longer sends offers.
    await db.query("UPDATE cleaner_work_schedule_requests SET status='superseded' WHERE cleaner_id=$1 AND week_start=$2 AND status IN ('pending','approved')",[cleanerId,week]);
    const saved=(await db.query(`INSERT INTO cleaner_work_schedule_requests(cleaner_id,week_start,days,client_request_id)
      VALUES($1,$2,$3::jsonb,$4) RETURNING *`,[cleanerId,week,JSON.stringify(days),key])).rows[0];
    await db.query(`UPDATE order_offers f SET expires_at=NOW() FROM service_orders o WHERE o.id=f.order_id AND f.cleaner_id=$1
      AND f.status='offered' AND o.scheduled_date>=$2::date AND o.scheduled_date<$2::date+7`,[cleanerId,week]);
    await db.query(`INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload)
      VALUES($1,'work_schedule.submitted','work_schedule',$2,$3::jsonb)`,[cleanerId,saved.id,JSON.stringify({weekStart:week})]);
    return saved;
  });
}
export async function reviewWorkingSchedule(db:Database,id:string,actorId:string,decision:string,comment='') {
  if(!['approved','rejected'].includes(decision))throw new ApiError(400,'invalid_review','Выберите одобрить или отклонить.');
  if(comment.length>2000)throw new ApiError(400,'invalid_review','Сократите комментарий.');
  return db.atomic(async()=>{
    const owner=(await db.query('SELECT cleaner_id FROM cleaner_work_schedule_requests WHERE id=$1',[id])).rows[0];
    if(!owner)throw new ApiError(404,'not_found','График не найден.');
    await db.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[owner.cleaner_id]);
    const request=(await db.query('SELECT * FROM cleaner_work_schedule_requests WHERE id=$1 FOR UPDATE',[id])).rows[0];
    if(request.status===decision)return request;
    if(request.status!=='pending')throw new ApiError(409,'schedule_changed','График уже рассмотрен или заменён новой заявкой.');
    if(decision==='approved'){
      const {currentWeekStart,today}=workingScheduleWeeks();
      const week=String(request.week_start instanceof Date?request.week_start.toISOString().slice(0,10):request.week_start).slice(0,10);
      if(week<currentWeekStart)throw new ApiError(409,'schedule_expired','Эта неделя уже закончилась.');
      await db.query('DELETE FROM cleaner_working_days WHERE cleaner_id=$1 AND work_date>=GREATEST($2::date,$3::date) AND work_date<$2::date+7',[request.cleaner_id,week,today]);
      for(const day of request.days){
        if(day.working&&day.date>=today)await db.query(`INSERT INTO cleaner_working_days(cleaner_id,work_date,start_time,end_time,request_id)
          VALUES($1,$2,$3,$4,$5) ON CONFLICT(cleaner_id,work_date) DO UPDATE SET start_time=EXCLUDED.start_time,end_time=EXCLUDED.end_time,request_id=EXCLUDED.request_id`,
          [request.cleaner_id,day.date,day.startTime,day.endTime,id]);
      }
    }
    const saved=(await db.query(`UPDATE cleaner_work_schedule_requests SET status=$2,review_comment=$3,reviewed_by=$4,reviewed_at=NOW() WHERE id=$1 RETURNING *`,[id,decision,comment,actorId])).rows[0];
    await db.query(`INSERT INTO audit_logs(actor_id,action,entity_type,entity_id,payload)
      VALUES($1,$2,'work_schedule',$3,$4::jsonb)`,[actorId,'work_schedule.'+decision,id,JSON.stringify({weekStart:request.week_start})]);
    return saved;
  });
}
