import { Database } from '../infrastructure/db/Database';

// Bonus limits are administrative policy, never a value supplied by the payer.
// Keep the existing 50% default; active eligible promotions can raise it.
export async function addonBonusPercent(db: Database, orderId: string): Promise<number> {
  const row = (await db.query(`SELECT GREATEST(50, COALESCE(MAX(p.max_bonus_spend_percent),50)) AS percent
    FROM promotions p
    WHERE p.active=TRUE AND (p.starts_at IS NULL OR p.starts_at<=NOW())
      AND (p.ends_at IS NULL OR p.ends_at>=NOW())
      AND COALESCE(p.presentation->>'rewardTarget','addons') IN ('addons','all')
      AND (p.package_id IS NULL OR p.package_id=(SELECT package_id FROM service_orders WHERE id=$1))`, [orderId])).rows[0];
  return Math.max(0, Math.min(100, Number(row?.percent ?? 50)));
}

/** Add bonuses to an unissued payment without spending the original bonuses twice. */
export async function topUpPendingBonus(db: Database, paymentId: string, requested: number, percent: number) {
  if (!Number.isFinite(requested) || requested <= 0) return null;
  return db.transaction(async tx => {
    const payment=(await tx.query("SELECT * FROM payments WHERE id=$1 AND status='pending' FOR UPDATE",[paymentId])).rows[0];
    if (!payment) return null;
    const user=(await tx.query('SELECT bonus_balance FROM app_users WHERE id=$1 FOR UPDATE',[payment.customer_id])).rows[0];
    const remaining=Number(payment.amount),spent=Number(payment.bonus_amount);
    const cap=Math.max(0,Math.floor((remaining+spent)*percent/100)-spent);
    const additional=Math.min(remaining,cap,Math.floor(requested),Number(user.bonus_balance));
    if (additional<=0) return payment;
    const balance=(await tx.query('UPDATE app_users SET bonus_balance=bonus_balance-$2,updated_at=NOW() WHERE id=$1 RETURNING bonus_balance',[payment.customer_id,additional])).rows[0];
    await tx.query(`INSERT INTO bonus_transactions(user_id,order_id,payment_id,type,amount,balance_after,reason_ru)
      VALUES($1,$2,$3,'spend',$4,$5,'Оплата бонусами')`,[payment.customer_id,payment.order_id,payment.id,-additional,balance.bonus_balance]);
    const paid=remaining===additional;
    const updated=(await tx.query(`UPDATE payments SET amount=amount-$2,bonus_amount=bonus_amount+$2,
      status=CASE WHEN $3 THEN 'paid'::payment_status ELSE status END,
      provider=CASE WHEN $3 THEN 'bonus' ELSE provider END,
      approval_source=CASE WHEN $3 THEN 'bonus' ELSE approval_source END,
      approved_at=CASE WHEN $3 THEN NOW() ELSE approved_at END,paid_at=CASE WHEN $3 THEN NOW() ELSE paid_at END,updated_at=NOW()
      WHERE id=$1 RETURNING *`,[payment.id,additional,paid])).rows[0];
    await tx.query('UPDATE service_orders SET bonus_spent=bonus_spent+$2,payable_amount=$3,updated_at=NOW() WHERE id=$1',[payment.order_id,additional,remaining-additional]);
    return updated;
  });
}
