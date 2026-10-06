import fs from 'fs/promises';
import path from 'path';
import admin from 'firebase-admin';

const collections = (process.env.FIREBASE_EXPORT_COLLECTIONS ?? [
  'users',
  'cleaners',
  'orders',
  'payments',
  'preorders',
  'packages',
  'addons',
  'addonGroups',
  'banners',
  'promotions',
  'translations',
  'contentPages',
  'settings',
  'notifications',
  'chats',
  'complaints',
  'reviews',
  'checklists',
  'qualityChecks',
  'houses',
  'zones',
].join(',')).split(',').map((value) => value.trim()).filter(Boolean);

async function main() {
  const outputDir = process.env.FIREBASE_EXPORT_DIR ?? path.resolve(process.cwd(), 'firebase-export');
  const includeStorage = process.env.FIREBASE_EXPORT_STORAGE !== 'false';
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
  });
  const firestore = admin.firestore();
  await fs.mkdir(outputDir, { recursive: true });

  const manifest: Record<string, number> = {};
  for (const collection of collections) {
    await exportCollection(firestore.collection(collection), collection, outputDir, manifest);
  }
  const storage = includeStorage ? await exportStorage(outputDir) : null;

  await fs.writeFile(path.join(outputDir, 'manifest.json'), JSON.stringify({
    exportedAt: new Date().toISOString(),
    collections: manifest,
    storage,
  }, null, 2));
  console.log(`Firestore export finished: ${outputDir}`);
}

async function exportCollection(
  ref: FirebaseFirestore.CollectionReference,
  collectionPath: string,
  outputDir: string,
  manifest: Record<string, number>,
) {
  const snapshot = await ref.get();
  const fileKey = collectionPath.replace(/\//g, '__');
  const rows = snapshot.docs.map((doc) => ({ id: doc.id, path: doc.ref.path, parentPath: doc.ref.parent.parent?.path ?? null, data: doc.data() }));
  await fs.writeFile(path.join(outputDir, `${fileKey}.json`), JSON.stringify(rows, null, 2));
  manifest[fileKey] = rows.length;

  for (const doc of snapshot.docs) {
    const subcollections = await doc.ref.listCollections();
    for (const subcollection of subcollections) {
      await exportCollection(subcollection, subcollection.path, outputDir, manifest);
    }
  }
}

async function exportStorage(outputDir: string) {
  const bucket = admin.storage().bucket(process.env.FIREBASE_STORAGE_BUCKET);
  const [files] = await bucket.getFiles();
  const downloadFiles = process.env.FIREBASE_EXPORT_STORAGE_DOWNLOAD === 'true';
  const storageDir = path.join(outputDir, 'storage');
  if (downloadFiles) await fs.mkdir(storageDir, { recursive: true });

  const rows = [];
  for (const file of files) {
    const [metadata] = await file.getMetadata();
    const localPath = downloadFiles ? path.join(storageDir, encodeObjectKey(file.name)) : null;
    if (localPath) {
      await fs.mkdir(path.dirname(localPath), { recursive: true });
      await file.download({ destination: localPath });
    }
    rows.push({
      bucket: bucket.name,
      name: file.name,
      localPath: localPath ? path.relative(outputDir, localPath) : null,
      contentType: metadata.contentType ?? null,
      size: metadata.size ? Number(metadata.size) : null,
      timeCreated: metadata.timeCreated ?? null,
      updated: metadata.updated ?? null,
      metadata: metadata.metadata ?? {},
    });
  }
  await fs.writeFile(path.join(outputDir, 'storage-manifest.json'), JSON.stringify(rows, null, 2));
  return { bucket: bucket.name, files: rows.length, downloaded: downloadFiles };
}

function encodeObjectKey(value: string) {
  return value.split('/').map((part) => encodeURIComponent(part)).join('/');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
