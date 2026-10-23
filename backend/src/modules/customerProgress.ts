import { Queryable } from '../domain/repositories/UnitOfWork';

type TierRule = { tier: string; minMonthlySpent: number; discountPercent: number };

export function progressForSpent(monthlySpent: number, rules: TierRule[]) {
  const sorted = [...rules].sort((a, b) => a.minMonthlySpent - b.minMonthlySpent);
  const current = sorted.filter(rule => monthlySpent >= rule.minMonthlySpent).at(-1) ?? sorted[0];
  const next = sorted.find(rule => rule.minMonthlySpent > monthlySpent);
  return {
    monthly_spent: monthlySpent,
    tier: current?.tier ?? 'NEWBIE',
    tier_discount_percent: current?.discountPercent ?? 0,
    next_tier_threshold: next?.minMonthlySpent ?? 0,
    tier_progress: next ? Math.min(1, Math.max(0, monthlySpent / next.minMonthlySpent)) : 1,
  };
}

export async function customerMonthlyProgress(db: Queryable, customerId: string, rules: TierRule[], now = new Date()) {
  // A paid invoice is counted once, including its bonus-funded portion. Failed,
  // pending and refunded invoices are not paid services. Use Kazakhstan's month.
  const result = await db.query<{ total: string }>(`
    SELECT COALESCE(SUM(amount + bonus_amount), 0)::text AS total
    FROM payments
    WHERE customer_id=$1 AND status='paid'
      AND paid_at >= (date_trunc('month', $2::timestamptz AT TIME ZONE 'Asia/Almaty') AT TIME ZONE 'Asia/Almaty')
      AND paid_at < ((date_trunc('month', $2::timestamptz AT TIME ZONE 'Asia/Almaty') + INTERVAL '1 month') AT TIME ZONE 'Asia/Almaty')
  `, [customerId, now]);
  return progressForSpent(Number(result.rows[0].total), rules);
}
