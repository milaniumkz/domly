import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import crypto from 'node:crypto';
import {Pool} from 'pg';
const recovery=require(path.resolve(__dirname,'../../../scripts/server/reconcile_cancelled_bonuses.cjs'));

test('recovery uses exact decimals and refuses ambiguous ledger credits',()=>{
 assert.equal(recovery.money(recovery.minor('2000.15')),'2000.15');
 assert.equal(recovery.money(recovery.minor('-0.01')),'-0.01');
 assert.throws(()=>recovery.minor('1.001'));
 const order={id:'order',customer_id:'user'};
 assert.equal(recovery.classify(order,[]).reason,'missing_debit_ledger');
 assert.equal(recovery.classify(order,[{user_id:'user',type:'spend',amount:'-80'},{user_id:'user',type:'accrual',amount:'20'}]).reason,'other_credits_require_review');
 assert.equal(recovery.classify(order,[{user_id:'other',type:'spend',amount:'-80'}]).reason,'foreign_ledger');
});
test('reconciliation reports are encrypted to the operator',()=>{
 const {publicKey,privateKey}=crypto.generateKeyPairSync('rsa',{modulusLength:2048});
 const source={orderId:'sensitive-test-id',amount:'80.00'};
 const envelope=recovery.encrypt(source,publicKey.export({type:'spki',format:'pem'}));
 assert.ok(!JSON.stringify(envelope).includes(source.orderId));
 const key=crypto.privateDecrypt({key:privateKey,oaepHash:'sha256',padding:crypto.constants.RSA_PKCS1_OAEP_PADDING},Buffer.from(envelope.key,'base64'));
 const decipher=crypto.createDecipheriv('aes-256-gcm',key,Buffer.from(envelope.iv,'base64'));decipher.setAuthTag(Buffer.from(envelope.tag,'base64'));
 assert.deepEqual(JSON.parse(Buffer.concat([decipher.update(Buffer.from(envelope.payload,'base64')),decipher.final()]).toString()),source);
});
for(const failAudit of [false,true])test(`cancelled-order maintenance is atomic and idempotent (audit failure ${failAudit})`,{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const url=new URL(process.env.DOMLY_INTEGRATION_DATABASE_URL!);assert.ok(['127.0.0.1','localhost'].includes(url.hostname));
 const pool=new Pool({connectionString:url.href,max:8}),user=crypto.randomUUID(),order=crypto.randomUUID(),payment=crypto.randomUUID(),fn='recovery_'+crypto.randomUUID().replaceAll('-','');
 try {
  await pool.query("INSERT INTO app_users(id,phone,role,bonus_balance) VALUES($1,$2,'customer',50)",[user,'recovery-'+user]);
  await pool.query("INSERT INTO service_orders(id,customer_id,status,bonus_spent) VALUES($1,$2,'cancelled',80)",[order,user]);
  await pool.query("INSERT INTO payments(id,customer_id,order_id,provider,status,amount,bonus_amount) VALUES($1,$2,$3,'kaspi','cancelled',20,80)",[payment,user,order]);
  await pool.query("INSERT INTO bonus_transactions(user_id,order_id,payment_id,type,amount,balance_after,reason_ru) VALUES($1,$2,$3,'spend',-80,20,'test'),($1,$2,$3,'refund',30,50,'prior partial refund')",[user,order,payment]);
  const plan=await recovery.audit(pool),candidate=plan.candidates.find((r:any)=>r.orderId===order);
  assert.ok(candidate);assert.equal(candidate.remaining,'50.00');
  if(failAudit){
    await pool.query(`CREATE FUNCTION ${fn}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.entity_id='${order}' THEN RAISE EXCEPTION 'injected audit failure'; END IF; RETURN NEW; END $$`);
    await pool.query(`CREATE TRIGGER ${fn} BEFORE INSERT ON audit_logs FOR EACH ROW EXECUTE FUNCTION ${fn}()`);
    await assert.rejects(recovery.applyOne(pool,candidate,'test-operation'),/injected audit failure/);
    assert.equal(Number((await pool.query('SELECT bonus_balance FROM app_users WHERE id=$1',[user])).rows[0].bonus_balance),50);
    assert.equal((await pool.query("SELECT id FROM bonus_transactions WHERE order_id=$1 AND type='refund'",[order])).rows.length,1);
  }else{
    const results=await Promise.all(Array.from({length:4},()=>recovery.applyOne(pool,candidate,'test-operation')));
    assert.equal(results.filter((r:any)=>r.status==='refunded').length,1);
    assert.equal(Number((await pool.query('SELECT bonus_balance FROM app_users WHERE id=$1',[user])).rows[0].bonus_balance),100);
    assert.equal(Number((await pool.query("SELECT SUM(amount) AS sum FROM bonus_transactions WHERE order_id=$1 AND type='refund'",[order])).rows[0].sum),80);
    assert.equal((await pool.query('SELECT status FROM service_orders WHERE id=$1',[order])).rows[0].status,'cancelled');
    assert.equal((await pool.query('SELECT status FROM payments WHERE id=$1',[payment])).rows[0].status,'cancelled');
    assert.equal((await pool.query('SELECT id FROM audit_logs WHERE entity_id=$1',[order])).rows.length,1);
    assert.ok(!(await recovery.audit(pool)).candidates.some((r:any)=>r.orderId===order));
  }
 }finally{
  await pool.query(`DROP TRIGGER IF EXISTS ${fn} ON audit_logs`);await pool.query(`DROP FUNCTION IF EXISTS ${fn}()`);
  await pool.query('DELETE FROM audit_logs WHERE entity_id=$1',[order]);await pool.query('DELETE FROM bonus_transactions WHERE user_id=$1',[user]);await pool.query('DELETE FROM payments WHERE customer_id=$1',[user]);await pool.query('DELETE FROM service_orders WHERE id=$1',[order]);await pool.query('DELETE FROM app_users WHERE id=$1',[user]);await pool.end();
 }
});
