import fs from 'fs/promises';
import path from 'path';

type ExportRow = { id: string; data: Record<string, unknown> };
type Manifest = { exportedAt?: string; collections: Record<string, number> };
type Issue = { collection: string; documentId: string; code: string; message: string };

const mappedCollections = new Set([
  'users',
  'clients',
  'customers',
  'cleaners',
  'admins',
  'customeraddresses',
  'clientaddresses',
  'useraddresses',
  'userhomes',
  'customerpackages',
  'userpackages',
  'subscriptions',
  'purchasedpackages',
  'clientpackages',
  'packages',
  'catalogpackages',
  'servicepackages',
  'tariffs',
  'addongroups',
  'addoncategories',
  'servicecategories',
  'addons',
  'extras',
  'additionalservices',
  'services',
  'zones',
  'servicezones',
  'districts',
  'coveragezones',
  'houses',
  'connectedhouses',
  'addresses',
  'homes',
  'translations',
  'apptranslations',
  'app_translations',
  'banners',
  'homebanners',
  'promotions',
  'promo',
  'promos',
  'actions',
  'contentpages',
  'content',
  'infocontent',
  'legalpages',
  'policies',
  'orders',
  'serviceorders',
  'cleanings',
  'payments',
  'paymentrequests',
  'invoices',
  'preorders',
  'preliminaryorders',
  'qualitychecks',
  'areachecks',
  'squarechecks',
  'notifications',
  'pushnotifications',
  'complaints',
  'claims',
  'reviews',
  'ratings',
  'photoreports',
  'photo_reports',
  'orderphotoreports',
  'chats',
  'messages',
  'settings',
  'appsettings',
  'config',
]);

async function main() {
  const inputDir = process.env.FIREBASE_EXPORT_DIR ?? path.resolve(process.cwd(), 'firebase-export');
  const outputPath = process.env.MIGRATION_AUDIT_OUT ?? path.join(inputDir, 'migration-audit.json');
  const manifest = JSON.parse(await fs.readFile(path.join(inputDir, 'manifest.json'), 'utf8')) as Manifest;
  const issues: Issue[] = [];
  const coverage: Record<string, { count: number; mapped: boolean }> = {};

  for (const [collection, count] of Object.entries(manifest.collections)) {
    const normalized = normalizeCollection(collection);
    coverage[collection] = { count, mapped: mappedCollections.has(normalized) };
    const rows = JSON.parse(await fs.readFile(path.join(inputDir, `${collection}.json`), 'utf8')) as ExportRow[];
    for (const row of rows) auditRow(collection, normalized, row, issues);
  }

  const summary = {
    ok: issues.length === 0,
    exportedAt: manifest.exportedAt ?? null,
    auditedAt: new Date().toISOString(),
    totalCollections: Object.keys(manifest.collections).length,
    totalDocuments: Object.values(manifest.collections).reduce((sum, count) => sum + count, 0),
    mappedCollections: Object.values(coverage).filter((item) => item.mapped).length,
    unmappedCollections: Object.entries(coverage).filter(([, item]) => !item.mapped).map(([collection, item]) => ({ collection, count: item.count })),
    issueCount: issues.length,
    issuesByCode: issues.reduce((acc: Record<string, number>, issue) => {
      acc[issue.code] = (acc[issue.code] ?? 0) + 1;
      return acc;
    }, {}),
  };

  const report = { summary, coverage, issues };
  await fs.writeFile(outputPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(summary, null, 2));
  console.log(`Migration audit written: ${outputPath}`);
  if (process.env.MIGRATION_AUDIT_STRICT === 'true' && issues.length > 0) process.exit(1);
}

