import { Queryable } from '../domain/repositories/UnitOfWork';
import { Database } from '../infrastructure/db/Database';
import { first } from '../common/sql';

export async function qualifyReferral(db: Database, payment: {id: string; customer_id: string; customer_package_id?: string | null}) {
  if (!payment.customer_package_id) return;
  await db.transaction(async tx => {
    const referral = first<any>((await tx.query('SELECT * FROM user_referrals WHERE customer_id=$1 FOR UPDATE', [payment.customer_id])).rows);
    if (!referral || referral.qualified_at) return;
    const inviter = first<any>((await tx.query('SELECT id FROM app_users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE', [referral.inviter_id])).rows);
    if (!inviter) return;
    const settings = Object.fromEntries((await tx.query<any>("SELECT key,value FROM app_settings WHERE key IN ('referralBonusAmount','referralMilestoneCount','referralMilestoneBonus')")).rows.map(row => [row.key,row.value]));
    const base = Math.max(0, Number(settings.referralBonusAmount ?? 2000));
    await tx.query('UPDATE user_referrals SET qualified_at=NOW(),reward_amount=$2 WHERE customer_id=$1', [payment.customer_id,base]);
    const count = Number(first<any>((await tx.query('SELECT COUNT(*) AS count FROM user_referrals WHERE inviter_id=$1 AND qualified_at IS NOT NULL', [inviter.id])).rows)?.count ?? 0);
    const milestone = Math.max(1, Number(settings.referralMilestoneCount ?? 5));
    let reward = base;
    if (count === milestone) reward += Math.max(0, Number(settings.referralMilestoneBonus ?? 10000));
    if (!Number.isFinite(reward) || reward <= 0) return;
    const user = first<any>((await tx.query('UPDATE app_users SET bonus_balance=bonus_balance+$2,updated_at=NOW() WHERE id=$1 RETURNING bonus_balance', [inviter.id,reward])).rows);
    await tx.query(`INSERT INTO bonus_transactions (user_id,payment_id,type,amount,balance_after,reason_ru)
      VALUES ($1,$2,'accrual',$3,$4,'Бонус за покупку пакета приглашённым клиентом')`, [inviter.id,payment.id,reward,user.bonus_balance]);
  });
}

export async function referralDiscount(db: Queryable, userId: string) {
  const count = Number(first<any>((await db.query('SELECT COUNT(*) AS count FROM user_referrals WHERE inviter_id=$1 AND qualified_at IS NOT NULL', [userId])).rows)?.count ?? 0);
  const setting = first<any>((await db.query("SELECT value FROM app_settings WHERE key='referralDiscountTiers'")).rows);
  const tiers = setting?.value ?? [{count:5,discount:3},{count:10,discount:7},{count:20,discount:10}];
  return Array.isArray(tiers) ? Math.max(0,...tiers.filter(tier=>Number(tier.count)<=count).map(tier=>Math.min(100,Number(tier.discount)||0))) : 0;
}

/** Display progress uses the same lifetime qualified-referral thresholds as the discount. */
export function referralDiscountProgress(qualified: number, input: unknown) {
  const defaults=[{count:5,discount:3},{count:10,discount:7},{count:20,discount:10}];
  const byCount=new Map<number,number>();
  for(const tier of (Array.isArray(input??defaults)?input??defaults:[]) as any[]) {
    const count=Number(tier?.count),discount=Number(tier?.discount);
    if(!Number.isFinite(count)||!Number.isFinite(discount))continue;
    const threshold=Math.max(0,Math.ceil(count)),percent=Math.max(0,Math.min(100,discount));
    byCount.set(threshold,Math.max(byCount.get(threshold)??0,percent));
  }
  const tiers=[...byCount].sort((a,b)=>a[0]-b[0]).map(([count,discount])=>({count,discount}));
  const count=Math.max(0,Math.floor(Number.isFinite(qualified)?qualified:0));
  const current=Math.max(0,...tiers.filter(t=>t.count<=count).map(t=>t.discount));
  const maximum=Math.max(0,...tiers.map(t=>t.discount));
  const maxTier=tiers.find(t=>t.discount===maximum);
  const next=tiers.find(t=>t.count>count&&t.discount>current);
  return {
    referralDiscountTiers:tiers,referralDiscountPercent:current,
    nextReferralDiscountPercent:next?.discount??null,nextReferralDiscountThreshold:next?.count??null,
    remainingForNextDiscount:next?Math.max(0,next.count-count):0,
    maxReferralDiscountPercent:maximum,maxReferralDiscountThreshold:maxTier?.count??0,
    remainingForMaxDiscount:Math.max(0,(maxTier?.count??0)-count),
    maxReferralDiscountReached:maximum>0&&current>=maximum,
  };
}
