#!/usr/bin/env node

const admin = require('../functions/node_modules/firebase-admin');

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.PROJECT_ID ||
  'domly-d0f91';
const execute = process.argv.includes('--execute');

admin.initializeApp({projectId});
const db = admin.firestore();

const REFERRAL_DISCOUNT_TIERS = [
  {count: 20, percent: 10},
  {count: 10, percent: 7},
  {count: 5, percent: 3},
];

function normalizeReferralCode(code) {
  return String(code || '').trim().toUpperCase();
}

function referralDiscountPercentForCount(count) {
  const normalized = Math.max(0, Number(count || 0));
  for (const tier of REFERRAL_DISCOUNT_TIERS) {
    if (normalized >= tier.count) return tier.percent;
  }
  return 0;
}

async function referralBonusAmount(order) {
  if (Number(order.referralBonusAmount || 0) > 0) {
    return Number(order.referralBonusAmount);
  }
  const policiesSnap = await db.collection('meta').doc('policies').get();
  const policies = policiesSnap.exists ? policiesSnap.data() || {} : {};
  return Number(policies.referralBonusAmount || 2000);
}

async function paidOrders() {
  const byPaymentStatus = await db
    .collection('customer_orders')
    .where('paymentStatus', '==', 'paid')
    .get();
  const byPaidStatus = await db
    .collection('customer_orders')
    .where('status', '==', 'paid')
    .get()
    .catch(() => ({docs: []}));
  const map = new Map();
  for (const doc of [...byPaymentStatus.docs, ...byPaidStatus.docs]) {
    map.set(doc.id, {id: doc.id, ...doc.data()});
  }
  return [...map.values()];
}

