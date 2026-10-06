#!/usr/bin/env node

const admin = require('../functions/node_modules/firebase-admin');

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.PROJECT_ID ||
  'domly-d0f91';

admin.initializeApp({projectId});
const db = admin.firestore();

const note = 'Оплата по этой услуге производится отдельно.';
const furnitureKeys = new Set(['furniture_sofa', 'furniture_mattress']);

async function updateAddonGroup(collectionName) {
  const ref = db.collection(collectionName).doc('furniture');
  const snap = await ref.get();
  if (!snap.exists) {
    return {collectionName, exists: false, updated: 0};
  }
  const data = snap.data() || {};
  const items = Array.isArray(data.items)
    ? data.items.map((item) => {
        if (!furnitureKeys.has(String(item?.key || ''))) {
          return item;
        }
        return {
          ...item,
          separatePayment: true,
          separate: true,
          note: item.note || note
        };
      })
    : [];
  await ref.set({
    note: data.note || note,
    items,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  return {collectionName, exists: true, updated: items.length};
}

async function updatePricing() {
  const ref = db.collection('pricing').doc('default');
  const snap = await ref.get();
  const data = snap.exists ? snap.data() || {} : {};
  const addonCatalog = {
    ...(data.addonCatalog || {}),
    furniture_sofa: {
      ...(data.addonCatalog?.furniture_sofa || {}),
      label: data.addonCatalog?.furniture_sofa?.label || 'Химчистка диванов',
      price: Number(data.addonCatalog?.furniture_sofa?.price || 9000),
      separatePayment: true
    },
    furniture_mattress: {
      ...(data.addonCatalog?.furniture_mattress || {}),
      label: data.addonCatalog?.furniture_mattress?.label || 'Химчистка матрасов',
      price: Number(data.addonCatalog?.furniture_mattress?.price || 7000),
      separatePayment: true
    }
  };
  await ref.set({
    addonCatalog,
    updatedAt: admin.firestore.FieldValue.serverTimestamp()
  }, {merge: true});
  return {collectionName: 'pricing/default', updated: 2};
}

async function main() {
  const results = await Promise.all([
    updateAddonGroup('addon_groups_config'),
    updateAddonGroup('debug_bridge_addon_groups'),
    updatePricing()
  ]);
  console.log(JSON.stringify({ok: true, projectId, results}, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
