const {Pool}=require('pg');
(async()=>{
 const db=new Pool({connectionString:process.env.DATABASE_URL});
 try {
  await db.query('BEGIN READ ONLY');
  const queue=(await db.query(`SELECT q.status,q.document_file_id IS NOT NULL AS has_document,COUNT(*)::int AS count,
   COUNT(*) FILTER(WHERE u.id IS NULL)::int AS missing_customer,
   MIN(q.created_at) AS first_created,MAX(q.created_at) AS last_created
   FROM quality_check_requests q LEFT JOIN app_users u ON u.id=q.customer_id
   GROUP BY q.status,q.document_file_id IS NOT NULL ORDER BY q.status,has_document`)).rows;
  const notices=(await db.query(`SELECT n.target_type,q.status,q.document_file_id IS NOT NULL AS has_document,
   COUNT(*)::int AS count,COUNT(*) FILTER(WHERE q.id IS NULL)::int AS missing_request,
   MIN(n.created_at) AS first_notice,MAX(n.created_at) AS last_notice
   FROM notifications n JOIN app_users u ON u.id=n.user_id AND u.role IN ('admin','superadmin')
   LEFT JOIN quality_check_requests q ON q.id::text=n.target_id::text
   WHERE n.target_type IN ('quality_check','area_quality_check') AND n.created_at>NOW()-INTERVAL '3 days'
   GROUP BY n.target_type,q.status,q.document_file_id IS NOT NULL ORDER BY n.target_type,q.status`)).rows;
  console.log('AREA_QUEUE_AUDIT '+JSON.stringify({queue,notices}));
  await db.query('ROLLBACK');
 } finally {await db.end()}
})().catch(e=>{console.error('AREA_QUEUE_AUDIT_ERROR',e.code||e.name);process.exit(1)});
