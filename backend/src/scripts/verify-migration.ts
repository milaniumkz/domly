import fs from 'fs/promises';
import path from 'path';
import { Database } from '../infrastructure/db/Database';
import { env } from '../common/env';
import { normalizeMigrationOrderStatus, normalizeMigrationPaymentStatus } from './migration-utils';

type ExportRow = { id: string; data: Record<string, unknown> };
type Manifest = {
  collections: Record<string, number>;
  storage?: { bucket: string; files: number; downloaded: boolean } | null;
};
type LegacyStats = {
  payments: { count: number; amount: number; bonus: number; byStatus: Record<string, number> };
  orders: { count: number; amount: number; addonItemOrders: number; byStatus: Record<string, number> };
  users: { count: number; bonusBalance: number };
};

async function main() {
  const inputDir = process.env.FIREBASE_EXPORT_DIR ?? path.resolve(process.cwd(), 'firebase-export');
  const outputPath = process.env.MIGRATION_VERIFY_OUT ?? path.join(inputDir, 'migration-verify.json');
  const manifest = JSON.parse(await fs.readFile(path.join(inputDir, 'manifest.json'), 'utf8')) as Manifest;
  const legacyStats = await collectLegacyStats(inputDir, manifest.collections);
  const db = new Database(env.databaseUrl);
  const failures: string[] = [];
  const startedAt = new Date().toISOString();

  try {
    for (const [collection, expected] of Object.entries(manifest.collections)) {
      const result = await db.query<{ count: string }>(
        `SELECT COUNT(*)::text AS count FROM legacy_firestore_documents WHERE collection_name=$1`,
        [collection],
      );
      const actual = Number(result.rows[0]?.count ?? 0);
      if (actual !== expected) failures.push(`${collection}: expected ${expected}, actual ${actual}`);
    }
    await verifyCoreTables(db, failures);
    await verifyPaymentTotals(db, legacyStats, failures);
    await verifyOrderTotals(db, legacyStats, failures);
    await verifyOrderAddons(db, legacyStats, failures);
    await verifyBonusBalances(db, legacyStats, failures);
    await verifyPackageState(db, failures);
    await verifyRelationalIntegrity(db, failures);
    await verifyStorageFiles(db, inputDir, manifest, failures);
  } finally {
    await db.close();
  }

  const report = {
    ok: failures.length === 0,
    startedAt,
    finishedAt: new Date().toISOString(),
    inputDir,
    manifest,
    legacyStats,
    failureCount: failures.length,
    failures,
  };
  await fs.writeFile(outputPath, JSON.stringify(report, null, 2));
  console.log(`Migration verification report written: ${outputPath}`);

  if (failures.length > 0) {
    console.error(`Migration verification failed:\n${failures.join('\n')}`);
    process.exit(1);
  }
  console.log('Migration verification passed.');
}

async function verifyStorageFiles(db: Database, inputDir: string, manifest: Manifest, failures: string[]) {
  if (!manifest.storage) return;
  const storageRows = JSON.parse(await fs.readFile(path.join(inputDir, 'storage-manifest.json'), 'utf8')) as Array<{ name: string }>;
  compareNumber('storage manifest count', storageRows.length, manifest.storage.files, failures);
  const result = await db.query<{ count: string }>(
    `SELECT COUNT(*)::text AS count FROM files WHERE object_key LIKE 'firebase/%'`,
  );
  compareNumber('imported storage files count', Number(result.rows[0]?.count ?? 0), storageRows.length, failures);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});

async function verifyCoreTables(db: Database, failures: string[]) {
  const checks = [
    { table: 'catalog_packages', label: 'пакеты' },
    { table: 'catalog_addons', label: 'доп. услуги' },
    { table: 'connected_houses', label: 'подключенные дома' },
    { table: 'app_users', label: 'пользователи' },
  ];
  for (const check of checks) {
    const result = await db.query<{ count: string }>(`SELECT COUNT(*)::text AS count FROM ${check.table}`);
    const count = Number(result.rows[0]?.count ?? 0);
    console.log(`${check.label}: ${count}`);
  }

  const duplicatePhones = await db.query<{ phone: string; count: string }>(
    `SELECT phone, COUNT(*)::text AS count FROM app_users GROUP BY phone HAVING COUNT(*) > 1 LIMIT 10`,
  );
  if (duplicatePhones.rows.length > 0) failures.push(`duplicate user phones: ${JSON.stringify(duplicatePhones.rows)}`);

  const brokenOrders = await db.query<{ count: string }>(
    `SELECT COUNT(*)::text AS count
     FROM service_orders o
     LEFT JOIN app_users u ON u.id=o.customer_id
     WHERE u.id IS NULL`,
  );
  if (Number(brokenOrders.rows[0]?.count ?? 0) > 0) failures.push(`orders without customer: ${brokenOrders.rows[0].count}`);
}

