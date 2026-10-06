#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const admin = require('../functions/node_modules/firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'domly-d0f91';
const execute = process.argv.includes('--execute');
const skipBackup = process.argv.includes('--skip-backup');
const backupDir = path.resolve(__dirname, '..', 'backups');

const PRESERVED_COLLECTIONS = new Set([
  'admin',
  'addon_groups_config',
  'addons_config',
  'app_config',
  'customer_packages',
  'info_content',
  'meta',
  'pricing',
  'referral_config',
  'ui_content',
]);

admin.initializeApp({projectId});
const db = admin.firestore();

function serialize(value) {
  if (value == null) return value;
  if (value instanceof admin.firestore.Timestamp) {
    return {__type: 'timestamp', seconds: value.seconds, nanoseconds: value.nanoseconds};
  }
  if (value instanceof admin.firestore.GeoPoint) {
    return {__type: 'geopoint', latitude: value.latitude, longitude: value.longitude};
  }
  if (value instanceof admin.firestore.DocumentReference) {
    return {__type: 'reference', path: value.path};
  }
  if (Array.isArray(value)) return value.map(serialize);
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
    users.push(...page.users);
    token = page.pageToken;
  } while (token);
  return users;
}

function isAdminUser(user) {
  const claims = user.customClaims || {};
  return claims.admin === true || claims.superAdmin === true || claims.manager === true;
}

async function exportCollection(colRef) {
  const snap = await colRef.get();
  const docs = [];
  for (const doc of snap.docs) {
    const subcollections = await doc.ref.listCollections();
    const sub = {};
    for (const subcol of subcollections) {
      sub[subcol.id] = await exportCollection(subcol);
    }
    docs.push({
      path: doc.ref.path,
      data: serialize(doc.data()),
      subcollections: sub,
    });
  }
  return docs;
}

async function backupFirestore() {
  if (skipBackup) return null;
  const collections = await db.listCollections();
  const result = {projectId, exportedAt: new Date().toISOString(), collections: {}};
  for (const col of collections) {
    console.log(`Exporting ${col.id}...`);
    result.collections[col.id] = await exportCollection(col);
  }
  fs.mkdirSync(backupDir, {recursive: true});
  const file = path.join(
    backupDir,
    `firestore-before-orders-users-wipe-${new Date().toISOString().replace(/[:.]/g, '-')}.json`
  );
  fs.writeFileSync(file, JSON.stringify(result, null, 2));
  return file;
}

async function deleteFirestoreExcept(preservedPaths) {
  const collections = await db.listCollections();
  const deletedByCollection = {};
  const preserved = [];

  for (const col of collections) {
    if (PRESERVED_COLLECTIONS.has(col.id)) {
      const countSnap = await col.count().get();
      preserved.push(`${col.id}/* (${countSnap.data().count} docs)`);
      continue;
    }
    const snap = await col.get();
    for (const doc of snap.docs) {
      if (preservedPaths.has(doc.ref.path)) {
        preserved.push(doc.ref.path);
        continue;
      }
      deletedByCollection[col.id] = (deletedByCollection[col.id] || 0) + 1;
      if (execute) {
        await db.recursiveDelete(doc.ref);
      }
    }
  }

  return {
    deletedDocs: Object.values(deletedByCollection).reduce((sum, count) => sum + count, 0),
    deletedByCollection,
    preserved,
  };
}

async function deleteAuthExcept(adminUsers) {
  const users = await listAuthUsers();
  const preservedUids = new Set(adminUsers.map((user) => user.uid));
  const toDelete = users.filter((user) => !preservedUids.has(user.uid));
  if (execute) {
    for (let i = 0; i < toDelete.length; i += 100) {
      await admin.auth().deleteUsers(toDelete.slice(i, i + 100).map((user) => user.uid));
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
  const authUsers = await listAuthUsers();
  const adminUsers = authUsers.filter(isAdminUser);
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
  console.log('Preserved auth admins:', JSON.stringify(adminUsers.map((user) => ({
    uid: user.uid,
    email: user.email || '',
    phone: user.phoneNumber || '',
    claims: user.customClaims || {},
  })), null, 2));

  const backupFile = await backupFirestore();
  console.log(backupFile ? `Backup written: ${backupFile}` : 'Backup skipped');

  const firestore = await deleteFirestoreExcept(preservedPaths);
  const auth = await deleteAuthExcept(adminUsers);
  console.log(JSON.stringify({firestore, auth}, null, 2));

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
