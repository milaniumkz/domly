// Read-only support diagnosis. Never print plaintext records or credentials.
const crypto=require('node:crypto');
function encrypt(report,publicKey){
 const key=crypto.randomBytes(32),iv=crypto.randomBytes(12);
 const cipher=crypto.createCipheriv('aes-256-gcm',key,iv);
 const data=Buffer.concat([cipher.update(JSON.stringify(report),'utf8'),cipher.final()]);
 return {v:1,key:crypto.publicEncrypt({key:publicKey,padding:crypto.constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},key).toString('base64'),iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),data:data.toString('base64')};
}
async function inspect(client){
 await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
 await client.query("SET LOCAL statement_timeout='15s'");
 try{
  const counts=(await client.query(`SELECT status,COUNT(*)::int orders,
    COUNT(*) FILTER(WHERE cleaner_id IS NULL)::int without_cleaner,
    COUNT(*) FILTER(WHERE completed_at IS NOT NULL)::int with_completion_time
    FROM service_orders GROUP BY status ORDER BY status`)).rows;
  const reviewCounts=(await client.query('SELECT author_role,rating,COUNT(*)::int reviews FROM reviews GROUP BY author_role,rating ORDER BY author_role,rating')).rows;
  const cleaners=(await client.query(`SELECT u.id,u.full_name,RIGHT(regexp_replace(u.phone,'[^0-9]','','g'),4) phone_suffix,
    u.status,u.deleted_at IS NOT NULL AS deleted,cp.verification_status,u.rating,u.created_at,
    (SELECT COUNT(*)::int FROM service_orders o WHERE o.cleaner_id=u.id AND o.status='completed') completed_orders,
    (SELECT COUNT(*)::int FROM reviews r WHERE r.cleaner_id=u.id AND r.author_role='customer') received_reviews,
    (SELECT AVG(r.rating)::numeric(4,2) FROM reviews r WHERE r.cleaner_id=u.id AND r.author_role='customer') received_average,
    (SELECT COUNT(*)::int FROM reviews r WHERE r.cleaner_id=u.id AND r.author_role='cleaner') written_reviews
    FROM app_users u LEFT JOIN cleaner_profiles cp ON cp.user_id=u.id WHERE u.role='cleaner'
    ORDER BY (u.deleted_at IS NULL AND u.status='approved') DESC,u.created_at DESC LIMIT 30`)).rows;
  const active=cleaners.filter(u=>!u.deleted&&u.status==='approved');
  const target=active.length===1?active[0]:cleaners.filter(u=>!u.deleted).length===1?cleaners.find(u=>!u.deleted):null;
  const report={at:new Date().toISOString(),counts,reviewCounts,cleaners,target:target?.id??null};
  if(target){
   report.orders=(await client.query(`SELECT o.id,o.numeric_id,o.status,o.scheduled_date::text,o.start_time::text,o.completed_at,
     (SELECT COUNT(*)::int FROM reviews r WHERE r.order_id=o.id AND r.author_role='customer') customer_reviews,
     (SELECT COUNT(*)::int FROM reviews r WHERE r.order_id=o.id AND r.author_role='cleaner') cleaner_reviews,
     (SELECT COUNT(*)::int FROM photo_reports pr WHERE pr.order_id=o.id) photo_reports,
     (SELECT COUNT(*)::int FROM checklist_reports cr WHERE cr.order_id=o.id) checklist_reports
     FROM service_orders o WHERE o.cleaner_id=$1 ORDER BY o.created_at DESC LIMIT 100`,[target.id])).rows;
   report.reviews=(await client.query(`SELECT r.id,r.order_id,r.author_role,r.rating,r.created_at,
     length(COALESCE(r.comment,'')) AS comment_length,o.numeric_id AS order_number,o.status AS order_status
     FROM reviews r LEFT JOIN service_orders o ON o.id=r.order_id WHERE r.cleaner_id=$1 ORDER BY r.created_at DESC LIMIT 100`,[target.id])).rows;
   report.apiVisibility=(await client.query(`SELECT COUNT(*)::int orders,COUNT(*) FILTER(WHERE o.status='completed')::int completed
     FROM service_orders o JOIN app_users cu ON cu.id=o.customer_id WHERE o.cleaner_id=$1`,[target.id])).rows[0];
   report.versions=(await client.query(`SELECT platform,app_version,MAX(started_at) AS last_seen,COUNT(*)::int events
     FROM tech_events WHERE user_id=$1 AND started_at>NOW()-INTERVAL '7 days'
     GROUP BY platform,app_version ORDER BY MAX(started_at) DESC LIMIT 15`,[target.id])).rows;
   report.recentReads=(await client.query(`SELECT action,http_status,error_code,platform,app_version,started_at
     FROM tech_events WHERE user_id=$1 AND action LIKE 'GET %' AND
       (action LIKE '%cleaner/orders%' OR action LIKE '%reviews%' OR action LIKE '%/me%')
     ORDER BY started_at DESC LIMIT 30`,[target.id])).rows;
  }
  await client.query('COMMIT');return report;
 }catch(error){await client.query('ROLLBACK');throw error;}
}
module.exports={encrypt,inspect};
if(require.main===module){
 (async()=>{
  const publicKey=crypto.createPublicKey({key:Buffer.from(process.env.REPORT_PUBLIC_KEY_B64||'','base64'),type:'spki',format:'der'});
  const {Pool}=require('pg');const pool=new Pool({connectionString:process.env.DATABASE_URL,max:1});
  const client=await pool.connect();
  try{process.stdout.write(JSON.stringify(encrypt(await inspect(client),publicKey)));}
  finally{client.release();await pool.end();}
 })().catch(()=>{process.stderr.write('Read-only cleaner audit failed; no plaintext report emitted.\n');process.exitCode=1;});
}
