import {cleanerAreaNorm,cleanerDailyAreaMaximum} from '../../modules/cleanerCapacity';
import {Router} from 'express';
import {auth} from '../../common/auth';
import {ApiError,asyncHandler,ok} from '../../common/api';
import {Database} from '../../infrastructure/db/Database';

export function calendarRange(query:Record<string,unknown>,now=Date.now()){
 const local=new Date(now+5*3600000),year=local.getUTCFullYear(),month=local.getUTCMonth();
 const from=String(query.from??new Date(Date.UTC(year,month,1)).toISOString().slice(0,10));
 const to=String(query.to??new Date(Date.UTC(year,month+1,0)).toISOString().slice(0,10));
 const valid=(value:string)=>Number(value.slice(0,4))>=2000&&Number(value.slice(0,4))<=2100&&/^\d{4}-\d{2}-\d{2}$/.test(value)&&Number.isFinite(Date.parse(value+'T00:00:00Z'))&&new Date(value+'T00:00:00Z').toISOString().slice(0,10)===value;
 if(!valid(from)||!valid(to)||from>to||(Date.parse(to)-Date.parse(from))/86400000>61)throw new ApiError(400,'invalid_calendar_range','Выберите период календаря не более 62 дней.');
 return {from,to,today:local.toISOString().slice(0,10)};
}

/** One consistent, read-only month snapshot; no arbitrary first-page limits. */
export function adminCalendarRouter(db:Database){
 const router=Router();
 router.get('/admin/calendar',auth(['admin','superadmin']),asyncHandler(async(req,res)=>{
  const range=calendarRange(req.query);
  const data=await db.transaction(async tx=>{
   await tx.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY');
   const orders=(await tx.query(`SELECT o.*,COALESCE(NULLIF(o.area,0),a.verified_area,a.area,0) AS area,o.scheduled_date::text AS service_date,
     cu.full_name AS customer_name,cu.phone AS customer_phone,
     a.city,a.settlement,a.street,a.house,a.apartment,a.entrance,a.verified_area,
     p.name_ru AS package_name_ru,cl.full_name AS cleaner_name,cl.phone AS cleaner_phone,
     COALESCE((SELECT jsonb_agg(jsonb_build_object('cleaner_id',m.cleaner_id,'name',u.full_name,'phone',u.phone,
       'status',m.status,'area',m.allocated_area,'slot',m.slot_number) ORDER BY m.slot_number)
       FROM order_team_members m LEFT JOIN app_users u ON u.id=m.cleaner_id WHERE m.order_id=o.id),'[]'::jsonb) AS team_members,
     COALESCE((SELECT jsonb_agg(jsonb_build_object('cleaner_id',f.cleaner_id,'name',u.full_name,'expires_at',f.expires_at))
       FROM order_offers f JOIN app_users u ON u.id=f.cleaner_id WHERE f.order_id=o.id AND f.status='offered' AND f.expires_at>NOW()),'[]'::jsonb) AS offers
     FROM service_orders o JOIN app_users cu ON cu.id=o.customer_id
     LEFT JOIN app_users cl ON cl.id=o.cleaner_id LEFT JOIN customer_addresses a ON a.id=o.address_id
     LEFT JOIN catalog_packages p ON p.id=o.package_id
     WHERE o.scheduled_date<=$2::date AND (o.scheduled_date>=$1::date OR cleaning_end_at(o.scheduled_date,o.start_time,o.end_time,o.estimated_duration_minutes)>$1::date) AND o.status<>'draft'
     ORDER BY o.scheduled_date,o.start_time,o.numeric_id,o.id`,[range.from,range.to])).rows;
   const assignments=(await tx.query(`SELECT w.id AS order_id,w.cleaner_id,w.area AS allocated_area,
     COALESCE(m.status,CASE WHEN w.status='completed' THEN 'completed' WHEN w.status='in_progress' THEN 'in_progress' ELSE 'accepted' END) AS member_status
     FROM cleaner_order_workloads w LEFT JOIN order_team_members m ON m.order_id=w.id AND m.cleaner_id=w.cleaner_id
     WHERE w.scheduled_date<=$2::date AND (w.scheduled_date>=$1::date OR cleaning_end_at(w.scheduled_date,w.start_time,w.end_time,w.estimated_duration_minutes)>$1::date) AND w.status<>'draft'
     ORDER BY w.cleaner_id,w.scheduled_date,w.start_time,w.id`,[range.from,range.to])).rows;
   const workingDays=(await tx.query(`SELECT wd.cleaner_id,wd.work_date::text AS service_date,
     LEFT(wd.start_time::text,5) AS start_time,LEFT(wd.end_time::text,5) AS end_time
     FROM cleaner_working_days wd JOIN cleaner_work_schedule_requests r ON r.id=wd.request_id AND r.status='approved'
     WHERE wd.work_date BETWEEN $1::date AND $2::date ORDER BY wd.work_date,wd.cleaner_id`,[range.from,range.to])).rows;
   const approvedWeeks=(await tx.query(`SELECT DISTINCT cleaner_id,week_start::text AS week_start
     FROM cleaner_work_schedule_requests WHERE status='approved' AND week_start<=$2::date AND week_start+6>=$1::date`,[range.from,range.to])).rows;
   const ids=[...new Set([...assignments,...workingDays].map(row=>row.cleaner_id))];
   const cleaners=(await tx.query(`SELECT u.id,u.full_name,u.phone,u.status,u.deleted_at,p.verification_status
     FROM app_users u LEFT JOIN cleaner_profiles p ON p.user_id=u.id
     WHERE u.role='cleaner' AND ((u.deleted_at IS NULL AND u.status='approved' AND p.verification_status='approved') OR u.id=ANY($1::uuid[]))
     ORDER BY COALESCE(NULLIF(u.full_name,''),u.phone),u.id`,[ids])).rows;
   return {...range,orders,assignments,workingDays,approvedWeeks,cleaners,areaNorm:cleanerAreaNorm,areaMaximum:cleanerDailyAreaMaximum,updatedAt:new Date().toISOString()};
  });
  res.set('Cache-Control','no-store');ok(res,data);
 }));
 return router;
}