async function verifyPaymentTotals(db: Database, legacy: LegacyStats, failures: string[]) {
  const actual = await db.query<{ count: string; amount: string; bonus: string }>(
    `SELECT COUNT(*)::text AS count,
            COALESCE(SUM(amount),0)::text AS amount,
            COALESCE(SUM(bonus_amount),0)::text AS bonus
     FROM payments
     WHERE legacy_firestore_id IS NOT NULL`,
  );
  const row = actual.rows[0];
  compareNumber('payments count', Number(row?.count ?? 0), legacy.payments.count, failures);
  compareMoney('payments amount sum', Number(row?.amount ?? 0), legacy.payments.amount, failures);
  compareMoney('payments bonus sum', Number(row?.bonus ?? 0), legacy.payments.bonus, failures);
  await compareStatusCounts(db, 'payments', 'payments', legacy.payments.byStatus, failures);
}

async function verifyOrderTotals(db: Database, legacy: LegacyStats, failures: string[]) {
  const actual = await db.query<{ count: string; amount: string }>(
    `SELECT COUNT(*)::text AS count,
            COALESCE(SUM(total_amount),0)::text AS amount
     FROM service_orders
     WHERE legacy_firestore_id IS NOT NULL`,
  );
  const row = actual.rows[0];
  compareNumber('orders count', Number(row?.count ?? 0), legacy.orders.count, failures);
  compareMoney('orders total amount sum', Number(row?.amount ?? 0), legacy.orders.amount, failures);
  await compareStatusCounts(db, 'service_orders', 'orders', legacy.orders.byStatus, failures);
}

async function verifyOrderAddons(db: Database, legacy: LegacyStats, failures: string[]) {
  if (legacy.orders.addonItemOrders === 0) return;
  const actual = await db.query<{ count: string }>(
    `SELECT COUNT(DISTINCT o.id)::text AS count
     FROM service_orders o
     JOIN order_addons oa ON oa.order_id=o.id
     WHERE o.legacy_firestore_id IS NOT NULL`,
  );
  compareNumber('orders with addon items', Number(actual.rows[0]?.count ?? 0), legacy.orders.addonItemOrders, failures);
}

async function verifyBonusBalances(db: Database, legacy: LegacyStats, failures: string[]) {
  const actual = await db.query<{ count: string; bonus: string }>(
    `SELECT COUNT(*)::text AS count,
            COALESCE(SUM(bonus_balance),0)::text AS bonus
     FROM app_users
     WHERE firebase_uid IS NOT NULL`,
  );
  const row = actual.rows[0];
  compareNumber('users count', Number(row?.count ?? 0), legacy.users.count, failures);
  compareMoney('users bonus balance sum', Number(row?.bonus ?? 0), legacy.users.bonusBalance, failures);
}

async function verifyPackageState(db: Database, failures: string[]) {
  const negativePackages = await db.query<{ count: string }>(
    `SELECT COUNT(*)::text AS count
     FROM customer_packages
     WHERE total_cleanings < 0 OR available_cleanings < 0 OR available_cleanings > total_cleanings`,
  );
  if (Number(negativePackages.rows[0]?.count ?? 0) > 0) {
    failures.push(`customer packages with invalid cleaning counters: ${negativePackages.rows[0].count}`);
  }
  const paidWithoutTarget = await db.query<{ count: string }>(
    `SELECT COUNT(*)::text AS count
     FROM payments
     WHERE status='paid' AND order_id IS NULL AND customer_package_id IS NULL AND payload->>'kind' IS NULL`,
  );
  if (Number(paidWithoutTarget.rows[0]?.count ?? 0) > 0) {
    failures.push(`paid payments without order/package/kind: ${paidWithoutTarget.rows[0].count}`);
  }
  const activePackagesWithoutAddress = await db.query<{ count: string }>(
    `SELECT COUNT(*)::text AS count
     FROM customer_packages
     WHERE status='active' AND address_id IS NULL`,
  );
  if (Number(activePackagesWithoutAddress.rows[0]?.count ?? 0) > 0) {
    failures.push(`active customer packages without address: ${activePackagesWithoutAddress.rows[0].count}`);
  }
}

