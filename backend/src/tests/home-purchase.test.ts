import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Database} from '../infrastructure/db/Database';
import {BonusService} from '../modules/domainServices';
import {cancelHomePurchase,resumeHomePurchase} from '../modules/homePurchase';

test('home purchase: retries have one identity; cancellation refunds exactly once and rejects other owners',{skip:!process.env.DOMLY_INTEGRATION_DATABASE_URL},async()=>{
 const db=new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);const user=randomUUID(),catalog=randomUUID(),pkg=randomUUID(),payment=randomUUID();
 try{
  await db.query("INSERT INTO app_users(id,phone,role,bonus_balance) VALUES($1,$2,'customer',20)",[user,'home-'+user]);
  await db.query("INSERT INTO catalog_packages(id,name_ru,name_kk,cleaning_count,months,base_price) VALUES($1,'fixture','fixture',4,1,100)",[catalog]);
  await db.query("INSERT INTO customer_packages(id,customer_id,package_id,total_cleanings,available_cleanings,status) VALUES($1,$2,$3,4,4,'pending_payment')",[pkg,user,catalog]);
  await db.query("INSERT INTO payments(id,customer_id,customer_package_id,provider,status,amount,bonus_amount) VALUES($1,$2,$3,'kaspi','cancelled',60,40)",[payment,user,pkg]);
  await db.query("INSERT INTO bonus_transactions(user_id,payment_id,type,amount,balance_after,reason_ru) VALUES($1,$2,'spend',-40,20,'fixture')",[user,payment]);
  await assert.rejects(cancelHomePurchase(db,new BonusService(db),randomUUID(),payment));
  const retried=await Promise.all(Array.from({length:3},()=>resumeHomePurchase(db,user,payment)));
  assert.equal(new Set(retried.map(p=>p.id)).size,1);assert.notEqual(retried[0].id,payment);assert.equal(Number(retried[0].amount),60);
  assert.equal((await db.query('SELECT status FROM payments WHERE id=$1',[payment])).rows[0].status,'cancelled');
  const outcomes=await Promise.all(Array.from({length:3},()=>cancelHomePurchase(db,new BonusService(db),user,payment)));
  assert.equal(outcomes.reduce((n,r)=>n+r.bonusReturned,0),40);
  assert.equal(Number((await db.query('SELECT bonus_balance FROM app_users WHERE id=$1',[user])).rows[0].bonus_balance),60);
  assert.equal((await db.query('SELECT status FROM customer_packages WHERE id=$1',[pkg])).rows[0].status,'cancelled');
  await assert.rejects(resumeHomePurchase(db,user,payment));
  await db.query("UPDATE customer_packages SET status='active' WHERE id=$1",[pkg]);
  await assert.rejects(cancelHomePurchase(db,new BonusService(db),user,payment));
 }finally{
  await db.query('DELETE FROM bonus_transactions WHERE user_id=$1',[user]);await db.query('DELETE FROM payments WHERE customer_id=$1',[user]);await db.query('DELETE FROM customer_packages WHERE customer_id=$1',[user]);await db.query('DELETE FROM catalog_packages WHERE id=$1',[catalog]);await db.query('DELETE FROM app_users WHERE id=$1',[user]);await db.close();
 }
});
