// One-off read-only support diagnosis; only encrypted customer data leaves the server.
const {Client}=require('pg');
const {randomBytes,publicEncrypt,createCipheriv,constants}=require('crypto');
(async()=>{
 const hash=process.env.CUSTOMER_NAME_SHA256;
 if(!/^[a-f0-9]{64}$/.test(hash||''))throw Error('Invalid lookup hash');
 const publicKey=Buffer.from(process.env.REPORT_PUBLIC_KEY||'','base64').toString();
 if(!publicKey.includes('BEGIN PUBLIC KEY'))throw Error('Missing encryption key');
 const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();let report;
 try{
  await db.query('BEGIN READ ONLY');await db.query("SET LOCAL statement_timeout='10s'");
  const users=(await db.query(`SELECT id,full_name,role,status,deleted_at,right(phone,4) AS phone_suffix FROM app_users u
    WHERE EXISTS(SELECT 1 FROM regexp_split_to_table(lower(COALESCE(u.full_name,'')),'[[:space:]]+') token
      WHERE encode(sha256(convert_to(token,'UTF8')),'hex')=$1) LIMIT 10`,[hash])).rows;
  report={observedAt:new Date().toISOString(),customers:[]};
  for(const user of users){
   const packages=(await db.query(`SELECT cp.id,cp.package_id,cp.status,cp.total_cleanings,cp.available_cleanings,cp.months,cp.period_start,cp.period_end,cp.created_at,cp.purchase_payment_id,
     COALESCE(cp.purchase_config#>>'{packageSnapshot,name_ru}',pkg.name_ru) AS name
     FROM customer_packages cp LEFT JOIN catalog_packages pkg ON pkg.id=cp.package_id WHERE customer_id=$1 ORDER BY cp.created_at`,[user.id])).rows;
   const payments=(await db.query(`SELECT id,numeric_id,order_id,customer_package_id,provider,status,amount,bonus_amount,paid_at,applied_at,created_at,
     payload->>'kind' AS kind,approval_source FROM payments WHERE customer_id=$1 ORDER BY created_at`,[user.id])).rows;
   const orders=(await db.query(`SELECT id,numeric_id,customer_package_id,status,scheduled_date,start_time,end_time,cleaner_id,payable_amount,created_at FROM service_orders WHERE customer_id=$1 ORDER BY created_at`,[user.id])).rows;
   report.customers.push({...user,packages,payments,orders});
  }
  await db.query('ROLLBACK');
 }finally{await db.end();}
 const key=randomBytes(32),iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv);
 const data=Buffer.concat([cipher.update(JSON.stringify(report),'utf8'),cipher.final()]);
 console.log(JSON.stringify({version:1,key:publicEncrypt({key:publicKey,padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},key).toString('base64'),iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),data:data.toString('base64')}));
})().catch(()=>{console.error('Read-only customer audit failed; no customer data printed');process.exitCode=1;});
