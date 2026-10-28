import {Database} from '../infrastructure/db/Database';
import {ApiError} from '../common/api';
import {BonusService} from './domainServices';

/** Cancel an unpaid purchase, retaining its ledger and all payment evidence. */
export async function cancelHomePurchase(db:Database,bonus:BonusService,userId:string,paymentId:string){
 return db.transaction(async tx=>{
  await tx.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[userId]);
  const payment=(await tx.query('SELECT * FROM payments WHERE id=$1 AND customer_id=$2 FOR UPDATE',[paymentId,userId])).rows[0];
  if(!payment?.customer_package_id)throw new ApiError(404,'not_found','Покупка не найдена.');
  const pkg=(await tx.query('SELECT * FROM customer_packages WHERE id=$1 AND customer_id=$2 FOR UPDATE',[payment.customer_package_id,userId])).rows[0];
  if(!pkg || !['pending_payment','cancelled'].includes(pkg.status))throw new ApiError(409,'purchase_not_pending','Оплаченный пакет нельзя отменить как заявку.');
  const payments=(await tx.query('SELECT * FROM payments WHERE customer_package_id=$1 ORDER BY id FOR UPDATE',[pkg.id])).rows;
  if(payments.some(p=>['paid','refunded'].includes(p.status)))throw new ApiError(409,'purchase_not_pending','Оплата уже подтверждена.');
  if((await tx.query("SELECT id FROM service_orders WHERE customer_package_id=$1 AND status<>'cancelled' LIMIT 1",[pkg.id])).rows.length)throw new ApiError(409,'purchase_has_orders','У пакета есть активные уборки.');
  let returned=0;
  for(const p of payments){
   const balance=Number((await tx.query("SELECT COALESCE(-SUM(amount),0) AS remaining FROM bonus_transactions WHERE user_id=$1 AND payment_id=$2 AND type IN ('spend','refund')",[userId,p.id])).rows[0].remaining);
   if(balance>0){await bonus.refund(userId,balance,'Возврат за отменённую покупку',undefined,p.id,tx);returned+=balance;}
  }
  await tx.query("UPDATE payments SET status='cancelled',updated_at=NOW() WHERE customer_package_id=$1 AND status NOT IN ('paid','refunded','cancelled')",[pkg.id]);
  await tx.query("UPDATE customer_packages SET status='cancelled',updated_at=NOW() WHERE id=$1",[pkg.id]);
  return {cancelled:true,bonusReturned:returned};
 });
}

/** A failed invoice receives a new identity; never revive a cancelled invoice. */
export async function resumeHomePurchase(db:Database,userId:string,paymentId:string){
 return db.transaction(async tx=>{
  await tx.query('SELECT id FROM app_users WHERE id=$1 FOR UPDATE',[userId]);
  const old=(await tx.query('SELECT * FROM payments WHERE id=$1 AND customer_id=$2 FOR UPDATE',[paymentId,userId])).rows[0];
  if(!old?.customer_package_id)throw new ApiError(404,'not_found','Покупка не найдена.');
  const pkg=(await tx.query('SELECT * FROM customer_packages WHERE id=$1 AND customer_id=$2 FOR UPDATE',[old.customer_package_id,userId])).rows[0];
  if(!pkg || pkg.status!=='pending_payment')throw new ApiError(409,'purchase_not_pending','Покупка уже оплачена или отменена.');
  const all=(await tx.query('SELECT * FROM payments WHERE customer_package_id=$1 ORDER BY created_at DESC,id FOR UPDATE',[pkg.id])).rows;
  if(all.some(p=>['paid','refunded'].includes(p.status)))throw new ApiError(409,'purchase_not_pending','Оплата уже подтверждена.');
  const pending=all.find(p=>['pending','draft','invoice_requested'].includes(p.status));
  if(pending)return pending;
  if(!['cancelled','rejected'].includes(old.status))throw new ApiError(409,'payment_not_retryable','Не удалось повторить этот платёж.');
  // Keep the outstanding debit attached to its original ledger entry.
  const credit=Number((await tx.query("SELECT COALESCE(-SUM(bt.amount),0) AS amount FROM bonus_transactions bt JOIN payments p ON p.id=bt.payment_id WHERE p.customer_package_id=$1 AND bt.user_id=$2 AND bt.type IN ('spend','refund')",[pkg.id,userId])).rows[0].amount);
  const price=Number(old.amount)+Number(old.bonus_amount);
  if(credit<0 || credit>price)throw new ApiError(409,'purchase_balance_mismatch','Требуется проверка бонусного баланса покупки.');
  return (await tx.query(`INSERT INTO payments(customer_id,customer_package_id,provider,status,amount,bonus_amount,payload)
   VALUES($1,$2,'kaspi','pending',$3,$4,$5) RETURNING *`,[userId,pkg.id,price-credit,credit,{kind:'package_purchase',retryOfPaymentId:old.id,inheritedBonus:true,mInfo:old.payload?.mInfo}])).rows[0];
 });
}