function auditRow(collection: string, normalized: string, row: ExportRow, issues: Issue[]) {
  if (['users', 'clients', 'customers', 'cleaners', 'admins'].includes(normalized)) {
    if (!text(row.data, ['phone', 'phoneNumber', 'mobile', 'tel'])) add(issues, collection, row.id, 'missing_phone', 'У пользователя нет телефона.');
  }
  if (['orders', 'serviceorders', 'cleanings'].includes(normalized)) {
    if (!text(row.data, ['customerId', 'customer_id', 'userId', 'clientId', 'customerPhone', 'phone', 'clientPhone'])) {
      add(issues, collection, row.id, 'missing_order_customer', 'У заказа нет customerId или телефона клиента.');
    }
    if (!dateValue(row.data, ['scheduledDate', 'scheduled_date', 'date'])) add(issues, collection, row.id, 'missing_order_date', 'У заказа нет даты.');
    if (!text(row.data, ['startTime', 'start_time', 'timeFrom'])) add(issues, collection, row.id, 'missing_order_start_time', 'У заказа нет времени начала.');
  }
  if (['customeraddresses', 'clientaddresses', 'useraddresses', 'userhomes'].includes(normalized)) {
    if (!text(row.data, ['userId', 'user_id', 'customerId', 'customer_id', 'clientId', 'phone', 'customerPhone', 'clientPhone'])) {
      add(issues, collection, row.id, 'missing_address_customer', 'У адреса клиента нет userId/customerId или телефона.');
    }
    if (!text(row.data, ['street', 'streetRu', 'street_ru', 'addressStreet', 'address'])) {
      add(issues, collection, row.id, 'missing_address_street', 'У адреса клиента нет улицы.');
    }
  }
  if (['customerpackages', 'userpackages', 'subscriptions', 'purchasedpackages', 'clientpackages'].includes(normalized)) {
    if (!text(row.data, ['userId', 'user_id', 'customerId', 'customer_id', 'clientId', 'phone', 'customerPhone', 'clientPhone'])) {
      add(issues, collection, row.id, 'missing_customer_package_customer', 'У купленного пакета нет клиента.');
    }
    if (!text(row.data, ['packageId', 'package_id', 'tariffId', 'packageName', 'package_name', 'tariffName', 'subscriptionName'])) {
      add(issues, collection, row.id, 'missing_customer_package_catalog', 'У купленного пакета нет ссылки на каталог или названия пакета.');
    }
  }
  if (['packages', 'catalogpackages', 'servicepackages', 'tariffs'].includes(normalized)) {
    if (!text(row.data, ['nameRu', 'name_ru', 'titleRu', 'title_ru', 'name', 'title'])) add(issues, collection, row.id, 'missing_package_name', 'У пакета нет названия.');
    if (number(row.data, ['basePrice', 'base_price', 'price', 'amount']) == null) add(issues, collection, row.id, 'missing_package_price', 'У пакета нет цены.');
  }
  if (['addons', 'extras', 'additionalservices', 'services'].includes(normalized)) {
    if (!text(row.data, ['titleRu', 'title_ru', 'nameRu', 'name_ru', 'title', 'name'])) add(issues, collection, row.id, 'missing_addon_title', 'У доп. услуги нет названия.');
    if (number(row.data, ['price', 'amount']) == null) add(issues, collection, row.id, 'missing_addon_price', 'У доп. услуги нет цены.');
  }
  if (['payments', 'paymentrequests', 'invoices'].includes(normalized)) {
    if (number(row.data, ['amount', 'sum', 'payableAmount', 'payable_amount']) == null) add(issues, collection, row.id, 'missing_payment_amount', 'У платежа нет суммы.');
    if (!text(row.data, ['customerId', 'customer_id', 'userId', 'clientId', 'customerPhone', 'phone', 'clientPhone'])) {
      add(issues, collection, row.id, 'missing_payment_customer', 'У платежа нет customerId или телефона клиента.');
    }
  }
  if (['houses', 'connectedhouses', 'addresses', 'homes'].includes(normalized)) {
    if (!text(row.data, ['streetRu', 'street_ru', 'street', 'addressStreet'])) add(issues, collection, row.id, 'missing_house_street', 'У дома нет улицы.');
    if (!text(row.data, ['house', 'houseNumber', 'building'])) add(issues, collection, row.id, 'missing_house_number', 'У дома нет номера.');
  }
  if (['preorders', 'preliminaryorders'].includes(normalized)) {
    if (!text(row.data, ['customerId', 'customer_id', 'userId', 'clientId', 'customerPhone', 'phone', 'clientPhone'])) {
      add(issues, collection, row.id, 'missing_preorder_customer', 'У предварительной записи нет клиента.');
    }
  }
  if (['qualitychecks', 'areachecks', 'squarechecks'].includes(normalized)) {
    if (!text(row.data, ['customerId', 'customer_id', 'userId', 'clientId', 'customerPhone', 'phone', 'clientPhone'])) {
      add(issues, collection, row.id, 'missing_quality_customer', 'У проверки площади нет клиента.');
    }
    if (number(row.data, ['requestedArea', 'requested_area', 'area']) == null) add(issues, collection, row.id, 'missing_quality_area', 'У проверки площади нет заявленной площади.');
  }
  if (['complaints', 'claims'].includes(normalized)) {
    if (!text(row.data, ['customerId', 'customer_id', 'userId', 'clientId', 'customerPhone', 'phone', 'clientPhone'])) {
      add(issues, collection, row.id, 'missing_complaint_customer', 'У жалобы нет клиента.');
    }
  }
  if (['reviews', 'ratings'].includes(normalized)) {
    if (!text(row.data, ['customerId', 'customer_id', 'userId', 'clientId', 'customerPhone', 'phone', 'clientPhone'])) {
      add(issues, collection, row.id, 'missing_review_customer', 'У отзыва нет клиента.');
    }
    if (number(row.data, ['rating', 'score']) == null) add(issues, collection, row.id, 'missing_review_rating', 'У отзыва нет оценки.');
  }
}

function add(issues: Issue[], collection: string, documentId: string, code: string, message: string) {
  issues.push({ collection, documentId, code, message });
}

function normalizeCollection(value: string) {
  return value.replace(/[^a-zA-Z0-9_]/g, '').toLowerCase();
}

function text(data: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
    if (typeof value === 'number') return String(value);
  }
  return null;
}

function number(data: Record<string, unknown>, keys: string[]): number | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    if (typeof value === 'string' && value.trim() && Number.isFinite(Number(value))) return Number(value);
  }
  return null;
}

function dateValue(data: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const value = data[key] as any;
    if (!value) continue;
    if (typeof value === 'string') return value;
    if (typeof value === 'number') return new Date(value).toISOString();
    if (typeof value?.toDate === 'function') return value.toDate().toISOString();
    if (typeof value?._seconds === 'number') return new Date(value._seconds * 1000).toISOString();
    if (typeof value?.seconds === 'number') return new Date(value.seconds * 1000).toISOString();
  }
  return null;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
