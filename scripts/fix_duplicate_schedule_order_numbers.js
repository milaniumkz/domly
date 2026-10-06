#!/usr/bin/env node

const admin = require('../functions/node_modules/firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || process.env.PROJECT_ID || 'domly-d0f91';
const dryRun = !process.argv.includes('--execute');

admin.initializeApp({projectId});
const db = admin.firestore();

function normalizeOrderNumber(value) {
  const parsed = Number.parseInt(String(value || '').replace(/\D/g, ''), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

function displayOrderIdFromNumber(value) {
  const number = normalizeOrderNumber(value);
  return number > 0 ? String(number) : null;
}

function sourceOrderIdFrom(slot) {
  return String(slot.sourceOrderId || slot.customerOrderId || slot.orderId || '').trim();
}

async function loadSourceOrderNumbers(slots) {
  const ids = [...new Set(slots.map(({data}) => sourceOrderIdFrom(data)).filter(Boolean))];
  const result = new Map();
  for (let index = 0; index < ids.length; index += 30) {
    const chunk = ids.slice(index, index + 30);
    const refs = chunk.map((id) => db.collection('customer_orders').doc(id));
    const snaps = await db.getAll(...refs);
    for (const snap of snaps) {
      if (!snap.exists) continue;
      const data = snap.data() || {};
      result.set(snap.id, normalizeOrderNumber(data.orderNumber || snap.id));
    }
  }
  return result;
}

async function maxKnownOrderNumber() {
  let max = 0;
  for (const collection of ['customer_orders', 'schedule_slots', 'cleaner_orders']) {
    const snap = await db.collection(collection).get();
    for (const doc of snap.docs) {
      const data = doc.data() || {};
      max = Math.max(max, normalizeOrderNumber(data.orderNumber));
    }
  }
  const counterSnap = await db.collection('system_counters').doc('customer_orders').get();
  max = Math.max(max, normalizeOrderNumber(counterSnap.data()?.lastOrderNumber));
  return max;
}

async function main() {
  const slotsSnap = await db.collection('schedule_slots').get();
  const slots = slotsSnap.docs.map((doc) => ({id: doc.id, ref: doc.ref, data: doc.data() || {}}));
  const sourceNumbers = await loadSourceOrderNumbers(slots);
  let next = await maxKnownOrderNumber();
  const used = new Set();
  const updates = [];

  for (const slot of slots) {
    const current = normalizeOrderNumber(slot.data.orderNumber);
    const sourceNumber = sourceNumbers.get(sourceOrderIdFrom(slot.data)) || 0;
    const duplicated = current > 0 && used.has(current);
    const missing = current <= 0;
    const reusesPackageNumber = current > 0 && sourceNumber > 0 && current === sourceNumber;

    if (missing || duplicated || reusesPackageNumber) {
      next += 1;
      const orderNumber = next;
      used.add(orderNumber);
      updates.push({slot, orderNumber});
    } else {
      used.add(current);
    }
  }

  console.log(`${dryRun ? 'DRY RUN' : 'EXECUTE'} project=${projectId}`);
  console.log(`slots=${slots.length}, fixes=${updates.length}, nextCounter=${next}`);
  for (const update of updates.slice(0, 20)) {
    console.log(`${update.slot.id}: ${update.slot.data.orderNumber || '-'} -> ${update.orderNumber}`);
  }
  if (updates.length > 20) console.log(`...and ${updates.length - 20} more`);
  if (dryRun || updates.length === 0) return;

  const writer = db.bulkWriter();
  for (const {slot, orderNumber} of updates) {
    const payload = {
      orderNumber,
      displayOrderId: displayOrderIdFromNumber(orderNumber),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    writer.set(slot.ref, payload, {merge: true});
    writer.set(db.collection('cleaner_orders').doc(slot.id), payload, {merge: true});
  }
  writer.set(db.collection('system_counters').doc('customer_orders'), {
    lastOrderNumber: next,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  await writer.close();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