async function verifyRelationalIntegrity(db: Database, failures: string[]) {
  const checks: Array<{ label: string; sql: string }> = [
    {
      label: 'orders without existing customer',
      sql: `SELECT COUNT(*)::text AS count
            FROM service_orders o
            LEFT JOIN app_users u ON u.id=o.customer_id
            WHERE u.id IS NULL`,
    },
    {
      label: 'orders with missing address',
      sql: `SELECT COUNT(*)::text AS count
            FROM service_orders o
            LEFT JOIN customer_addresses a ON a.id=o.address_id
            WHERE o.address_id IS NOT NULL AND a.id IS NULL`,
    },
    {
      label: 'assigned orders with missing cleaner',
      sql: `SELECT COUNT(*)::text AS count
            FROM service_orders o
            LEFT JOIN app_users c ON c.id=o.cleaner_id
            WHERE o.cleaner_id IS NOT NULL AND c.id IS NULL`,
    },
    {
      label: 'payments without existing customer',
      sql: `SELECT COUNT(*)::text AS count
            FROM payments p
            LEFT JOIN app_users u ON u.id=p.customer_id
            WHERE p.customer_id IS NOT NULL AND u.id IS NULL`,
    },
    {
      label: 'payments with missing order',
      sql: `SELECT COUNT(*)::text AS count
            FROM payments p
            LEFT JOIN service_orders o ON o.id=p.order_id
            WHERE p.order_id IS NOT NULL AND o.id IS NULL`,
    },
    {
      label: 'payments with missing customer package',
      sql: `SELECT COUNT(*)::text AS count
            FROM payments p
            LEFT JOIN customer_packages cp ON cp.id=p.customer_package_id
            WHERE p.customer_package_id IS NOT NULL AND cp.id IS NULL`,
    },
    {
      label: 'orders with missing customer package',
      sql: `SELECT COUNT(*)::text AS count
            FROM service_orders o
            LEFT JOIN customer_packages cp ON cp.id=o.customer_package_id
            WHERE o.customer_package_id IS NOT NULL AND cp.id IS NULL`,
    },
    {
      label: 'payment events with missing payment',
      sql: `SELECT COUNT(*)::text AS count
            FROM payment_events pe
            LEFT JOIN payments p ON p.id=pe.payment_id
            WHERE pe.payment_id IS NOT NULL AND p.id IS NULL`,
    },
    {
      label: 'bonus transactions without existing user',
      sql: `SELECT COUNT(*)::text AS count
            FROM bonus_transactions bt
            LEFT JOIN app_users u ON u.id=bt.user_id
            WHERE u.id IS NULL`,
    },
    {
      label: 'chat participants without existing user',
      sql: `SELECT COUNT(*)::text AS count
            FROM chat_participants cp
            LEFT JOIN app_users u ON u.id=cp.user_id
            WHERE u.id IS NULL`,
    },
    {
      label: 'chat messages without existing sender',
      sql: `SELECT COUNT(*)::text AS count
            FROM chat_messages cm
            LEFT JOIN app_users u ON u.id=cm.sender_id
            WHERE u.id IS NULL`,
    },
    {
      label: 'notifications without existing user',
      sql: `SELECT COUNT(*)::text AS count
            FROM notifications n
            LEFT JOIN app_users u ON u.id=n.user_id
            WHERE u.id IS NULL`,
    },
    {
      label: 'quality checks without existing customer',
      sql: `SELECT COUNT(*)::text AS count
            FROM quality_check_requests q
            LEFT JOIN app_users u ON u.id=q.customer_id
            WHERE u.id IS NULL`,
    },
    {
      label: 'quality checks with missing document file',
      sql: `SELECT COUNT(*)::text AS count
            FROM quality_check_requests q
            LEFT JOIN files f ON f.id=q.document_file_id
            WHERE q.document_file_id IS NOT NULL AND f.id IS NULL`,
    },
    {
      label: 'banners with missing image file',
      sql: `SELECT COUNT(*)::text AS count
            FROM banners b
            LEFT JOIN files f ON f.id=b.image_file_id
            WHERE b.image_file_id IS NOT NULL AND f.id IS NULL`,
    },
    {
      label: 'promotions with missing banner file',
      sql: `SELECT COUNT(*)::text AS count
            FROM promotions p
            LEFT JOIN files f ON f.id=p.banner_file_id
            WHERE p.banner_file_id IS NOT NULL AND f.id IS NULL`,
    },
    {
      label: 'cleaner documents with missing file',
      sql: `SELECT COUNT(*)::text AS count
            FROM cleaner_documents d
            LEFT JOIN files f ON f.id=d.file_id
            WHERE d.file_id IS NOT NULL AND f.id IS NULL`,
    },
  ];
  for (const check of checks) {
    const count = Number((await db.query<{ count: string }>(check.sql)).rows[0]?.count ?? 0);
    if (count > 0) failures.push(`${check.label}: ${count}`);
  }

  const bonusBalanceMismatch = await db.query<{ user_id: string; stored: string; calculated: string }>(
    `SELECT u.id AS user_id,
            u.bonus_balance::text AS stored,
            COALESCE(SUM(bt.amount),0)::text AS calculated
     FROM app_users u
     LEFT JOIN bonus_transactions bt ON bt.user_id=u.id
     GROUP BY u.id, u.bonus_balance
     HAVING ABS(u.bonus_balance - COALESCE(SUM(bt.amount),0)) > 0.01
     LIMIT 10`,
  );
  if (bonusBalanceMismatch.rows.length > 0) {
    failures.push(`bonus balance mismatches: ${JSON.stringify(bonusBalanceMismatch.rows)}`);
  }
}

