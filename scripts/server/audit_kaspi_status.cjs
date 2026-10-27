// Read-only, aggregate diagnostics; no names, phones, tokens or payment payloads.
const {Client}=require('pg');
(async()=>{
 const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();
 try {
  await db.query('BEGIN READ ONLY');
  const queries={
   payments:`SELECT status,count(*)::int FROM payments WHERE provider='kaspi' GROUP BY status`,
   callbacks:`SELECT status,resolution,count(*)::int,max(received_at) AS latest FROM moon_ai_payment_callbacks GROUP BY status,resolution`,
   sample:`SELECT status,amount,created_at,updated_at,invoice_requested_at,customer_package_id IS NOT NULL AS package_purchase, payload ? 'moonAiReview' AS review, payload->'moonAi'->>'status' AS callback_status FROM payments WHERE provider='kaspi' AND amount=129600 ORDER BY created_at DESC LIMIT 20`,
   events:`SELECT event_type,status,count(*)::int FROM payment_events WHERE provider='kaspi' GROUP BY event_type,status`
  };
  for(const [name,sql]of Object.entries(queries))console.log(JSON.stringify({[name]:(await db.query(sql)).rows}));
  await db.query('ROLLBACK');
 }finally{await db.end();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
