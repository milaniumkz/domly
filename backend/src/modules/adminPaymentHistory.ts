import {ApiError} from '../common/api';
import {Database} from '../infrastructure/db/Database';

/** A consistent snapshot of all tab counts and the requested visible prefix. */
export async function adminPaymentHistory(db: Database, query: Record<string, unknown>) {
  const tab = String(query.tab ?? 'all');
  const limit = query.limit === undefined ? 50 : Number(query.limit);
  const sort = String(query.sort ?? 'desc');
  if (!['all','waiting','paid','cancelled','errors'].includes(tab) ||
      !['asc','desc'].includes(sort) || !Number.isInteger(limit) || limit < 1 || limit > 2147483647) {
    throw new ApiError(400, 'invalid_request', 'Проверьте параметры списка платежей.');
  }
  const values: unknown[] = [tab, limit];
  const filters: string[] = [];
  for (const [key, comparison] of [['dateFrom','>='],['dateTo','<=']]) {
    if (!query[key]) continue;
    const date = new Date(String(query[key]));
    if (!Number.isFinite(date.getTime())) throw new ApiError(400,'invalid_request','Проверьте период платежей.');
    values.push(date.toISOString());
    filters.push(`p.created_at ${comparison} $${values.length}::timestamptz`);
  }
  if (String(query.search ?? '').trim()) {
    values.push('%'+String(query.search).trim()+'%');
    filters.push(`concat_ws(' ', p.id::text, p.numeric_id::text, p.order_id::text,
      p.status::text, p.amount::text, p.invoice_phone, p.payload::text,
      u.full_name, u.phone, o.numeric_id::text, pkg.name_ru, pkg.name_kk) ILIKE $${values.length}`);
  }
  const order = sort === 'asc' ? 'ASC' : 'DESC';
  const result = (await db.query(`
    WITH matching AS MATERIALIZED (
      SELECT p.id, p.created_at,
        CASE WHEN p.status::text IN ('paid','success','completed') THEN 'paid'
             WHEN p.status::text IN ('cancelled','canceled','expired','refunded') THEN 'cancelled'
             WHEN p.status::text IN ('failed','rejected','error') THEN 'errors'
             ELSE 'waiting' END AS payment_tab
      FROM payments p
      LEFT JOIN app_users u ON u.id=p.customer_id
      LEFT JOIN service_orders o ON o.id=p.order_id
      LEFT JOIN customer_packages cp ON cp.id=p.customer_package_id
      LEFT JOIN catalog_packages pkg ON pkg.id=COALESCE(cp.package_id,o.package_id)
      ${filters.length ? 'WHERE '+filters.join(' AND ') : ''}
    ), counts AS (
      SELECT count(*)::int AS "all",
        count(*) FILTER(WHERE payment_tab='waiting')::int AS waiting,
        count(*) FILTER(WHERE payment_tab='paid')::int AS paid,
        count(*) FILTER(WHERE payment_tab='cancelled')::int AS cancelled,
        count(*) FILTER(WHERE payment_tab='errors')::int AS errors FROM matching
    ), visible AS (
      SELECT id,created_at FROM matching WHERE $1='all' OR payment_tab=$1
      ORDER BY created_at ${order}, id ${order} LIMIT $2
    ), details AS (
      SELECT p.*, approver.full_name AS approved_by_name, u.full_name AS customer_name, u.phone AS customer_phone,
        o.numeric_id AS order_number, cp.id AS package_purchase_id, pkg.name_ru AS package_name_ru,
        ca.city, ca.settlement, ca.street, ca.house, ca.apartment, ca.area, ca.verified_area
      FROM visible v JOIN payments p ON p.id=v.id
      LEFT JOIN app_users u ON u.id=p.customer_id
      LEFT JOIN app_users approver ON approver.id=p.approved_by
      LEFT JOIN service_orders o ON o.id=p.order_id
      LEFT JOIN customer_packages cp ON cp.id=p.customer_package_id
      LEFT JOIN catalog_packages pkg ON pkg.id=COALESCE(cp.package_id,o.package_id)
      LEFT JOIN customer_addresses ca ON ca.id=COALESCE(cp.address_id,o.address_id)
    ) SELECT to_jsonb(counts) AS counts,
      COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.created_at ${order},d.id ${order}) FROM details d),'[]'::jsonb) AS items
    FROM counts`, values)).rows[0];
  return {...result, total: result.counts[tab]};
}
