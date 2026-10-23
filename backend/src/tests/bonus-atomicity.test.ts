import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Database} from '../infrastructure/db/Database';
import {BonusService} from '../modules/domainServices';
for(const operation of ['accrue','spend','refund'] as const){
 test(`bonus ${operation}: failed ledger insert rolls back balance`,{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
  const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),id=randomUUID();
  try{
   await db.query("INSERT INTO app_users(id,phone,role,bonus_balance) VALUES($1,$2,'customer',100)",[id,'atomic-'+id]);
   const service=new BonusService(db);
   await assert.rejects(operation==='accrue'?service.accrue(id,40,'test',undefined,undefined,randomUUID()):service[operation](id,40,'test',undefined,randomUUID()));
   assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[id])).rows[0].bonus_balance),100,'failed operation must not change balance');
   assert.equal((await db.query('SELECT id FROM bonus_transactions WHERE user_id=$1',[id])).rows.length,0);
  }finally{await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[id]);await db.query('DELETE FROM app_users WHERE id=$1',[id]);await db.close();}
 });
}
test('simultaneous bonus spends cannot overdraw or exhaust transaction connections',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),id=randomUUID();
 try{
  await db.query("INSERT INTO app_users(id,phone,role,bonus_balance) VALUES($1,$2,'customer',100)",[id,'atomic-'+id]);
  const service=new BonusService(db);
  const result=await Promise.allSettled(Array.from({length:12},()=>service.spend(id,80,'parallel test')));
  assert.equal(result.filter(r=>r.status==='fulfilled').length,1);
  assert.ok(result.filter(r=>r.status==='rejected').every((r:any)=>r.reason.code==='not_enough_bonuses'));
  assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[id])).rows[0].bonus_balance),20);
  const ledger=(await db.query('SELECT amount,balance_after FROM bonus_transactions WHERE user_id=$1',[id])).rows;
  assert.equal(ledger.length,1);assert.equal(Number(ledger[0].amount),-80);assert.equal(Number(ledger[0].balance_after),20);
 }finally{await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[id]);await db.query('DELETE FROM app_users WHERE id=$1',[id]);await db.close();}
});

test('bonus payment cannot remain paid after ledger failure',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),id=randomUUID(),suffix=randomUUID().replaceAll('-','');
 const functionName='audit_fail_bonus_'+suffix;
 try{
  await db.query("INSERT INTO app_users(id,phone,role,bonus_balance) VALUES($1,$2,'customer',100)",[id,'atomic-'+id]);
  await db.query(`CREATE FUNCTION ${functionName}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.user_id='${id}'::uuid THEN RAISE EXCEPTION 'injected ledger storage failure'; END IF; RETURN NEW; END $$`);
  await db.query(`CREATE TRIGGER ${functionName} BEFORE INSERT ON bonus_transactions FOR EACH ROW EXECUTE FUNCTION ${functionName}()`);
  const {PaymentService}=await import('../modules/domainServices');
  await assert.rejects(new PaymentService(db,new BonusService(db)).createPayment({customerId:id,amount:80,provider:'kaspi',useBonus:true,maxBonusPercent:100,applyReferralDiscount:false}),/injected ledger storage failure/);
  assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[id])).rows[0].bonus_balance),100);
  assert.equal((await db.query('SELECT id FROM payments WHERE customer_id=$1',[id])).rows.length,0,'failed debit must not leave a paid payment');
 }finally{
  await db.query(`DROP TRIGGER IF EXISTS ${functionName} ON bonus_transactions`);await db.query(`DROP FUNCTION IF EXISTS ${functionName}()`);
  await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[id]);await db.query('DELETE FROM payments WHERE customer_id=$1',[id]);await db.query('DELETE FROM app_users WHERE id=$1',[id]);await db.close();
 }
});

