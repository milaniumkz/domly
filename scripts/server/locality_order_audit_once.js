const {Pool}=require('pg');
(async()=>{const p=new Pool({connectionString:process.env.DATABASE_URL});const c=await p.connect();try{
 await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
 const pattern='(кос[шщ]|қос[шщ]|хос[шщ]|kossh|kosch|kosh|qossh|qosh|khosh)';
 const match="lower(concat_ws(' ',a.city,a.settlement,a.street,a.residential_complex)) ~ $1";
 const addresses=(await c.query(`SELECT split_part(u.full_name,' ',1) AS name,right(u.phone,4) AS phone_last4,a.city,a.settlement,a.created_at,a.updated_at,
 lower(coalesce(a.street,'')) ~ $1 AS locality_in_street,
 lower(regexp_replace(a.city,'[[:space:].-]','','g')) IN ('астана','astana','нурсултан','nursultan') AS city_marked_service_available,
 EXISTS(SELECT 1 FROM connected_houses h WHERE h.active AND lower(h.city)=lower(a.city) AND lower(h.street_ru)=lower(a.street) AND lower(h.house)=lower(a.house)) AS matched_active_connected_house
 FROM customer_addresses a JOIN app_users u ON u.id=a.user_id WHERE u.deleted_at IS NULL AND ${match} ORDER BY a.created_at DESC LIMIT 20`,[pattern])).rows;
 const orders=(await c.query(`SELECT split_part(u.full_name,' ',1) AS name,right(u.phone,4) AS phone_last4,o.status,o.created_at,o.scheduled_date,o.start_time,
 cp.purchase_config->'addressSnapshot'->>'city' AS purchase_city,cp.purchase_config->'addressSnapshot'->>'settlement' AS purchase_settlement,
 p.status AS purchase_payment_status,cp.created_at AS package_created_at
 FROM service_orders o JOIN app_users u ON u.id=o.customer_id LEFT JOIN customer_packages cp ON cp.id=o.customer_package_id LEFT JOIN payments p ON p.id=cp.purchase_payment_id
 WHERE EXISTS(SELECT 1 FROM customer_addresses a WHERE a.user_id=o.customer_id AND ${match})
 ORDER BY o.created_at DESC LIMIT 60`,[pattern])).rows;
 const events=(await c.query(`SELECT split_part(u.full_name,' ',1) AS name,right(u.phone,4) AS phone_last4,
 CASE WHEN e.action LIKE '%/addresses%' THEN 'ADDRESS_SAVE' WHEN e.action LIKE '%/packages/purchase%' THEN 'PACKAGE_PURCHASE' ELSE 'ORDER_CREATE' END AS kind,
 e.result,e.http_status,e.started_at,e.fields->>'city' AS submitted_city,e.after_values->>'city' AS saved_city,
 e.fields->>'city' IS NOT NULL AS city_was_explicit,
 lower(coalesce(e.fields->>'street','')) ~ $1 AS submitted_street_contains_locality
 FROM tech_events e JOIN app_users u ON u.id=e.user_id
 WHERE EXISTS(SELECT 1 FROM customer_addresses a WHERE a.user_id=e.user_id AND ${match})
 AND (e.action LIKE '%/addresses%' OR e.action LIKE '%/packages/purchase%' OR e.action='POST /api/v1/orders')
 ORDER BY e.started_at DESC LIMIT 100`,[pattern])).rows;
 await c.query('ROLLBACK');
 const text=JSON.stringify({capturedAt:new Date().toISOString(),addresses,orders,events});
 if(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(text))throw new Error('Unexpected identifier');
 process.stdout.write(text);
 }finally{c.release();await p.end();}})().catch(()=>{console.error('Read-only locality diagnostic failed');process.exitCode=1;});
