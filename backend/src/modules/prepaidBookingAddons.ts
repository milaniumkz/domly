import {Queryable} from '../domain/repositories/UnitOfWork';

/** Fixed prepaid extras belong to one visit; per-visit extras belong to every visit.
 * Call while holding the package lock when booking, so concurrent visits cannot
 * consume the same fixed extra twice. Cancelled visits release their extras.
 */
export async function prepaidBookingAddons(db:Queryable,purchase:{id:string;purchase_config?:any}) {
  const prepaid=Array.isArray(purchase.purchase_config?.addons)?purchase.purchase_config.addons as any[]:[];
  const fixed=prepaid.filter(item=>item.pricingType!=='per_visit'&&/^[0-9a-f-]{36}$/i.test(String(item.id??''))).map(item=>item.id);
  if(!fixed.length)return prepaid;
  const used=(await db.query<{addon_id:string}>(`SELECT DISTINCT oa.addon_id FROM order_addons oa
    JOIN service_orders o ON o.id=oa.order_id WHERE o.customer_package_id=$1 AND oa.addon_id=ANY($2::uuid[])
      AND o.status NOT IN ('cancelled','canceled') AND oa.payment_status NOT IN ('cancelled','rejected','refunded')`,[purchase.id,fixed])).rows;
  const consumed=new Set(used.map(row=>row.addon_id));
  return prepaid.filter(item=>item.pricingType==='per_visit'||!consumed.has(item.id));
}
