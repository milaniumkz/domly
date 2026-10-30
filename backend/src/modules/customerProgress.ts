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

export const defaultCustomerTierRules = [
    { tier: 'NEWBIE', labelRu: 'Наш любимый Новичок', labelKk: 'Біздің сүйікті Жаңадан бастаушы', minMonthlySpent: 0, maxMonthlySpent: 100000, discountPercent: 0, sortOrder: 0 },
    { tier: 'CLEANSTER', labelRu: 'Наш любимый Чистюля', labelKk: 'Біздің сүйікті Тазалық жанашыры', minMonthlySpent: 100000, maxMonthlySpent: 500000, discountPercent: 5, sortOrder: 1 },
    { tier: 'GURU', labelRu: 'Гуру чистоты', labelKk: 'Тазалық гуруы', minMonthlySpent: 500000, maxMonthlySpent: 1500000, discountPercent: 10, sortOrder: 2 },
    { tier: 'GOD', labelRu: 'Бог чистоты', labelKk: 'Тазалық құдайы', minMonthlySpent: 1500000, maxMonthlySpent: null, discountPercent: 10, sortOrder: 3 },
  ];
export const normalizeCustomerTierRules = (raw: unknown) => {
    const source = Array.isArray(raw) ? raw : defaultCustomerTierRules;
    const normalized = source
      .map((item: any, index: number) => {
        const fallback = defaultCustomerTierRules[index] ?? defaultCustomerTierRules.at(-1)!;
        const minMonthlySpent = Number(item?.minMonthlySpent ?? item?.minSpent ?? fallback.minMonthlySpent);
        const maxRaw = item?.maxMonthlySpent ?? item?.maxSpent ?? fallback.maxMonthlySpent;
        const maxMonthlySpent = maxRaw === null || maxRaw === undefined || maxRaw === '' ? null : Number(maxRaw);
        return {
          tier: String(item?.tier ?? fallback.tier).trim().toUpperCase(),
          labelRu: String(item?.labelRu ?? item?.label ?? fallback.labelRu),
          labelKk: String(item?.labelKk ?? fallback.labelKk),
          minMonthlySpent: Number.isFinite(minMonthlySpent) ? Math.max(0, minMonthlySpent) : fallback.minMonthlySpent,
          maxMonthlySpent: maxMonthlySpent !== null && Number.isFinite(maxMonthlySpent) ? Math.max(0, maxMonthlySpent) : null,
          discountPercent: Math.min(100, Math.max(0, Number(item?.discountPercent ?? fallback.discountPercent) || 0)),
          sortOrder: Number(item?.sortOrder ?? index),
        };
      })
      .filter((item) => item.tier && item.labelRu)
      .sort((a, b) => a.sortOrder - b.sortOrder || a.minMonthlySpent - b.minMonthlySpent);
    return normalized.length ? normalized : defaultCustomerTierRules;
  };

/** Use the same paid-month rules as the profile, never a client-supplied tier. */
export async function customerTierDiscount(db: Queryable, customerId: string) {
  const settings=(await db.query<{value:unknown}>("SELECT value FROM app_settings WHERE key='customerTierRules'")).rows[0];
  const progress=await customerMonthlyProgress(db,customerId,normalizeCustomerTierRules(settings?.value));
  return Math.min(100,Math.max(0,Number(progress.tier_discount_percent)||0));
}

export function discountedServicePrice(price:number,percent:number) {
  return Math.round(price*(1-Math.min(100,Math.max(0,percent))/100));
}
