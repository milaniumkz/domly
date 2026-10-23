import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { Database } from '../infrastructure/db/Database';
import { customerMonthlyProgress, progressForSpent } from '../modules/customerProgress';

const rules = [
  { tier: 'NEWBIE', minMonthlySpent: 0, discountPercent: 0 },
  { tier: 'CLEANSTER', minMonthlySpent: 100000, discountPercent: 5 },
  { tier: 'GURU', minMonthlySpent: 500000, discountPercent: 10 },
  { tier: 'GOD', minMonthlySpent: 1500000, discountPercent: 10 },
];

test('monthly progress uses configured spending thresholds, including exact boundaries', () => {
  assert.equal(progressForSpent(0, rules).tier_progress, 0);
  assert.equal(progressForSpent(99999, rules).tier, 'NEWBIE');
  assert.equal(progressForSpent(100000, rules).tier, 'CLEANSTER');
  assert.equal(progressForSpent(250000, rules).tier_progress, 0.5);
  assert.equal(progressForSpent(500000, rules).tier, 'GURU');
  assert.equal(progressForSpent(1500000, rules).tier_progress, 1);
  assert.equal(progressForSpent(1500000, rules).next_tier_threshold, 0);
  assert.equal(progressForSpent(100, [{...rules[0]}, {...rules[1], minMonthlySpent: 100}]).tier, 'CLEANSTER');
});

test('monthly spending isolates customer, paid status and Almaty calendar boundaries', { skip: !process.env.DOMLY_INTEGRATION_DATABASE_URL }, async () => {
  const db = new Database(process.env.DOMLY_INTEGRATION_DATABASE_URL!);
  const customer = randomUUID(), other = randomUUID();
  try {
    for (const id of [customer, other]) await db.query("INSERT INTO app_users(id,phone,role) VALUES($1,$2,'customer')", [id, `progress-${id}`]);
    const add = async (id: string, status: string, at: string | null, amount: number, bonus = 0) => {
      await db.query('INSERT INTO payments(customer_id,provider,status,paid_at,amount,bonus_amount) VALUES($1,\'manual\',$2,$3,$4,$5)', [id,status,at,amount,bonus]);
    };
    await add(customer, 'paid', '2026-09-30T19:00:00Z', 90000, 10000);
    await add(customer, 'paid', '2026-10-31T18:59:59Z', 25000);
    await add(customer, 'paid', '2026-09-30T18:59:59Z', 999999);
    await add(customer, 'paid', '2026-10-31T19:00:00Z', 999999);
    await add(customer, 'paid', null, 999999);
    for (const status of ['pending','invoice_requested','cancelled','rejected','refunded']) await add(customer,status,'2026-10-10T12:00:00Z',999999);
    await add(other, 'paid', '2026-10-10T12:00:00Z', 999999);
    const progress = await customerMonthlyProgress(db, customer, rules, new Date('2026-10-23T12:00:00Z'));
    assert.equal(progress.monthly_spent, 125000);
    assert.equal(progress.tier, 'CLEANSTER');
    assert.equal(progress.tier_progress, 0.25);
    assert.equal(progress.tier_discount_percent, 5);
    assert.equal(progress.next_tier_threshold, 500000);
    assert.equal((await customerMonthlyProgress(db, customer, rules, new Date('2026-12-01T00:00:00Z'))).monthly_spent, 0);
  } finally {
    await db.query('DELETE FROM payments WHERE customer_id=ANY($1::uuid[])', [[customer,other]]);
    await db.query('DELETE FROM app_users WHERE id=ANY($1::uuid[])', [[customer,other]]);
    await db.close();
  }
});
