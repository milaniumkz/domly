// Operator maintenance only. Audit first; apply requires the exact audited plan.
// Reports are encrypted to the requesting operator. No credentials or PII in logs.
const crypto = require('crypto');
function minor(value) {
  const text=String(value ?? '0');
  if(!/^-?\d+(\.\d{1,2})?$/.test(text))throw Error('Invalid money representation');
  const negative=text.startsWith('-'),[whole,fraction='']=text.replace(/^-/,'').split('.');
  const result=BigInt(whole)*100n+BigInt(fraction.padEnd(2,'0'));
  return negative?-result:result;
}
function money(value) {const negative=value<0n, n=negative?-value:value;return `${negative?'-':''}${n/100n}.${String(n%100n).padStart(2,'0')}`;}
function classify(order, ledger) {
  const spent=ledger.filter(x=>x.type==='spend').reduce((s,x)=>s-minor(x.amount),0n);
  const returned=ledger.filter(x=>x.type==='refund').reduce((s,x)=>s+minor(x.amount),0n);
  const remaining=spent>returned?spent-returned:0n;
  const reason=ledger.some(x=>x.user_id!==order.customer_id)?'foreign_ledger'
    :ledger.some(x=>(x.type==='spend'&&minor(x.amount)>=0n)||(x.type==='refund'&&minor(x.amount)<=0n))?'invalid_ledger_sign'
    :returned>spent?'refund_exceeds_debit'
    :!ledger.some(x=>x.type==='spend')?'missing_debit_ledger'
    :ledger.some(x=>minor(x.amount)>0n&&x.type!=='refund')?'other_credits_require_review'
    :remaining===0n?'already_returned':null;
  return {orderId:order.id,customerId:order.customer_id,spent:money(spent),returned:money(returned),remaining:money(remaining),reason};
}
async function inspect(client, order) {
  const payments=(await client.query('SELECT id,customer_id,status,provider,amount,bonus_amount,created_at FROM payments WHERE order_id=$1 ORDER BY id',[order.id])).rows;
  const ledger=(await client.query(`SELECT id,user_id,order_id,payment_id,type,amount,balance_after,reason_ru,created_at FROM bonus_transactions
    WHERE order_id=$1 OR (order_id IS NULL AND payment_id=ANY($2::uuid[])) ORDER BY created_at,id`,[order.id,payments.map(x=>x.id)])).rows;
  return {...classify(order,ledger),order,payments,ledger};
}
function planHash(candidates) {
  return crypto.createHash('sha256').update(JSON.stringify(candidates.map(({orderId,customerId,spent,returned,remaining})=>({orderId,customerId,spent,returned,remaining})).sort((a,b)=>a.orderId.localeCompare(b.orderId)))).digest('hex');
}
async function audit(pool) {
  const client=await pool.connect();
  try {
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    const orders=(await client.query(`SELECT o.id,o.customer_id,o.status,o.bonus_spent,o.created_at,o.updated_at
      FROM service_orders o WHERE o.status='cancelled' AND (o.bonus_spent>0 OR EXISTS (
        SELECT 1 FROM bonus_transactions b LEFT JOIN payments p ON p.id=b.payment_id
        WHERE (b.order_id=o.id OR (b.order_id IS NULL AND p.order_id=o.id)) AND b.type='spend')) ORDER BY o.id`)).rows;
    const records=[];for(const order of orders)records.push(await inspect(client,order));
    await client.query('COMMIT');
    const candidates=records.filter(x=>!x.reason);
    return {at:new Date().toISOString(),records,candidates,planHash:planHash(candidates),total:money(candidates.reduce((s,x)=>s+minor(x.remaining),0n))};
  } catch(error) {await client.query('ROLLBACK');throw error;} finally {client.release();}
}
async function applyOne(pool, expected, operationId) {
  const client=await pool.connect();
  try {
    await client.query('BEGIN');
    const user=(await client.query('SELECT id,bonus_balance FROM app_users WHERE id=$1 FOR UPDATE',[expected.customerId])).rows[0];
    const order=(await client.query('SELECT id,customer_id,status,bonus_spent,created_at,updated_at FROM service_orders WHERE id=$1 FOR UPDATE',[expected.orderId])).rows[0];
    if(!user||!order||order.status!=='cancelled'||order.customer_id!==expected.customerId)throw Error('Order changed');
    const current=await inspect(client,order);
    if(current.reason||planHash([current])!==planHash([expected])) {await client.query('ROLLBACK');return {orderId:expected.orderId,status:'changed_or_already_returned'};}
    const balance=(await client.query('UPDATE app_users SET bonus_balance=bonus_balance+$2::numeric,updated_at=NOW() WHERE id=$1 RETURNING bonus_balance',[user.id,current.remaining])).rows[0].bonus_balance;
    const key=`cancelled-order-recovery-v1:${order.id}:${current.spent}:${current.returned}`;
    const credit=(await client.query(`INSERT INTO bonus_transactions(user_id,order_id,type,amount,balance_after,reason_ru,dedupe_key)
      VALUES($1,$2,'refund',$3,$4,'Возврат бонусов за отменённый заказ (сверка)',$5) RETURNING id`,[user.id,order.id,current.remaining,balance,key])).rows[0];
    await client.query(`INSERT INTO audit_logs(action,entity_type,entity_id,payload) VALUES('bonus_refund_reconciliation','order',$1,$2::jsonb)`,[order.id,JSON.stringify({operationId,transactionId:credit.id,amount:current.remaining,balanceBefore:user.bonus_balance,balanceAfter:balance,debitIds:current.ledger.filter(x=>x.type==='spend').map(x=>x.id)})]);
    await client.query('COMMIT');
    return {orderId:order.id,status:'refunded',transactionId:credit.id,amount:current.remaining,balanceBefore:user.bonus_balance,balanceAfter:balance};
  } catch(error) {await client.query('ROLLBACK');throw error;} finally {client.release();}
}
function encrypt(report, pem) {
 const publicKey=crypto.createPublicKey(pem);if(publicKey.asymmetricKeyType!=='rsa')throw Error('RSA report key required');
 const key=crypto.randomBytes(32),iv=crypto.randomBytes(12),cipher=crypto.createCipheriv('aes-256-gcm',key,iv);
 const payload=Buffer.concat([cipher.update(JSON.stringify(report)),cipher.final()]);
 return {version:1,algorithm:'RSA-OAEP-SHA256/AES-256-GCM',key:crypto.publicEncrypt({key:publicKey,oaepHash:'sha256',padding:crypto.constants.RSA_PKCS1_OAEP_PADDING},key).toString('base64'),iv:iv.toString('base64'),tag:cipher.getAuthTag().toString('base64'),payload:payload.toString('base64')};
}
async function main() {
 const pem=Buffer.from(process.env.RECOVERY_REPORT_PUBLIC_KEY_B64||'','base64');crypto.createPublicKey(pem);
 const mode=process.env.RECOVERY_MODE;if(!['audit','apply'].includes(mode))throw Error('Invalid mode');
 const {Pool}=require('pg');const pool=new Pool({connectionString:process.env.DATABASE_URL,max:2});
 const report={mode,operationId:process.env.RECOVERY_OPERATION_ID,results:[]};
 try {
   report.before=await audit(pool);
   if(mode==='apply') {
     if(!/^[a-f0-9]{64}$/.test(process.env.RECOVERY_EXPECTED_PLAN||'')||report.before.planHash!==process.env.RECOVERY_EXPECTED_PLAN)throw Error('Audited plan changed');
     for(const candidate of report.before.candidates)report.results.push(await applyOne(pool,candidate,report.operationId));
     report.after=await audit(pool);
   }
 } catch(error) {report.error={name:error.name,code:error.code||null,message:['Audited plan changed','Order changed'].includes(error.message)?error.message:'Recovery stopped; inspect preserved ledger and audit evidence'};process.exitCode=1;}
 finally {await pool.end();process.stdout.write(JSON.stringify(encrypt(report,pem))+'\n');}
}
module.exports={minor,money,classify,planHash,audit,applyOne,encrypt};
if(!module.parent)main().catch(error=>{console.error('Bonus recovery stopped: '+error.name);process.exitCode=1;});
