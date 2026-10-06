#!/usr/bin/env node

const path = require('path');
const admin = require(path.resolve(
  __dirname,
  '../functions/node_modules/firebase-admin',
));

function loadCredential() {
  const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (serviceAccountPath) {
    // eslint-disable-next-line global-require, import/no-dynamic-require
    const serviceAccount = require(serviceAccountPath);
    return admin.credential.cert(serviceAccount);
  }
  return admin.credential.applicationDefault();
}

admin.initializeApp({
  credential: loadCredential(),
  projectId: process.env.FIREBASE_PROJECT_ID || 'domly-d0f91',
});

const db = admin.firestore();
const {FieldValue} = admin.firestore;

const zoneId = 'astana_center';
const houses = [
  {
    id: 'test_triumph_1',
    address: 'ЖК Триумф, подъезд 1',
    title: 'ЖК Триумф',
    residentialComplex: 'ЖК Триумф',
    status: 'ACTIVE',
    threshold: 20,
    current_users: 24,
    waitlistCount: 24,
    city: 'Астана',
    lat: 51.1289,
    lng: 71.4305,
    zoneId,
  },
  {
    id: 'test_greenville_1',
    address: 'ЖК Гринвиль, подъезд 2',
    title: 'ЖК Гринвиль',
    residentialComplex: 'ЖК Гринвиль',
    status: 'IN_PROGRESS',
    threshold: 20,
    current_users: 11,
    waitlistCount: 11,
    city: 'Астана',
    lat: 51.1182,
    lng: 71.4034,
    zoneId,
  },
  {
    id: 'test_capital_park_1',
    address: 'ЖК Capital Park, блок C, подъезд 1',
    title: 'ЖК Capital Park',
    residentialComplex: 'ЖК Capital Park',
    status: 'INACTIVE',
    threshold: 20,
    current_users: 3,
    waitlistCount: 3,
    city: 'Астана',
    lat: 51.0918,
    lng: 71.4187,
    zoneId,
  },
  {
    id: 'test_avenue_1',
    address: 'ЖК Avenue Garden, подъезд 3',
    title: 'ЖК Avenue Garden',
    residentialComplex: 'ЖК Avenue Garden',
    status: 'IN_PROGRESS',
    threshold: 20,
    current_users: 14,
    waitlistCount: 14,
    city: 'Астана',
    lat: 51.1486,
    lng: 71.4542,
    zoneId,
  },
];

async function main() {
  const batch = db.batch();
  for (const house of houses) {
    const {id, ...payload} = house;
    batch.set(
      db.collection('houses').doc(id),
      {
        ...payload,
        updatedAt: FieldValue.serverTimestamp(),
        seededBy: 'scripts/add_test_houses.js',
      },
      {merge: true},
    );
  }

  batch.set(
    db.collection('service_zones').doc(zoneId),
    {
      title: 'Астана центр',
      city: 'Астана',
      status: 'active',
      houseIds: FieldValue.arrayUnion(...houses.map((house) => house.id)),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  await batch.commit();

  console.log(
    `Added ${houses.length} test houses to project domly-d0f91: ${houses
      .map((house) => house.id)
      .join(', ')}`,
  );
}

main().catch((error) => {
  console.error(error.stack || String(error));
  process.exit(1);
});
