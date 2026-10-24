import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';

/** freeze_until is the first available date, so seven days extend expiry by seven days. */
export async function freezePackage(db: Database, userId: string, packageId: string, input: {days?: unknown; until?: unknown}) {
  return db.transaction(async tx => {
    const setting = (await tx.query("SELECT value FROM app_settings WHERE key='maxPackageFreezeDays'")).rows[0];
    let days = typeof input.days === 'number' ? input.days : Number.NaN;
    if (input.until !== undefined) {
      if (typeof input.until !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(input.until) || !Number.isFinite(Date.parse(input.until)) || new Date(input.until).toISOString().slice(0,10)!==input.until) {
        throw new ApiError(400,'invalid_freeze','Проверьте срок заморозки.');
      }
      days = Number((await tx.query('SELECT $1::date-CURRENT_DATE AS days',[input.until])).rows[0].days);
    }
    if (!Number.isInteger(days) || days < 1 || days > Number(setting?.value ?? 30)) throw new ApiError(400,'invalid_freeze','Проверьте срок заморозки.');
    const pkg = (await tx.query("SELECT id FROM customer_packages WHERE id=$1 AND customer_id=$2 AND status='active' FOR UPDATE",[packageId,userId])).rows[0];
    if (!pkg) throw new ApiError(404,'package_not_found','Активный пакет не найден.');
    const booking = (await tx.query(`SELECT id FROM service_orders WHERE customer_package_id=$1
      AND scheduled_date>=CURRENT_DATE AND scheduled_date<CURRENT_DATE+$2::int
      AND status NOT IN ('cancelled','canceled','completed') LIMIT 1`,[packageId,days])).rows[0];
    if (booking) throw new ApiError(409,'freeze_has_bookings','Сначала перенесите или отмените уборки на период заморозки.');
    return (await tx.query(`UPDATE customer_packages SET
      period_end=COALESCE(period_end,(period_start+make_interval(months=>months))::date)
        +(CURRENT_DATE+$2::int-GREATEST(CURRENT_DATE,COALESCE(freeze_until,CURRENT_DATE))),
      freeze_until=CURRENT_DATE+$2::int,updated_at=NOW()
      WHERE id=$1 RETURNING *`,[packageId,days])).rows[0];
  });
}
