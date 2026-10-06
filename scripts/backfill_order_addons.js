#!/usr/bin/env node
const admin = require('../functions/node_modules/firebase-admin');

admin.initializeApp({projectId: process.env.PROJECT_ID || 'domly-d0f91'});
const db = admin.firestore();

function normalizeDetailedAddons(addonsDetailed = []) {
  return (Array.isArray(addonsDetailed) ? addonsDetailed : [])
    .map((item) => ({
      key: String(item?.key || '').trim(),
      label: String(item?.label || item?.title || item?.name || item?.optionLabel || item?.key || '').trim(),
      quantity: Math.max(0, Number(item?.quantity || 1)),
      separatePayment: item?.separatePayment === true,
    }))
    .filter((item) => item.key || item.label);
}

function labelsFrom(source = {}) {
  const labels = [];
  const add = (value) => {
    const text = String(value || '').trim();
    if (text && !labels.includes(text)) labels.push(text);
  };
  for (const item of normalizeDetailedAddons(source.addonsDetailed)) {
    add(item.label || item.key);
  }
  for (const item of Array.isArray(source.separatePaymentAddons) ? source.separatePaymentAddons : []) {
    add(item?.label || item?.title || item?.name || item?.key || item);
  }
  for (const item of Array.isArray(source.addons) ? source.addons : []) {
    add(item?.label || item?.title || item?.name || item?.key || item);
  }
  return labels;
}

function hasAddonData(source = {}) {
  return labelsFrom(source).length > 0;
}

function addonPayload(source = {}) {
  return {
    addons: Array.isArray(source.addons) ? source.addons : [],
    addonsDetailed: normalizeDetailedAddons(source.addonsDetailed),
    addonsSeparatePaymentTotal: Number(source.addonsSeparatePaymentTotal || 0),
    separatePaymentAddons: Array.isArray(source.separatePaymentAddons)
      ? source.separatePaymentAddons
      : [],
  };
}

function mergeSources(...sources) {
  const merged = {};
  for (const source of sources) {
    if (!source) continue;
    if (!hasAddonData(merged) && hasAddonData(source)) {
      Object.assign(merged, addonPayload(source));
    }
    if (!Array.isArray(merged.addonsDetailed) || merged.addonsDetailed.length === 0) {
      if (Array.isArray(source.addonsDetailed) && source.addonsDetailed.length > 0) {
        merged.addonsDetailed = normalizeDetailedAddons(source.addonsDetailed);
      }
    }
    if (!Array.isArray(merged.separatePaymentAddons) || merged.separatePaymentAddons.length === 0) {
      if (Array.isArray(source.separatePaymentAddons) && source.separatePaymentAddons.length > 0) {
        merged.separatePaymentAddons = source.separatePaymentAddons;
      }
    }
    if (!Array.isArray(merged.addons) || merged.addons.length === 0) {
      if (Array.isArray(source.addons) && source.addons.length > 0) {
        merged.addons = source.addons;
      }
    }
    if (!merged.addonsSeparatePaymentTotal && source.addonsSeparatePaymentTotal) {
      merged.addonsSeparatePaymentTotal = Number(source.addonsSeparatePaymentTotal || 0);
    }
  }
  return addonPayload(merged);
}

async function sourceForSlot(slot) {
  const sources = [slot];
  const sourceOrderId = String(slot.sourceOrderId || slot.customerOrderId || '').trim();
  if (sourceOrderId) {
    const orderSnap = await db.collection('customer_orders').doc(sourceOrderId).get();
    if (orderSnap.exists) sources.push(orderSnap.data());
  }
  const subscriptionId = String(slot.subscriptionId || '').trim();
  if (subscriptionId) {
    const subSnap = await db.collection('subscriptions').doc(subscriptionId).get();
    if (subSnap.exists) sources.push(subSnap.data());
  }
  return mergeSources(...sources);
}

async function sourceForCleanerOrder(order) {
  const sources = [order];
  const slotId = String(order.scheduleSlotId || order.slotId || '').trim();
  if (slotId) {
    const slotSnap = await db.collection('schedule_slots').doc(slotId).get();
    if (slotSnap.exists) sources.push(slotSnap.data());
  }
  const sourceOrderId = String(order.sourceOrderId || order.customerOrderId || order.orderId || '').trim();
  if (sourceOrderId) {
    const orderSnap = await db.collection('customer_orders').doc(sourceOrderId).get();
    if (orderSnap.exists) sources.push(orderSnap.data());
  }
  return mergeSources(...sources);
}

async function updateCollection(collection, sourceResolver, dryRun) {
  const snap = await db.collection(collection).get();
  let checked = 0;
  let changed = 0;
  for (const doc of snap.docs) {
    checked += 1;
    const data = doc.data() || {};
    if (hasAddonData(data)) continue;
    const payload = await sourceResolver(data);
    if (!hasAddonData(payload)) continue;
    changed += 1;
    console.log(`${dryRun ? '[dry]' : '[write]'} ${collection}/${doc.id}: ${labelsFrom(payload).join(', ')}`);
    if (!dryRun) {
      await doc.ref.set({
        ...payload,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  }
  return {collection, checked, changed};
}

async function main() {
  const dryRun = !process.argv.includes('--write');
  const results = [];
  results.push(await updateCollection('schedule_slots', sourceForSlot, dryRun));
  results.push(await updateCollection('cleaner_orders', sourceForCleanerOrder, dryRun));
  results.push(await updateCollection('cleaner_shifts', sourceForCleanerOrder, dryRun));
  console.log(JSON.stringify({dryRun, results}, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