async function compareStatusCounts(db: Database, table: string, label: string, expected: Record<string, number>, failures: string[]) {
  const rows = (await db.query<{ status: string; count: string }>(
    `SELECT status::text, COUNT(*)::text AS count
     FROM ${table}
     WHERE legacy_firestore_id IS NOT NULL
     GROUP BY status::text`,
  )).rows;
  const actual = Object.fromEntries(rows.map((row) => [row.status, Number(row.count)]));
  for (const [status, count] of Object.entries(expected)) {
    compareNumber(`${label} status ${status}`, actual[status] ?? 0, count, failures);
  }
}

async function collectLegacyStats(inputDir: string, collections: Record<string, number>): Promise<LegacyStats> {
  const stats: LegacyStats = {
    payments: { count: 0, amount: 0, bonus: 0, byStatus: {} },
    orders: { count: 0, amount: 0, addonItemOrders: 0, byStatus: {} },
    users: { count: 0, bonusBalance: 0 },
  };
  for (const collection of Object.keys(collections)) {
    const rows = JSON.parse(await fs.readFile(path.join(inputDir, `${collection}.json`), 'utf8')) as ExportRow[];
    const key = normalizeCollection(collection);
    for (const row of rows) {
      if (['payments', 'paymentrequests', 'invoices'].includes(key)) collectPaymentStats(row, stats);
      if (['orders', 'serviceorders', 'cleanings'].includes(key)) collectOrderStats(row, stats);
      if (['users', 'clients', 'customers', 'cleaners', 'admins'].includes(key)) collectUserStats(row, stats);
    }
  }
  return stats;
}

function collectPaymentStats(row: ExportRow, stats: LegacyStats) {
  const amount = number(row.data, ['amount', 'sum', 'payableAmount', 'payable_amount']);
  if (amount == null) return;
  stats.payments.count += 1;
  stats.payments.amount += amount;
  stats.payments.bonus += number(row.data, ['bonusAmount', 'bonus_amount', 'bonusSpent']) ?? 0;
  inc(stats.payments.byStatus, paymentStatusFromData(row.data));
}

function collectOrderStats(row: ExportRow, stats: LegacyStats) {
  const customer = text(row.data, ['customerId', 'customer_id', 'userId', 'clientId', 'customerPhone', 'phone', 'clientPhone']);
  if (!customer) return;
  stats.orders.count += 1;
  stats.orders.amount += number(row.data, ['totalAmount', 'total_amount', 'amount']) ?? 0;
  if (hasAddonItems(row.data)) stats.orders.addonItemOrders += 1;
  inc(stats.orders.byStatus, orderStatusFromData(row.data));
}

function collectUserStats(row: ExportRow, stats: LegacyStats) {
  if (!text(row.data, ['phone', 'phoneNumber', 'mobile', 'tel'])) return;
  stats.users.count += 1;
  stats.users.bonusBalance += number(row.data, ['bonusBalance', 'bonus_balance', 'bonuses']) ?? 0;
}

function compareNumber(label: string, actual: number, expected: number, failures: string[]) {
  if (actual !== expected) failures.push(`${label}: expected ${expected}, actual ${actual}`);
}

function compareMoney(label: string, actual: number, expected: number, failures: string[]) {
  if (Math.abs(actual - expected) > 0.01) failures.push(`${label}: expected ${expected}, actual ${actual}`);
}

function inc(target: Record<string, number>, key: string) {
  target[key] = (target[key] ?? 0) + 1;
}

function hasAddonItems(data: Record<string, unknown>) {
  return arrayValue(data, ['addons', 'addonIds', 'extras', 'additionalServices', 'selectedAddons', 'orderAddons']).length > 0;
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

function arrayValue(data: Record<string, unknown>, keys: string[]): unknown[] {
  for (const key of keys) {
    const value = data[key];
    if (Array.isArray(value)) return value;
    if (typeof value === 'string' && value.trim()) {
      try {
        const parsed = JSON.parse(value);
        if (Array.isArray(parsed)) return parsed;
      } catch {
        return value.split(',').map((part) => part.trim()).filter(Boolean);
      }
    }
  }
  return [];
}

function paymentStatusFromData(data: Record<string, unknown>) {
  return normalizeMigrationPaymentStatus(text(data, ['status', 'paymentStatus']));
}

function orderStatusFromData(data: Record<string, unknown>) {
  return normalizeMigrationOrderStatus(text(data, ['status', 'orderStatus']));
}
