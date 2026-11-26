import {Router} from 'express';
import {auth} from '../../common/auth';
import {ApiError,asyncHandler,ok} from '../../common/api';
import {Database} from '../../infrastructure/db/Database';

export function workloadRange(query:Record<string,unknown>,now=Date.now()){
 const local=new Date(now+5*3600000);
 const to=String(query.to??local.toISOString().slice(0,10));
 const from=String(query.from??new Date(Date.UTC(local.getUTCFullYear(),local.getUTCMonth(),1)).toISOString().slice(0,10));
 const valid=(v:string)=>/^\d{4}-\d{2}-\d{2}$/.test(v)&&v>='2000-01-01'&&v<='2100-12-31'&&Number.isFinite(Date.parse(v+'T00:00:00Z'))&&new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v;
 if(!valid(from)||!valid(to)||from>to||(Date.parse(to)-Date.parse(from))/86400000>3660)throw new ApiError(400,'invalid_workload_range','Укажите корректный период не более 10 лет.');
 return {from,to};
}
export function cleanerWorkloadRouter(db:Database){
 const router=Router();
 router.get('/admin/cleaner-workload',auth(['admin','superadmin']),asyncHandler(async(req,res)=>{
  const range=workloadRange(req.query);
  const rows=(await db.query(`WITH completed AS (
    SELECT o.id,o.cleaner_id,COALESCE(NULLIF(o.area,0),a.verified_area,a.area,0) AS area,
      o.started_at,o.completed_at,o.scheduled_date
    FROM service_orders o LEFT JOIN customer_addresses a ON a.id=o.address_id
    WHERE o.status='completed' AND o.cleaner_id IS NOT NULL
      AND NOT EXISTS(SELECT 1 FROM order_team_members m WHERE m.order_id=o.id)
    UNION ALL
    SELECT o.id,m.cleaner_id,m.allocated_area,m.started_at,m.completed_at,o.scheduled_date
    FROM order_team_members m JOIN service_orders o ON o.id=m.order_id
    WHERE m.status='completed' AND m.cleaner_id IS NOT NULL AND o.status NOT IN ('cancelled','canceled','draft')
   ), totals AS (
    SELECT cleaner_id,COUNT(*)::int AS completed_count,COALESCE(SUM(area),0) AS cleaned_area,
      COALESCE(SUM(CASE WHEN started_at IS NOT NULL AND completed_at>=started_at
        THEN EXTRACT(EPOCH FROM completed_at-started_at)/60 ELSE 0 END),0) AS actual_minutes,
      COUNT(*) FILTER(WHERE started_at IS NULL OR completed_at IS NULL OR completed_at<started_at)::int AS missing_time_count
    FROM completed WHERE COALESCE((completed_at AT TIME ZONE 'Asia/Almaty')::date,scheduled_date) BETWEEN $1::date AND $2::date
    GROUP BY cleaner_id
   ) SELECT u.id,u.full_name,COALESCE(t.completed_count,0) AS completed_count,COALESCE(t.cleaned_area,0) AS cleaned_area,
     COALESCE(t.actual_minutes,0) AS actual_minutes,COALESCE(t.missing_time_count,0) AS missing_time_count
    FROM app_users u LEFT JOIN totals t ON t.cleaner_id=u.id
    WHERE u.role='cleaner' AND (u.deleted_at IS NULL OR t.cleaner_id IS NOT NULL)
    ORDER BY COALESCE(u.full_name,''),u.id`,[range.from,range.to])).rows;
  res.set('Cache-Control','no-store');ok(res,{...range,cleaners:rows});
 }));
 return router;
}
