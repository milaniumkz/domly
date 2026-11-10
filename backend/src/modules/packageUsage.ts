import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';
import type {NotificationService} from './domainServices';

const DAY = 86400000;
/** Add months from the original local payment instant, clamping month-end days. */
export function paidMonthBoundary(paidAt: Date | string, offset: number): Date {
  const local = new Date(new Date(paidAt).getTime() + 5 * 3600000);
  const month = new Date(Date.UTC(local.getUTCFullYear(), local.getUTCMonth() + offset, 1));
  const lastDay = new Date(Date.UTC(month.getUTCFullYear(), month.getUTCMonth() + 1, 0)).getUTCDate();
  return new Date(Date.UTC(month.getUTCFullYear(), month.getUTCMonth(), Math.min(local.getUTCDate(), lastDay),
    local.getUTCHours(), local.getUTCMinutes(), local.getUTCSeconds(), local.getUTCMilliseconds()) - 5 * 3600000);
}

async function usageRows(db: Database, id: string) {
  const periods=(await db.query(`SELECT pp.*,COUNT(o.id)::int AS used FROM customer_package_periods pp
    LEFT JOIN service_orders o ON o.usage_period_id=pp.id AND o.status NOT IN ('cancelled','canceled')
    WHERE pp.customer_package_id=$1 GROUP BY pp.id ORDER BY pp.period_index`,[id])).rows;
  if(!periods.length)return periods;
  // Preserve the credit's expiry when an order is cancelled later. Never
  // reshuffle already allocated visits into another month's remaining credits.
  const pending=(await db.query(`SELECT id,scheduled_date::text AS date,start_time::text AS time FROM service_orders
    WHERE customer_package_id=$1 AND usage_period_id IS NULL AND status NOT IN ('cancelled','canceled')
    ORDER BY created_at,id`,[id])).rows;
  for(const order of pending){
    const at=bookingTimestamp(order.date,order.time??'00:00');
    const period=periods.find(p=>new Date(p.ends_at).getTime()>at&&(periods.length===3||at>=new Date(p.starts_at).getTime())&&remainingPeriodCleanings(p)>0);
    if(!period)continue; // Preserve incomplete legacy records without inventing credits.
    await db.query('UPDATE service_orders SET usage_period_id=$2 WHERE id=$1 AND usage_period_id IS NULL',[order.id,period.id]);
    period.used=Number(period.used)+1;
  }
  return periods;
}
function bookingTimestamp(date:string,time:string){
  return Date.parse(`${date}T${time.length===5?time+':00':time}+05:00`);
}
/** Later monthly credits may be used early; expired credits may not be carried forward. */
export function packageBookingCapacity(periods:any[],date:string,time:string,ownPeriodId?:string|null):number{
  const at=bookingTimestamp(date,time);
  if(!periods.length||at<new Date(periods[0].starts_at).getTime()||at>=new Date(periods.at(-1).ends_at).getTime())return 0;
  return periods.filter(p=>at<new Date(p.ends_at).getTime()&&(periods.length===3||at>=new Date(p.starts_at).getTime())).reduce((sum,p)=>sum+remainingPeriodCleanings(p)+(p.id===ownPeriodId?1:0),0);
}
export function remainingPeriodCleanings(period: any): number {
  return Math.max(0,Number(period.quota)-Number(period.legacy_used)-Number(period.used)-Number(period.expired_cleanings));
}

/** The package lock serializes reservations, expiry, cancellation and retries. */
export async function refreshPackageUsage(db: Database, id: string, now = Date.now()) {
  return db.atomic(async()=>{
    const pkg=(await db.query('SELECT * FROM customer_packages WHERE id=$1 FOR UPDATE',[id])).rows[0];
    if(!pkg || !['active','expired'].includes(pkg.status))return {managed:false,periods:[],pkg};
    let periods=await usageRows(db,id);
    if(!periods.length){
      const paid=(await db.query(`SELECT COALESCE(paid_at,approved_at,created_at) AS paid_at FROM payments
        WHERE customer_package_id=$1 AND customer_id=$2 AND status='paid'
        ORDER BY COALESCE(paid_at,approved_at,created_at),id LIMIT 1`,[id,pkg.customer_id])).rows[0];
      // Do not invent a payment date for incomplete imported records.
      if(!paid)return {managed:false,periods:[],pkg};
      const months=Math.max(1,Math.min(120,Math.trunc(Number(pkg.months)||1)));
      const total=Math.max(0,Number(pkg.total_cleanings));
      const known=Number((await db.query(`SELECT COUNT(*)::int n FROM service_orders
        WHERE customer_package_id=$1 AND status NOT IN ('cancelled','canceled')`,[id])).rows[0].n);
      let legacy=Math.max(0,total-Number(pkg.available_cleanings)-known);
      // Preserve any extension granted by the existing freeze feature.
      const oldStart=new Date(pkg.period_start);
      const naturalOldEnd=paidMonthBoundary(oldStart,months).getTime();
      const extension=pkg.period_end?Math.max(0,new Date(pkg.period_end).getTime()-naturalOldEnd):0;
      for(let index=0;index<months;index++){
        const quota=Math.floor(total*(index+1)/months)-Math.floor(total*index/months);
        const start=paidMonthBoundary(paid.paid_at,index);
        const end=paidMonthBoundary(paid.paid_at,index+1);
        if(index>0)start.setTime(start.getTime()+extension);
        end.setTime(end.getTime()+extension);
        await db.query(`INSERT INTO customer_package_periods(customer_package_id,period_index,starts_at,ends_at,quota)
          VALUES($1,$2,$3,$4,$5) ON CONFLICT(customer_package_id,period_index) DO NOTHING`,[id,index,start,end,quota]);
      }
      periods=await usageRows(db,id);
      for(const period of periods){
        const used=Math.min(legacy,Math.max(0,Number(period.quota)-Number(period.used)));
        if(used)await db.query('UPDATE customer_package_periods SET legacy_used=$2 WHERE id=$1',[period.id,used]);
        period.legacy_used=used;legacy-=used;
      }
      await db.query(`UPDATE customer_packages SET period_start=($2::timestamptz AT TIME ZONE 'Asia/Almaty')::date,
        period_end=($3::timestamptz AT TIME ZONE 'Asia/Almaty')::date WHERE id=$1`,[id,periods[0].starts_at,periods.at(-1)!.ends_at]);
    }
    for(const period of periods){
      if(new Date(period.ends_at).getTime()>now)continue;
      const expired=Math.min(Math.max(0,Number(pkg.available_cleanings)),remainingPeriodCleanings(period));
      if(expired){
        await db.query('UPDATE customer_package_periods SET expired_cleanings=expired_cleanings+$2 WHERE id=$1',[period.id,expired]);
        await db.query('UPDATE customer_packages SET available_cleanings=available_cleanings-$2,updated_at=NOW() WHERE id=$1',[id,expired]);
        await db.query(`INSERT INTO audit_logs(action,entity_type,entity_id,payload)
          VALUES('package.month_expired','customer_package',$1,$2)`,[id,{periodId:period.id,periodIndex:period.period_index,expiredCleanings:expired,endsAt:period.ends_at}]);
        period.expired_cleanings=Number(period.expired_cleanings)+expired;
        pkg.available_cleanings=Number(pkg.available_cleanings)-expired;
      }
    }
    if(new Date(periods.at(-1)!.ends_at).getTime()<=now && pkg.status==='active'){
      await db.query("UPDATE customer_packages SET status='expired',updated_at=NOW() WHERE id=$1",[id]);pkg.status='expired';
    }
    return {managed:true,periods,pkg};
  });
}

