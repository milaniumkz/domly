import {Database} from '../infrastructure/db/Database';
import {ApiError} from '../common/api';

export async function adminCancelledSales(db:Database,query:Record<string,unknown>){
 const limit=Number(query.limit??30),offset=Number(query.offset??0),kind=String(query.kind??'all');
 if(!Number.isInteger(limit)||limit<1||limit>100||!Number.isInteger(offset)||offset<0||!['all','payment','order'].includes(kind))throw new ApiError(400,'invalid_request','Проверьте параметры списка отмен.');
 const values:unknown[]=[kind,limit,offset],filters=["($1='all' OR e.kind=$1)"];
 const search=String(query.search??'').trim();if(search){values.push('%'+search+'%');filters.push(`concat_ws(' ',u.full_name,u.phone,p.invoice_phone,p.numeric_id::text,o.numeric_id::text,pkg.name_ru,cp.purchase_config::text,ca.city,ca.street,ca.house,ca.apartment) ILIKE $${values.length}`);}
 for(const [key,op] of [['dateFrom','>='],['dateTo','<=']])if(query[key]){const d=new Date(String(query[key]));if(!Number.isFinite(d.getTime()))throw new ApiError(400,'invalid_request','Проверьте период.');values.push(d.toISOString());filters.push(`e.cancelled_at ${op} $${values.length}::timestamptz`);}
 const sort=query.sort==='asc'?'ASC':'DESC';
 const result=(await db.query(`WITH events AS (
  SELECT 'payment'::text kind,p.id,p.customer_id,p.order_id,p.customer_package_id,
   COALESCE(NULLIF(p.payload#>>'{kaspiCancellation,at}','')::timestamptz,p.updated_at) cancelled_at
  FROM payments p WHERE p.status='cancelled'
  UNION ALL
  SELECT 'order',o.id,o.customer_id,o.id,o.customer_package_id,
   COALESCE((SELECT MIN(h.created_at) FROM order_status_history h WHERE h.order_id=o.id AND h.new_status='cancelled'),o.updated_at)
  FROM service_orders o WHERE o.status='cancelled' 
 ), matching AS MATERIALIZED (
  SELECT e.*
  FROM events e LEFT JOIN payments p ON e.kind='payment' AND p.id=e.id
  LEFT JOIN service_orders o ON o.id=e.order_id
  LEFT JOIN customer_packages cp ON cp.id=COALESCE(e.customer_package_id,o.customer_package_id)
  LEFT JOIN app_users u ON u.id=e.customer_id LEFT JOIN app_users cl ON cl.id=o.cleaner_id
  LEFT JOIN catalog_packages pkg ON pkg.id=COALESCE(cp.package_id,o.package_id)
  LEFT JOIN customer_addresses ca ON ca.id=COALESCE(o.address_id,cp.address_id)
  WHERE ${filters.join(' AND ')}
 ), visible AS (SELECT * FROM matching ORDER BY cancelled_at ${sort},id ${sort} LIMIT $2 OFFSET $3), details AS (
  SELECT e.*,p.numeric_id payment_number,o.numeric_id order_number,
   u.full_name customer_name,u.phone customer_phone,u.email customer_email,u.deleted_at,
   p.invoice_phone,COALESCE(p.amount,o.total_amount) amount,COALESCE(p.bonus_amount,o.bonus_spent) bonus_amount,p.provider,COALESCE(p.created_at,o.created_at) payment_created_at,
   CASE WHEN p.payload->>'createdBy'='bot' OR cp.purchase_config->>'createdBy'='bot' THEN 'bot' ELSE 'customer' END created_by,
   CASE WHEN p.payload ? 'kaspiCancellation' OR o.cancellation_reason='Счёт Kaspi отменён' THEN 'Kaspi / MonAI'
     WHEN o.cancelled_by IS NOT NULL AND o.cancelled_by<>o.customer_id THEN 'Администратор' ELSE 'Клиент / приложение' END cancellation_source,
   COALESCE(p.payload->'kaspiCancellation','{}') effects,
   COALESCE(o.cancellation_reason,'Счёт отменён') reason,
   COALESCE(cp.purchase_config#>>'{packageSnapshot,name_ru}',pkg.name_ru) package_name,
   cp.id package_purchase_id,cp.status package_status,cp.total_cleanings,cp.available_cleanings,cp.months,
   cp.purchase_config->'pricingSnapshot' pricing_snapshot,cp.purchase_config->'perCleaningPrice' per_cleaning_price,
   cp.period_start,cp.period_end,COALESCE(cp.purchase_config->'addressSnapshot',to_jsonb(ca)) address,
   o.status order_status,o.scheduled_date,LEFT(o.start_time::text,5) start_time,LEFT(o.end_time::text,5) end_time,
   cl.full_name cleaner_name,cl.phone cleaner_phone,
   COALESCE(cp.purchase_config->'addons',p.payload#>'{quote,addons}','[]') package_addons,
   COALESCE((SELECT jsonb_agg(jsonb_build_object('id',a.id,'title',c.title_ru,'quantity',a.quantity,'price',a.price,'status',a.payment_status,'paidSeparately',a.paid_separately))
    FROM order_addons a LEFT JOIN catalog_addons c ON c.id=a.addon_id WHERE a.order_id=o.id),'[]') addons,
   COALESCE((SELECT jsonb_agg(jsonb_build_object('id',rel.id,'number',rel.numeric_id,'status',rel.status,'date',rel.scheduled_date,'startTime',LEFT(rel.start_time::text,5)))
    FROM service_orders rel WHERE rel.customer_package_id=cp.id),'[]') package_orders,
   COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pay.id,'number',pay.numeric_id,'status',pay.status,'provider',pay.provider,'amount',pay.amount,'bonusAmount',pay.bonus_amount,'createdAt',pay.created_at))
    FROM payments pay WHERE pay.id=p.id OR (e.order_id IS NOT NULL AND pay.order_id=e.order_id) OR (cp.id IS NOT NULL AND pay.customer_package_id=cp.id)),'[]') payments
  FROM visible e LEFT JOIN payments p ON e.kind='payment' AND p.id=e.id
  LEFT JOIN service_orders o ON o.id=e.order_id
  LEFT JOIN customer_packages cp ON cp.id=COALESCE(e.customer_package_id,o.customer_package_id)
  LEFT JOIN app_users u ON u.id=e.customer_id LEFT JOIN app_users cl ON cl.id=o.cleaner_id
  LEFT JOIN catalog_packages pkg ON pkg.id=COALESCE(cp.package_id,o.package_id)
  LEFT JOIN customer_addresses ca ON ca.id=COALESCE(o.address_id,cp.address_id)
 ) SELECT (SELECT COUNT(*)::int FROM matching) total,
 COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.cancelled_at ${sort},v.id ${sort}) FILTER(WHERE v.id IS NOT NULL),'[]') items FROM details v`,values)).rows[0];
 return result;
}
