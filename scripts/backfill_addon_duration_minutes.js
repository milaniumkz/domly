#!/usr/bin/env node

const admin = require('../functions/node_modules/firebase-admin');

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  process.env.PROJECT_ID ||
  'domly-d0f91';

admin.initializeApp({projectId});
const db = admin.firestore();

const durations = {
  window_standard: 15,
  window_panorama: 20,
  window_mosquito: 10,
  balcony_window_standard: 15,
  balcony_panorama: 20,
  balcony_balcony: 20,
  balcony_loggia: 20,
  balcony_terrace: 30,
  kitchen_oven: 25,
  kitchen_hood: 25,
  kitchen_fridge: 25,
  kitchen_facades: 30,
  kitchen_full_set: 60,
  kitchen_stove: 20,
  kitchen_microwave: 15,
  kitchen_apron: 15,
  kitchen_dishes_hand: 25,
  kitchen_dishwasher_loading: 10,
  bath_tile_walls: 30,
  bath_glass_walls: 25,
  bath_washer_wipe: 10,
  textile_bed_linen_ironing: 20,
  textile_clothes_ironing: 20,
  textile_curtains_ironing: 35,
  textile_bed_change: 15,
  hard_chandelier_standard: 25,
  hard_chandelier_complex: 45,
  hard_chandelier_super: 70,
  hard_lamps: 15,
  hard_upper_shelves: 25,
  hard_baseboards: 20,
  hard_doors: 15,
  hard_cobweb: 20,
  furniture_sofa: 60,
  furniture_mattress: 45,
  carpet_cleaning: 60,
};

function durationFor(item) {
  const existing = Number(item.durationMinutes || 0);
  if (Number.isFinite(existing) && existing > 0) return Math.round(existing);
  const key = String(item.key || item.id || '');
  return durations[key] || 15;
}

async function main() {
  const snap = await db.collection('addon_groups_config').get();
  const batch = db.batch();
  const addonCatalog = {};
  let groupsUpdated = 0;
  let itemsUpdated = 0;

  for (const doc of snap.docs) {
    const group = doc.data() || {};
    const items = Array.isArray(group.items) ? group.items : [];
    const nextItems = items.map((item) => {
      const next = {...item, durationMinutes: durationFor(item)};
      const key = String(next.key || next.id || '');
      if (key && next.isActive !== false) {
        addonCatalog[key] = {
          label: String(next.label || next.title || key),
          price: Number(next.price || next.unitPrice || next.amount || next.cost || 0),
          durationMinutes: Number(next.durationMinutes || 15),
          note: String(next.note || ''),
          shortInfo: String(next.shortInfo || next.description || ''),
          description: String(next.description || next.shortInfo || ''),
          fullInfo: String(next.fullInfo || next.longDescription || ''),
          longDescription: String(next.longDescription || next.fullInfo || ''),
          features: Array.isArray(next.features) ? next.features.map(String) : [],
          separatePayment: next.separatePayment === true,
        };
      }
      if (!Number(item.durationMinutes || 0)) itemsUpdated += 1;
      return next;
    });
    batch.set(doc.ref, {
      items: nextItems,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
    groupsUpdated += 1;
  }

  batch.set(db.collection('pricing').doc('default'), {
    addonCatalog,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  await batch.commit();
  console.log(JSON.stringify({ok: true, projectId, groupsUpdated, itemsUpdated}, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