export function bookingPeriod(periods:any[],date:string,time:string){
  const at=Date.parse(`${date}T${time.length===5?time+':00':time}+05:00`);
  return periods.find(p=>at>=new Date(p.starts_at).getTime()&&at<new Date(p.ends_at).getTime());
}
export async function validatePackagePeriod(db:Database,id:string,date:string,time:string,excludeOrderId?:string,now=Date.now()){
  const state=await refreshPackageUsage(db,id,now);
  if(!state.managed)return state;
  const period=bookingPeriod(state.periods,date,time);
  if(!period||new Date(period.ends_at).getTime()<=now)throw new ApiError(400,'package_period_expired','Выберите дату в пределах срока пакета. Остаток за прошедший месяц не переносится.');
  const own=excludeOrderId?(await db.query("SELECT usage_period_id FROM service_orders WHERE id=$1 AND customer_package_id=$2 AND status NOT IN ('cancelled','canceled')",[excludeOrderId,id])).rows[0]:null;
  if(packageBookingCapacity(state.periods,date,time,own?.usage_period_id)<=0)throw new ApiError(400,'package_cleanings_used','На выбранную дату не осталось уборок в пакете. Выберите более раннюю дату или купите дополнительный пакет.');
  return state;
}

export async function processPackageUsage(db:Database,notifications:Pick<NotificationService,'create'>,now=Date.now()){
  let cursor='00000000-0000-0000-0000-000000000000';
  for(;;){
    const rows=(await db.query(`SELECT cp.id,u.deleted_at FROM customer_packages cp JOIN app_users u ON u.id=cp.customer_id
      WHERE cp.id>$1 AND cp.status='active'
      AND EXISTS(SELECT 1 FROM payments p WHERE p.customer_package_id=cp.id AND p.status='paid')
      ORDER BY cp.id LIMIT 100`,[cursor])).rows;
    if(!rows.length)break;
    for(const row of rows){
      if(row.deleted_at)await refreshPackageUsage(db,row.id,now);
      else await processPackageUsageForPackage(db,notifications,row.id,now);
    }
    cursor=rows.at(-1)!.id;
  }
}


export async function processPackageUsageForPackage(db:Database,notifications:Pick<NotificationService,'create'>,id:string,now=Date.now()){
  return db.atomic(async()=>{
    const state=await refreshPackageUsage(db,id,now);
      for(const period of state.periods){
        const remaining=remainingPeriodCleanings(period);
        const days=Math.ceil((new Date(period.ends_at).getTime()-now)/DAY);
        if(!remaining||![7,3,1].includes(days))continue;
        const until=new Date(new Date(period.ends_at).getTime()+5*3600000).toISOString().slice(0,16).replace('T',' ');
        await notifications.create({userId:state.pkg.customer_id,titleRu:'Уборки скоро сгорят',titleKk:'Тазалаулардың мерзімі жақында аяқталады',
          bodyRu:`До окончания месяца пакета осталось ${days} дн. Неиспользованных уборок: ${remaining}. Успейте использовать их до ${until}. Они не переносятся на следующий месяц.`,
          bodyKk:`Пакет айының аяқталуына ${days} күн қалды. Пайдаланылмаған тазалаулар: ${remaining}. Оларды ${until} дейін пайдаланыңыз. Олар келесі айға көшірілмейді.`,
          targetType:'package',targetId:id,dedupeKey:`package-period-${period.id}-${new Date(period.ends_at).getTime()}-reminder-${days}`});
      }
  });
}
