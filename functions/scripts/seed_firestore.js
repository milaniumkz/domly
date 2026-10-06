#!/usr/bin/env node
const projectId = process.env.FIREBASE_PROJECT_ID || 'domly-d0f91';
const url =
  process.env.SEED_FUNCTION_URL ||
  `https://us-central1-${projectId}.cloudfunctions.net/seedFirestore`;
const token = process.env.SEED_TOKEN || '';

async function main() {
  const headers = {'Content-Type': 'application/json'};
  if (token) {
    headers['x-seed-token'] = token;
  }

  const response = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify(token ? {token} : {})
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${text}`);
  }

  console.log('[OK] Firestore seed uploaded:', text);
}

main().catch((error) => {
  console.error('[ERROR] Seed failed:', error);
  process.exit(1);
});
