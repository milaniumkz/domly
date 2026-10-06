const admin = require('../functions/node_modules/firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: 'domly-d0f91' });
}

const db = admin.firestore();

const TARGETS = ['kk', 'en'];
const LANGPAIR = {
  kk: 'ru|kk',
  en: 'ru|en',
};

const shouldSkip = (source) => {
  const text = String(source || '').trim();
  if (!text) return true;
  if (/^https?:\/\//i.test(text)) return true;
  if (/^[\d\s.,:;+\-()/%₸м²]+$/.test(text)) return true;
  if (/[{}[\]^\\]/.test(text)) return true;
  return false;
};

async function translate(source, locale) {
  if (locale === 'ru' || shouldSkip(source)) return source;
  const url =
    'https://api.mymemory.translated.net/get?q=' +
    encodeURIComponent(source) +
    '&langpair=' +
    encodeURIComponent(LANGPAIR[locale]);
  const response = await fetch(url, {
    headers: { accept: 'application/json' },
  });
  if (!response.ok) {
    throw new Error(`translate ${locale} failed: ${response.status}`);
  }
  const data = await response.json();
  const translated = data?.responseData?.translatedText;
  if (!translated || typeof translated !== 'string') return '';
  return translated
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&')
    .trim();
}

async function runPool(items, limit, worker) {
  let cursor = 0;
  const workers = Array.from({ length: limit }, async () => {
    while (cursor < items.length) {
      const index = cursor++;
      await worker(items[index], index);
    }
  });
  await Promise.all(workers);
}

async function main() {
  const snapshot = await db.collection('app_translations').get();
  let updated = 0;
  let skipped = 0;
  let failed = 0;

  const docs = snapshot.docs;
  await runPool(docs, 8, async (doc) => {
    const data = doc.data() || {};
    const source = String(data.source || '').trim();
    const locales = { ...(data.locales || {}) };
    if (!source) return;

    let changed = false;
    for (const locale of TARGETS) {
      if (String(locales[locale] || '').trim()) continue;
      if (shouldSkip(source)) {
        locales[locale] = source;
        changed = true;
        skipped++;
        continue;
      }
      try {
        const translated = await translate(source, locale);
        if (translated) {
          locales[locale] = translated;
          changed = true;
        }
      } catch (error) {
        failed++;
        console.warn(`[WARN] ${locale}: ${source} -> ${error.message}`);
      }
    }

    if (changed) {
      await doc.ref.set(
        {
          locales,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: 'translation_sync',
        },
        { merge: true },
      );
      updated++;
      if (updated % 50 === 0) {
        console.log(`[OK] updated ${updated}`);
      }
    }
  });

  console.log(JSON.stringify({ updated, skipped, failed }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
