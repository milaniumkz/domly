import {refreshPackageUsage} from './packageUsage';
import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';

/** freeze_until is the first available date, so seven days extend expiry by seven days. */
export async function freezePackage(db: Database, userId: string, packageId: string, input: {days?: unknown; until?: unknown}) {
  return db.atomic(async () => {
    const tx=db;
    const setting = (await tx.query("SELECT value FROM app_settings WHERE key='maxPackageFreezeDays'")).rows[0];
    let days = typeof input.days === 'number' ? input.days : Number.NaN;
    if (input.until !== undefined) {
      if (typeof input.until !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(input.until) || !Number.isFinite(Date.parse(input.until)) || new Date(input.until).toISOString().slice(0,10)!==input.until) {
        throw new ApiError(400,'invalid_freeze','Проверьте срок заморозки.');
      }
      days = Number((await tx.query('SELECT $1::date-CURRENT_DATE AS days',[input.until])).rows[0].days);
    }
    if (!Number.isInteger(days) || days < 1 || days > Number(setting?.value ?? 30)) throw new ApiError(400,'invalid_freeze','Проверьте срок заморозки.');
    const pkg = (await tx.query("SELECT * FROM customer_packages WHERE id=$1 AND customer_id=$2 AND status='active' FOR UPDATE",[packageId,userId])).rows[0];
    if (!pkg) throw new ApiError(404,'package_not_found','Активный пакет не найден.');
    const usage=await refreshPackageUsage(db,packageId);
    if(usage.pkg?.status!=='active')throw new ApiError(400,'package_period_expired','Срок пакета истёк.');
    const before=(await tx.query('SELECT period_start,period_end,months FROM customer_packages WHERE id=$1',[packageId])).rows[0];
    const booking = (await tx.query(`SELECT id FROM service_orders WHERE customer_package_id=$1
      AND scheduled_date>=CURRENT_DATE AND scheduled_date<CURRENT_DATE+$2::int
      AND status NOT IN ('cancelled','canceled','completed') LIMIT 1`,[packageId,days])).rows[0];
    if (booking) throw new ApiError(409,'freeze_has_bookings','Сначала перенесите или отмените уборки на период заморозки.');
    const updated = (await tx.query(`UPDATE customer_packages SET
      period_end=COALESCE(period_end,(period_start+make_interval(months=>months))::date)
        +(CURRENT_DATE+$2::int-GREATEST(CURRENT_DATE,COALESCE(freeze_until,CURRENT_DATE))),
      freeze_until=CURRENT_DATE+$2::int,updated_at=NOW()
      WHERE id=$1 RETURNING *`,[packageId,days])).rows[0];
    const extension = Number((await tx.query(`SELECT ($1::date-COALESCE($2::date,($3::date+make_interval(months=>$4::int))::date)) AS days`,
      [updated.period_end,before.period_end,before.period_start,before.months])).rows[0].days);
    if(extension>0)await tx.query(`UPDATE customer_package_periods SET
      starts_at=CASE WHEN starts_at>NOW() THEN starts_at+($2::int*INTERVAL '1 day') ELSE starts_at END,
      ends_at=ends_at+($2::int*INTERVAL '1 day') WHERE customer_package_id=$1 AND ends_at>NOW()`,[packageId,extension]);
    return updated;
  });
}
