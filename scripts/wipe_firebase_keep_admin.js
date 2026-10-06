#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const admin = require('../functions/node_modules/firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'domly-d0f91';
const execute = process.argv.includes('--execute');
const skipBackup = process.argv.includes('--skip-backup');
const backupDir = path.resolve(__dirname, '..', 'backups');
const EXPORT_CONCURRENCY = 25;
const PRESERVED_COLLECTIONS = new Set([
  'admin',
  'addon_groups_config',
  'addons_config',
  'app_config',
  'area_config',
  'checklist_templates',
  'clusters',
  'customer_packages',
  'houses',
  'info_content',
  'pricing',
  'referral_config',
  'service_zones',
  'ui_content',
  'worker_bonus_config',
]);

admin.initializeApp({projectId});
const db = admin.firestore();

function serialize(value) {
  if (value == null) {
    return value;
  }
  if (value instanceof admin.firestore.Timestamp) {
    return {__type: 'timestamp', seconds: value.seconds, nanoseconds: value.nanoseconds};
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return {__type: 'geopoint', latitude: value.latitude, longitude: value.longitude};
  }
  if (value instanceof admin.firestore.DocumentReference) {
    return {__type: 'reference', path: value.path};
  }
  if (Array.isArray(value)) {
    return value.map(serialize);
  }
  if (typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, serialize(item)]));
  }
  return value;
}

async function listAuthUsers() {
  const users = [];
  let token;
  do {
    const page = await admin.auth().listUsers(1000, token);
    for (const user of page.users) {
      users.push(user);
    }
    token = page.pageToken;
  } while (token);
  return users;
}

function isAdminUser(user) {
  const claims = user.customClaims || {};
  return claims.admin === true || claims.superAdmin === true || claims.manager === true;
}

async function exportDocument(docRef) {
  const snap = await docRef.get();
  const subcollections = await docRef.listCollections();
  const children = {};
  for (const col of subcollections) {
    children[col.id] = await exportCollection(col);
  }
  return {
    path: docRef.path,
    exists: snap.exists,
    data: snap.exists ? serialize(snap.data()) : null,
    subcollections: children,
  };
}

async function mapWithConcurrency(items, limit, mapper) {
  const results = new Array(items.length);
  let cursor = 0;
  const workers = Array.from({length: Math.min(limit, items.length)}, async () => {
    while (cursor < items.length) {
      const index = cursor;
      cursor += 1;
      results[index] = await mapper(items[index], index);
    }
  });
  await Promise.all(workers);
  return results;
}

async function exportCollection(colRef) {
  const snap = await colRef.get();
  return mapWithConcurrency(
    snap.docs,
    EXPORT_CONCURRENCY,
    (doc) => exportDocument(doc.ref)
  );
}

async function exportFirestore() {
  if (skipBackup) {
    return null;
  }
  const collections = await db.listCollections();
  const result = {
    projectId,
    exportedAt: new Date().toISOString(),
    collections: {},
  };
  for (const col of collections) {
    console.log(`Exporting ${col.id}...`);
    result.collections[col.id] = await exportCollection(col);
  }
  fs.mkdirSync(backupDir, {recursive: true});
  const file = path.join(
    backupDir,
    `firestore-before-wipe-${new Date().toISOString().replace(/[:.]/g, '-')}.json`
  );
  fs.writeFileSync(file, JSON.stringify(result, null, 2));
  return file;
}

async function deleteFirestoreExcept(preservedPaths) {
  const collections = await db.listCollections();
  let deletedDocs = 0;
  const preserved = [];
  for (const col of collections) {
    if (PRESERVED_COLLECTIONS.has(col.id)) {
      const preservedSnap = await col.count().get();
      preserved.push(`${col.id}/* (${preservedSnap.data().count} docs)`);
      continue;
    }
    const snap = await col.get();
    for (const doc of snap.docs) {
      if (preservedPaths.has(doc.ref.path)) {
        preserved.push(doc.ref.path);
        continue;
      }
      deletedDocs += 1;
      if (execute) {
        await db.recursiveDelete(doc.ref);
      }
    }
  }
  return {deletedDocs, preserved};
}

async function deleteAuthExcept(adminUsers) {
  const users = await listAuthUsers();
  const preservedUids = new Set(adminUsers.map((user) => user.uid));
  const toDelete = users.filter((user) => !preservedUids.has(user.uid));
  if (execute) {
    for (let i = 0; i < toDelete.length; i += 100) {
      const batch = toDelete.slice(i, i + 100).map((user) => user.uid);
      await admin.auth().deleteUsers(batch);
    }
  }
  return {
    deletedUsers: toDelete.length,
    preservedUsers: adminUsers.map((user) => ({
      uid: user.uid,
      email: user.email || '',
      phone: user.phoneNumber || '',
      claims: user.customClaims || {},
    })),
  };
}

async function main() {
  const users = await listAuthUsers();
  const adminUsers = users.filter(isAdminUser);
  if (adminUsers.length === 0) {
    throw new Error('No admin/superAdmin/manager Auth users found. Refusing to wipe.');
  }

  const preservedPaths = new Set();
  for (const user of adminUsers) {
    preservedPaths.add(`admin_users/${user.uid}`);
    preservedPaths.add(`users/${user.uid}`);
  }

  console.log(`Project: ${projectId}`);
  console.log(`Mode: ${execute ? 'EXECUTE' : 'DRY RUN'}`);
  console.log('Preserved admin users:', JSON.stringify(adminUsers.map((user) => ({
    uid: user.uid,
    email: user.email || '',
    phone: user.phoneNumber || '',
    claims: user.customClaims || {},
  })), null, 2));

  const backupFile = await exportFirestore();
  console.log(backupFile ? `Backup written: ${backupFile}` : 'Backup skipped by --skip-backup');

  const firestoreResult = await deleteFirestoreExcept(preservedPaths);
  const authResult = await deleteAuthExcept(adminUsers);

  console.log(JSON.stringify({
    firestore: firestoreResult,
    auth: authResult,
  }, null, 2));

  if (!execute) {
    console.log('Dry run only. Re-run with --execute to delete data.');
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