async function applyReferralForOrder(order) {
  const packageId = String(order.packageId || order.package_id || '')
    .trim()
    .toLowerCase();
  if (packageId === 'addons_only') {
    return {changed: false, reason: 'addons_only'};
  }
  const amount = Number(order.price || order.total || order.amount || 0);
  if (!Number.isFinite(amount) || amount <= 0) {
    return {changed: false, reason: 'zero_amount'};
  }
  const referredUserId = String(order.customerId || '').trim();
  if (!referredUserId) return {changed: false, reason: 'no_customer'};

  const customerRef = db.collection('customers').doc(referredUserId);
  const customerSnap = await customerRef.get();
  if (!customerSnap.exists) return {changed: false, reason: 'customer_missing'};
  const customer = customerSnap.data() || {};
  const referrerCode = normalizeReferralCode(customer.referredByCode);
  if (!referrerCode) return {changed: false, reason: 'no_referral_code'};

  const referrerSnap = await db
    .collection('customers')
    .where('referralCode', '==', referrerCode)
    .limit(1)
    .get();
  if (referrerSnap.empty) return {changed: false, reason: 'referrer_missing'};

  const referrerDoc = referrerSnap.docs[0];
  const referrerUserId = referrerDoc.id;
  if (referrerUserId === referredUserId) {
    return {changed: false, reason: 'self_referral'};
  }

  const referralQuery = await db
    .collection('referrals')
    .where('user_id', '==', referrerUserId)
    .where('referredUserId', '==', referredUserId)
    .limit(1)
    .get();
  const referralRef = referralQuery.empty
    ? db.collection('referrals').doc(`${referrerUserId}_${referredUserId}`)
    : referralQuery.docs[0].ref;
  const bonusAmount = await referralBonusAmount(order);

  let changed = false;
  let bonusAdded = 0;
  if (execute) {
    await db.runTransaction(async (tx) => {
      const referralSnap = await tx.get(referralRef);
      const existing = referralSnap.exists ? referralSnap.data() || {} : {};
      const alreadyPaid = String(existing.bonusStatus || '').toLowerCase() === 'paid';
      const alreadyQualified =
        existing.monthlyPackageActivatedAt != null || existing.qualifiedAt != null;
      if (alreadyPaid && alreadyQualified) return;
      changed = true;
      tx.set(
        referralRef,
        {
          user_id: referrerUserId,
          referredUserId,
          invited_user_id: referredUserId,
          referredOrderId: order.id,
          referredByCode: referrerCode,
          status: 'registered',
          bonusStatus: 'paid',
          bonusAmount: alreadyPaid ? Number(existing.bonusAmount || bonusAmount) : bonusAmount,
          monthlyPackageActivatedAt:
            existing.monthlyPackageActivatedAt ||
            admin.firestore.FieldValue.serverTimestamp(),
          qualifiedAt:
            existing.qualifiedAt || admin.firestore.FieldValue.serverTimestamp(),
          paidAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: existing.createdAt || admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          repairedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      if (!alreadyPaid && bonusAmount > 0) {
        bonusAdded = bonusAmount;
        tx.set(
          referrerDoc.ref,
          {
            bonusPoints: admin.firestore.FieldValue.increment(bonusAmount),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
      }
      tx.set(
        customerRef,
        {
          referralAppliedAt: admin.firestore.FieldValue.serverTimestamp(),
          referralPaidOrderId: order.id,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    });
  } else {
    const referralSnap = await referralRef.get();
    const existing = referralSnap.exists ? referralSnap.data() || {} : {};
    const alreadyPaid = String(existing.bonusStatus || '').toLowerCase() === 'paid';
    const alreadyQualified =
      existing.monthlyPackageActivatedAt != null || existing.qualifiedAt != null;
    changed = !(alreadyPaid && alreadyQualified);
    bonusAdded = alreadyPaid ? 0 : bonusAmount;
  }

  return {
    changed,
    referrerUserId,
    referredUserId,
    bonusAdded,
    reason: changed ? 'repaired' : 'already_ok',
  };
}

async function recalculateStats(userId) {
  const referralsSnap = await db
    .collection('referrals')
    .where('user_id', '==', userId)
    .get();
  let invited = 0;
  let registered = 0;
  let paid = 0;
  let bonus = 0;
  let qualified = 0;
  const referrals = [];
  for (const doc of referralsSnap.docs) {
    const item = doc.data() || {};
    const referredUserId = item.referredUserId || item.invited_user_id || null;
    const invitedPhone = String(item.invited_phone || item.invitedPhone || '').trim();
    if (referredUserId || invitedPhone) invited += 1;
    if (referredUserId) registered += 1;
    if (item.bonusStatus === 'paid') {
      paid += 1;
      bonus += Number(item.bonusAmount || 0);
    }
    if (item.monthlyPackageActivatedAt || item.qualifiedAt || item.bonusStatus === 'paid') {
      qualified += 1;
    }
    referrals.push({
      id: doc.id,
      invitedPhone: invitedPhone || null,
      referredUserId,
      status: item.status || 'sent',
      bonusStatus: item.bonusStatus || 'pending',
      bonusAmount: Number(item.bonusAmount || 0),
      monthlyPackageActivatedAt: item.monthlyPackageActivatedAt || null,
      qualifiedAt: item.qualifiedAt || null,
      paidAt: item.paidAt || null,
      createdAt: item.createdAt || null,
    });
  }
  const referralDiscountPercent = referralDiscountPercentForCount(qualified);
  if (execute) {
    await db.collection('referralStats').doc(userId).set(
      {
        userId,
        invited,
        registered,
        paid,
        bonus,
        monthlyActivated: qualified,
        referralDiscountPercent,
        referrals,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        repairedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    await db.collection('customers').doc(userId).set(
      {
        referralQualifiedCount: qualified,
        referralDiscountPercent,
        referralDiscountUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  }
  return {userId, invited, registered, paid, bonus, qualified, referralDiscountPercent};
}

async function main() {
  console.log(`${execute ? 'EXECUTE' : 'DRY RUN'} referral repair on ${projectId}`);
  const orders = await paidOrders();
  const touchedReferrers = new Set();
  const reasons = {};
  let changed = 0;
  let bonusAdded = 0;
  for (const order of orders) {
    const result = await applyReferralForOrder(order);
    reasons[result.reason] = (reasons[result.reason] || 0) + 1;
    if (result.changed) {
      changed += 1;
      bonusAdded += result.bonusAdded || 0;
      if (result.referrerUserId) touchedReferrers.add(result.referrerUserId);
      console.log(
        `${execute ? 'fixed' : 'would fix'} order=${order.id} referrer=${result.referrerUserId} referred=${result.referredUserId} bonus=${result.bonusAdded}`,
      );
    }
  }
  const stats = [];
  for (const userId of touchedReferrers) {
    stats.push(await recalculateStats(userId));
  }
  console.log(JSON.stringify({orders: orders.length, changed, bonusAdded, reasons, stats}, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