test('concurrent payments share only the available bonus balance',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),id=randomUUID();
 try{
  await db.query("INSERT INTO app_users(id,phone,role,bonus_balance) VALUES($1,$2,'customer',100)",[id,'atomic-'+id]);
  const {PaymentService}=await import('../modules/domainServices');const service=new PaymentService(db,new BonusService(db));
  const results=await Promise.all(Array.from({length:2},()=>service.createPayment({customerId:id,amount:80,provider:'manual',useBonus:true,maxBonusPercent:100,applyReferralDiscount:false})));
  assert.equal(results.reduce((sum,r)=>sum+r.bonusSpent,0),100);
  assert.equal(results.reduce((sum,r)=>sum+r.payableAmount,0),60);
  assert.equal(results.filter(r=>(r.payment as any).status==='paid').length,1);
  assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[id])).rows[0].bonus_balance),0);
  const ledger=(await db.query('SELECT amount FROM bonus_transactions WHERE user_id=$1',[id])).rows;
  assert.equal(ledger.reduce((sum,r)=>sum+Number(r.amount),0),-100);
 }finally{await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[id]);await db.query('DELETE FROM payments WHERE customer_id=$1',[id]);await db.query('DELETE FROM app_users WHERE id=$1',[id]);await db.close();}
});


test('order payment refunds roll back together and serialize concurrent retries',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),id=randomUUID(),order=randomUUID(),payment=randomUUID(),suffix=randomUUID().replaceAll('-','');
 const fn='audit_fail_refund_'+suffix;
 try {
  await db.query("INSERT INTO app_users(id,phone,role,bonus_balance) VALUES($1,$2,'customer',20)",[id,'refund-'+id]);
  await db.query("INSERT INTO service_orders(id,customer_id,scheduled_date,start_time,end_time,status,bonus_spent) VALUES($1,$2,'2035-01-03','08:00','10:00','pending_payment',80)",[order,id]);
  await db.query("INSERT INTO payments(id,customer_id,order_id,provider,status,amount,bonus_amount) VALUES($1,$2,$3,'manual','pending',20,80)",[payment,id,order]);
  await db.query(`CREATE FUNCTION ${fn}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.id='${payment}'::uuid AND NEW.status='cancelled' THEN RAISE EXCEPTION 'injected refund failure'; END IF; RETURN NEW; END $$`);
  await db.query(`CREATE TRIGGER ${fn} BEFORE UPDATE ON payments FOR EACH ROW EXECUTE FUNCTION ${fn}()`);
  const {PaymentService}=await import('../modules/domainServices');const service=new PaymentService(db,new BonusService(db));
  await assert.rejects(service.refundOrderPayments(order,'test'),/injected refund failure/);
  assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[id])).rows[0].bonus_balance),20,'failed payment update must roll back bonus refund');
  assert.equal((await db.query('SELECT id FROM bonus_transactions WHERE user_id=$1',[id])).rows.length,0);
  await db.query(`DROP TRIGGER ${fn} ON payments`);
  const results=await Promise.all(Array.from({length:8},()=>service.refundOrderPayments(order,'test')));
  assert.equal(results.flat().length,1,'only one retry may refund the payment');
  assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[id])).rows[0].bonus_balance),100);
  assert.equal((await db.query('SELECT id FROM bonus_transactions WHERE user_id=$1',[id])).rows.length,1);
 } finally {
  await db.query(`DROP TRIGGER IF EXISTS ${fn} ON payments`);await db.query(`DROP FUNCTION IF EXISTS ${fn}()`);
  await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[id]);await db.query('DELETE FROM payments WHERE customer_id=$1',[id]);await db.query('DELETE FROM service_orders WHERE id=$1',[order]);await db.query('DELETE FROM app_users WHERE id=$1',[id]);await db.close();
 }
});


test('atomic scope rolls back nested services and delivers only after commit',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),observer=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!),id=randomUUID();
 let delivered=0;
 try {
  await db.query("INSERT INTO app_users(id,phone,role,bonus_balance) VALUES($1,$2,'customer',10)",[id,'scope-'+id]);
  const effect=async()=>{assert.equal(Number((await observer.query('SELECT bonus_balance FROM app_users WHERE id=$1',[id])).rows[0].bonus_balance),30);delivered++;};
  await assert.rejects(db.atomic(async()=>{await new BonusService(db).accrue(id,20,'scope');await db.afterCommit(effect);throw Error('rollback');}),/rollback/);
  assert.equal(delivered,0);assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[id])).rows[0].bonus_balance),10);
  await db.atomic(async()=>{await new BonusService(db).accrue(id,20,'scope');await db.afterCommit(effect);assert.equal(delivered,0);});
  assert.equal(delivered,1);
  await Promise.all(Array.from({length:12},()=>db.atomic(async()=>{await new BonusService(db).accrue(id,1,'concurrent scope');})));
  assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[id])).rows[0].bonus_balance),42);
 } finally {await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[id]);await db.query('DELETE FROM app_users WHERE id=$1',[id]);await db.close();await observer.close();}
});
