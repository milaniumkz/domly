import fs from 'fs/promises';
import path from 'path';
import { createHash } from 'crypto';
import { Database } from '../infrastructure/db/Database';
import { env } from '../common/env';
import { normalizePhone } from '../modules/domainServices';
import { StorageService } from '../modules/integrations';
import { normalizeMigrationOrderStatus, normalizeMigrationPaymentStatus } from './migration-utils';

type ExportRow = { id: string; path?: string; parentPath?: string | null; data: Record<string, unknown> };
type Manifest = { collections: Record<string, number>; storage?: { bucket: string; files: number; downloaded: boolean } | null };
type StorageManifestRow = {
  bucket: string;
  name: string;
  localPath?: string | null;
  contentType?: string | null;
  size?: number | null;
  timeCreated?: string | null;
};

async function main() {
  const inputDir = process.env.FIREBASE_EXPORT_DIR ?? path.resolve(process.cwd(), 'firebase-export');
  const manifest = JSON.parse(await fs.readFile(path.join(inputDir, 'manifest.json'), 'utf8')) as Manifest;
  const db = new Database(env.databaseUrl);
  const stats: Record<string, number> = {};

  try {
    const collections = await loadExportCollections(inputDir, manifest.collections);
    for (const { collection, rows } of collections) {
      for (const row of rows) await importLegacy(db, collection, row);
      stats[collection] = rows.length;
      console.log(`Stored ${rows.length} legacy docs from ${collection}`);
    }

    const storageStats = await importStorageManifest(db, inputDir).catch((error) => {
      if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
      return null;
    });
    if (storageStats) stats.storageFiles = storageStats.files;

    for (const { collection, rows } of sortCollectionsForMapping(collections)) {
      for (const row of rows) await importMapped(db, collection, row);
      console.log(`Mapped ${rows.length} docs from ${collection}`);
    }
  } finally {
    await db.close();
  }

  console.log(JSON.stringify({ ok: true, stats }, null, 2));
}

async function loadExportCollections(inputDir: string, collections: Record<string, number>) {
  const result: Array<{ collection: string; rows: ExportRow[]; index: number }> = [];
  let index = 0;
  for (const collection of Object.keys(collections)) {
    const rows = JSON.parse(await fs.readFile(path.join(inputDir, `${collection}.json`), 'utf8')) as ExportRow[];
    result.push({ collection, rows, index: index++ });
  }
  return result;
}

function sortCollectionsForMapping<T extends { collection: string; index: number }>(collections: T[]) {
  return [...collections].sort((left, right) => {
    const priorityDiff = collectionImportPriority(left.collection) - collectionImportPriority(right.collection);
    return priorityDiff || left.index - right.index;
  });
}

function collectionImportPriority(collection: string) {
  const key = normalizeCollection(collection);
  if (['users', 'clients', 'customers', 'cleaners', 'admins'].includes(key)) return 10;
  if (['packages', 'catalogpackages', 'servicepackages', 'tariffs', 'addongroups', 'addoncategories', 'servicecategories', 'addons', 'extras', 'additionalservices', 'services', 'zones', 'servicezones', 'districts', 'coveragezones', 'houses', 'connectedhouses', 'addresses', 'homes', 'translations', 'apptranslations', 'app_translations', 'settings', 'appsettings', 'config', 'contentpages', 'content', 'infocontent', 'legalpages', 'policies', 'banners', 'homebanners', 'promotions', 'promo', 'promos', 'actions'].includes(key)) return 20;
  if (['customeraddresses', 'clientaddresses', 'useraddresses', 'userhomes'].includes(key)) return 30;
  if (['customerpackages', 'userpackages', 'subscriptions', 'purchasedpackages', 'clientpackages'].includes(key)) return 40;
  if (['orders', 'serviceorders', 'cleanings', 'preorders', 'preliminaryorders', 'qualitychecks', 'areachecks', 'squarechecks'].includes(key)) return 50;
  if (['payments', 'paymentrequests', 'invoices'].includes(key)) return 60;
  if (['notifications', 'pushnotifications', 'complaints', 'claims', 'reviews', 'ratings', 'photoreports', 'photo_reports', 'orderphotoreports', 'chats'].includes(key)) return 70;
  if (key.startsWith('chats') && key.includes('messages')) return 80;
  if (['messages'].includes(key)) return 80;
  return 90;
}

async function importStorageManifest(db: Database, inputDir: string) {
  const rows = JSON.parse(await fs.readFile(path.join(inputDir, 'storage-manifest.json'), 'utf8')) as StorageManifestRow[];
  const uploadToMinio = process.env.IMPORT_STORAGE_TO_MINIO === 'true';
  const storage = uploadToMinio ? new StorageService() : null;
  for (const row of rows) {
    const objectKey = `firebase/${row.name}`;
    let publicUrl: string | null = null;
    if (storage && row.localPath) {
      const localFile = path.join(inputDir, row.localPath);
      const buffer = await fs.readFile(localFile);
      publicUrl = await storage.uploadBuffer(objectKey, buffer, row.contentType ?? undefined);
    }
    await db.query(
      `INSERT INTO files (bucket, object_key, mime_type, size_bytes, public_url, created_at)
       VALUES ($1,$2,$3,$4,$5,COALESCE($6,NOW()))
       ON CONFLICT (bucket, object_key) DO UPDATE SET
         mime_type=EXCLUDED.mime_type,
         size_bytes=EXCLUDED.size_bytes,
         public_url=COALESCE(EXCLUDED.public_url, files.public_url)`,
      [
        storage ? env.minioBucket : row.bucket,
        objectKey,
        row.contentType ?? null,
        row.size ?? null,
        publicUrl,
        row.timeCreated ? new Date(row.timeCreated) : null,
      ],
    );
  }
  console.log(`Imported ${rows.length} Firebase Storage files${uploadToMinio ? ' into MinIO' : ' as metadata'}`);
  return { files: rows.length };
}

async function importLegacy(db: Database, collection: string, row: ExportRow) {
  await db.query(
    `INSERT INTO legacy_firestore_documents (collection_name, document_id, payload)
     VALUES ($1,$2,$3)
     ON CONFLICT (collection_name, document_id) DO UPDATE SET payload=$3, exported_at=NOW()`,
    [collection, row.id, row.data],
  );
}

async function importMapped(db: Database, collection: string, row: ExportRow) {
  const key = normalizeCollection(collection);
  if (['users', 'clients', 'customers', 'cleaners', 'admins'].includes(key)) return importUser(db, key, row);
  if (['customeraddresses', 'clientaddresses', 'useraddresses', 'userhomes'].includes(key)) return importCustomerAddress(db, row);
  if (['customerpackages', 'userpackages', 'subscriptions', 'purchasedpackages', 'clientpackages'].includes(key)) return importCustomerPackage(db, row);
  if (['packages', 'catalogpackages', 'servicepackages', 'tariffs'].includes(key)) return importPackage(db, row);
  if (['addongroups', 'addoncategories', 'servicecategories'].includes(key)) return importAddonGroup(db, row);
  if (['addons', 'extras', 'additionalservices', 'services'].includes(key)) return importAddon(db, row);
  if (['zones', 'servicezones', 'districts', 'coveragezones'].includes(key)) return importZone(db, row);
  if (['houses', 'connectedhouses', 'addresses', 'homes'].includes(key)) {
    return hasCustomerReference(row.data) ? importCustomerAddress(db, row) : importHouse(db, row);
  }
  if (['translations', 'apptranslations', 'app_translations'].includes(key)) return importTranslation(db, row);
  if (['banners', 'homebanners'].includes(key)) return importBanner(db, row);
  if (['promotions', 'promo', 'promos', 'actions'].includes(key)) return importPromotion(db, row);
  if (['contentpages', 'content', 'infocontent', 'legalpages', 'policies'].includes(key)) return importContentPage(db, row);
  if (['orders', 'serviceorders', 'cleanings'].includes(key)) return importOrder(db, row);
  if (['payments', 'paymentrequests', 'invoices'].includes(key)) return importPayment(db, row);
  if (['preorders', 'preliminaryorders'].includes(key)) return importPreorder(db, row);
  if (['qualitychecks', 'areachecks', 'squarechecks'].includes(key)) return importQualityCheck(db, row);
  if (['notifications', 'pushnotifications'].includes(key)) return importNotification(db, row);
  if (['complaints', 'claims'].includes(key)) return importComplaint(db, row);
  if (['reviews', 'ratings'].includes(key)) return importReview(db, row);
  if (['photoreports', 'photo_reports', 'orderphotoreports'].includes(key)) return importPhotoReport(db, row);
  if (key.startsWith('chats') && key.includes('messages')) return importChatMessage(db, row);
  if (['chats', 'messages'].includes(key)) return key === 'chats' ? importChat(db, row) : importChatMessage(db, row);
  if (['settings', 'appsettings', 'config'].includes(key)) return importSetting(db, row);
}

async function importUser(db: Database, collectionKey: string, row: ExportRow) {
  const data = row.data;
  const phone = text(data, ['phone', 'phoneNumber', 'mobile', 'tel']);
  if (!phone) return;
  const role = roleFromData(collectionKey, data);
  await db.query(
    `INSERT INTO app_users (firebase_uid, role, phone, full_name, email, language, rating, bonus_balance, status, is_phone_verified, created_at, updated_at)
     VALUES ($1,$2,$3,$4,$5,COALESCE($6,'ru'),COALESCE($7,5),COALESCE($8,0),COALESCE($9,'new'),COALESCE($10,TRUE),COALESCE($11,NOW()),NOW())
     ON CONFLICT (phone) DO UPDATE SET
       firebase_uid=COALESCE(app_users.firebase_uid, EXCLUDED.firebase_uid),
       role=EXCLUDED.role,
       full_name=COALESCE(EXCLUDED.full_name, app_users.full_name),
       email=COALESCE(EXCLUDED.email, app_users.email),
       language=EXCLUDED.language,
       rating=EXCLUDED.rating,
       bonus_balance=EXCLUDED.bonus_balance,
       status=EXCLUDED.status,
       updated_at=NOW()`,
    [
      text(data, ['uid', 'firebaseUid', 'firebase_uid']) ?? row.id,
      role,
      normalizePhone(phone),
      text(data, ['fullName', 'full_name', 'name', 'fio', 'displayName']),
      text(data, ['email']),
      text(data, ['language', 'lang']),
      number(data, ['rating']),
      number(data, ['bonusBalance', 'bonus_balance', 'bonuses']),
      statusFromData(data),
      bool(data, ['isPhoneVerified', 'phoneVerified', 'verified']),
      dateValue(data, ['createdAt', 'created_at', 'registeredAt']),
    ],
  );
  if (role === 'cleaner') {
    await db.query(
      `INSERT INTO cleaner_profiles (user_id, city, registration_status, verification_status, work_start_date, monthly_area_limit, daily_work_limit_minutes, created_at, updated_at)
       SELECT id, COALESCE($2,'Астана'), COALESCE($3,'pending'), COALESCE($4,'pending'), $5, COALESCE($6,220), COALESCE($7,540), NOW(), NOW()
       FROM app_users WHERE phone=$1
       ON CONFLICT (user_id) DO UPDATE SET
         city=EXCLUDED.city,
         registration_status=EXCLUDED.registration_status,
         verification_status=EXCLUDED.verification_status,
         work_start_date=COALESCE(EXCLUDED.work_start_date, cleaner_profiles.work_start_date),
         monthly_area_limit=EXCLUDED.monthly_area_limit,
         daily_work_limit_minutes=EXCLUDED.daily_work_limit_minutes,
         updated_at=NOW()`,
      [
        normalizePhone(phone),
        text(data, ['city']),
        statusFromData(data),
        statusFromData(data, ['verificationStatus', 'verification_status', 'documentStatus']),
        dateValue(data, ['workStartDate', 'work_start_date', 'verifiedAt', 'createdAt']),
        number(data, ['monthlyAreaLimit', 'monthly_area_limit']),
        number(data, ['dailyWorkLimitMinutes', 'daily_work_limit_minutes']),
      ],
    );
  }
  if (role === 'customer') await importCustomerAddress(db, row);
}

async function importCustomerAddress(db: Database, row: ExportRow) {
  const data = row.data;
  const userId = await findUserId(db, data, ['userId', 'user_id', 'customerId', 'customer_id', 'clientId'], ['phone', 'userPhone', 'customerPhone', 'clientPhone']);
  if (!userId) return;
  const street = text(data, ['street', 'streetRu', 'street_ru', 'addressStreet', 'address', 'homeAddress']);
  const house = text(data, ['house', 'houseNumber', 'building', 'home', 'addressHouse']);
  const area = number(data, ['area', 'square', 'apartmentArea', 'flatArea']);
  if (!street || !house) return;
  await db.query(
    `INSERT INTO customer_addresses
       (user_id, city, settlement, street, house, apartment, entrance, floor, access_comment, area, verified_area, latitude, longitude, is_primary, created_at, updated_at)
     VALUES ($1,COALESCE($2,'Астана'),$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,COALESCE($14,TRUE),COALESCE($15,NOW()),NOW())
     ON CONFLICT DO NOTHING`,
    [
      userId,
      text(data, ['city']),
      text(data, ['settlement', 'village', 'district']),
      street,
      house,
      text(data, ['apartment', 'flat', 'kv']),
      text(data, ['entrance', 'podiezd']),
      text(data, ['floor']),
      text(data, ['accessComment', 'access_comment', 'comment']),
      area,
      number(data, ['verifiedArea', 'verified_area', 'approvedArea']) ?? area,
      number(data, ['latitude', 'lat']),
      number(data, ['longitude', 'lng', 'lon']),
      bool(data, ['isPrimary', 'is_primary', 'primary']),
      dateValue(data, ['createdAt', 'created_at']),
    ],
  );
}

async function importCustomerPackage(db: Database, row: ExportRow) {
  const data = row.data;
  const customerId = await findUserId(db, data, ['customerId', 'customer_id', 'userId', 'clientId'], ['customerPhone', 'phone', 'clientPhone']);
  if (!customerId) return;
  const packageId = await findPackageId(db, data);
  if (!packageId) return;
  const addressId = await findCustomerAddressId(db, customerId, data);
  const total = number(data, ['totalCleanings', 'total_cleanings', 'cleaningCount', 'visits', 'count']) ?? await packageCleaningCount(db, packageId);
  const available = number(data, ['availableCleanings', 'available_cleanings', 'remainingCleanings', 'left', 'remaining']) ?? total;
  await db.query(
    `INSERT INTO customer_packages
       (legacy_firestore_id, customer_id, package_id, address_id, total_cleanings, available_cleanings, months, period_start, period_end, status, created_at, updated_at)
     VALUES ($1,$2,$3,$4,COALESCE($5,1),COALESCE($6,$5,1),COALESCE($7,1),COALESCE($8,CURRENT_DATE),$9,COALESCE($10,'active'),COALESCE($11,NOW()),NOW())
     ON CONFLICT (legacy_firestore_id) DO UPDATE SET
       package_id=EXCLUDED.package_id,
       address_id=COALESCE(EXCLUDED.address_id, customer_packages.address_id),
       total_cleanings=EXCLUDED.total_cleanings,
       available_cleanings=EXCLUDED.available_cleanings,
       months=EXCLUDED.months,
       period_start=EXCLUDED.period_start,
       period_end=EXCLUDED.period_end,
       status=EXCLUDED.status,
       updated_at=NOW()`,
    [
      row.id,
      customerId,
      packageId,
      addressId,
      total,
      available,
      number(data, ['months', 'durationMonths']),
      dateOnly(data, ['periodStart', 'period_start', 'startDate', 'createdAt']),
      dateOnly(data, ['periodEnd', 'period_end', 'endDate', 'expiresAt']),
      packageStatusFromData(data),
      dateValue(data, ['createdAt', 'created_at']),
    ],
  );
}

async function importPackage(db: Database, row: ExportRow) {
  const data = row.data;
  const nameRu = text(data, ['nameRu', 'name_ru', 'titleRu', 'title_ru', 'name', 'title']);
  if (!nameRu) return;
  await db.query(
    `INSERT INTO catalog_packages (name_ru, name_kk, description_ru, description_kk, cleaning_count, months, base_price, price_per_m2, active, features)
     VALUES ($1,$2,$3,$4,COALESCE($5,1),COALESCE($6,1),COALESCE($7,0),COALESCE($8,0),COALESCE($9,TRUE),COALESCE($10,'{}'::jsonb))
     ON CONFLICT (name_ru, cleaning_count, months) DO UPDATE SET
       name_kk=EXCLUDED.name_kk,
       description_ru=EXCLUDED.description_ru,
       description_kk=EXCLUDED.description_kk,
       base_price=EXCLUDED.base_price,
       price_per_m2=EXCLUDED.price_per_m2,
       active=EXCLUDED.active,
       features=EXCLUDED.features,
       updated_at=NOW()`,
    [
      nameRu,
      text(data, ['nameKk', 'name_kk', 'titleKk', 'title_kk']),
      text(data, ['descriptionRu', 'description_ru', 'description', 'info']),
      text(data, ['descriptionKk', 'description_kk']),
      number(data, ['cleaningCount', 'cleaning_count', 'visits', 'count']),
      number(data, ['months', 'durationMonths']),
      number(data, ['basePrice', 'base_price', 'price', 'amount']),
      number(data, ['pricePerM2', 'price_per_m2', 'sqmPrice']),
      bool(data, ['active', 'isActive']),
      json(data, ['features', 'items', 'included']),
    ],
  );
}

async function importAddonGroup(db: Database, row: ExportRow) {
  const data = row.data;
  const titleRu = text(data, ['titleRu', 'title_ru', 'nameRu', 'name_ru', 'title', 'name']);
  if (!titleRu) return;
  await db.query(
    `INSERT INTO addon_groups (title_ru, title_kk, sort_order, active)
     VALUES ($1,$2,COALESCE($3,0),COALESCE($4,TRUE))
     ON CONFLICT (title_ru) DO UPDATE SET title_kk=EXCLUDED.title_kk, sort_order=EXCLUDED.sort_order, active=EXCLUDED.active`,
    [titleRu, text(data, ['titleKk', 'title_kk', 'nameKk', 'name_kk']), number(data, ['sortOrder', 'sort_order', 'order']), bool(data, ['active', 'isActive'])],
  );
}

async function importAddon(db: Database, row: ExportRow) {
  const data = row.data;
  const titleRu = text(data, ['titleRu', 'title_ru', 'nameRu', 'name_ru', 'title', 'name']);
  if (!titleRu) return;
  const groupTitle = text(data, ['groupTitle', 'group', 'category', 'categoryRu']);
  const groupId = groupTitle ? await ensureAddonGroup(db, groupTitle) : null;
  await db.query(
    `INSERT INTO catalog_addons
       (group_id, title_ru, title_kk, description_ru, description_kk, hint_ru, hint_kk, pricing_type, price, duration_minutes, paid_separately, active, sort_order)
     VALUES ($1,$2,$3,$4,$5,$6,$7,COALESCE($8,'fixed'),COALESCE($9,0),COALESCE($10,0),COALESCE($11,FALSE),COALESCE($12,TRUE),COALESCE($13,0))
     ON CONFLICT (title_ru) DO UPDATE SET
       group_id=EXCLUDED.group_id,
       title_kk=EXCLUDED.title_kk,
       description_ru=EXCLUDED.description_ru,
       description_kk=EXCLUDED.description_kk,
       hint_ru=EXCLUDED.hint_ru,
       hint_kk=EXCLUDED.hint_kk,
       pricing_type=EXCLUDED.pricing_type,
       price=EXCLUDED.price,
       duration_minutes=EXCLUDED.duration_minutes,
       paid_separately=EXCLUDED.paid_separately,
       active=EXCLUDED.active,
       sort_order=EXCLUDED.sort_order,
       updated_at=NOW()`,
    [
      groupId,
      titleRu,
      text(data, ['titleKk', 'title_kk', 'nameKk', 'name_kk']),
      text(data, ['descriptionRu', 'description_ru', 'description', 'info']),
      text(data, ['descriptionKk', 'description_kk']),
      text(data, ['hintRu', 'hint_ru', 'hint', 'shortDescription']),
      text(data, ['hintKk', 'hint_kk']),
      text(data, ['pricingType', 'pricing_type']),
      number(data, ['price', 'amount']),
      number(data, ['durationMinutes', 'duration_minutes', 'minutes']),
      bool(data, ['paidSeparately', 'paid_separately']),
      bool(data, ['active', 'isActive']),
      number(data, ['sortOrder', 'sort_order', 'order']),
    ],
  );
}

async function importZone(db: Database, row: ExportRow) {
  const data = row.data;
  const nameRu = text(data, ['nameRu', 'name_ru', 'titleRu', 'title_ru', 'name', 'title']);
  if (!nameRu) return;
  await db.query(
    `INSERT INTO service_zones (name_ru, name_kk, city, polygon, active)
     VALUES ($1,$2,COALESCE($3,'Астана'),$4,COALESCE($5,TRUE))
     ON CONFLICT (city, name_ru) DO UPDATE SET name_kk=EXCLUDED.name_kk, polygon=EXCLUDED.polygon, active=EXCLUDED.active`,
    [nameRu, text(data, ['nameKk', 'name_kk', 'titleKk', 'title_kk']), text(data, ['city']), json(data, ['polygon', 'geoJson']), bool(data, ['active', 'isActive'])],
  );
}

async function importHouse(db: Database, row: ExportRow) {
  const data = row.data;
  const streetRu = text(data, ['streetRu', 'street_ru', 'street', 'addressStreet']);
  const house = text(data, ['house', 'houseNumber', 'building']);
  if (!streetRu || !house) return;
  await db.query(
    `INSERT INTO connected_houses
       (city, street_ru, street_kk, house, residential_complex_ru, residential_complex_kk, latitude, longitude, active)
     VALUES (COALESCE($1,'Астана'),$2,$3,$4,$5,$6,$7,$8,COALESCE($9,TRUE))
     ON CONFLICT (city, street_ru, house) DO UPDATE SET
       street_kk=EXCLUDED.street_kk,
       residential_complex_ru=EXCLUDED.residential_complex_ru,
       residential_complex_kk=EXCLUDED.residential_complex_kk,
       latitude=EXCLUDED.latitude,
       longitude=EXCLUDED.longitude,
       active=EXCLUDED.active`,
    [
      text(data, ['city']),
      streetRu,
      text(data, ['streetKk', 'street_kk']),
      house,
      text(data, ['residentialComplexRu', 'residential_complex_ru', 'complex', 'jk']),
      text(data, ['residentialComplexKk', 'residential_complex_kk']),
      number(data, ['latitude', 'lat']),
      number(data, ['longitude', 'lng', 'lon']),
      bool(data, ['active', 'isActive']),
    ],
  );
}

async function importTranslation(db: Database, row: ExportRow) {
  const data = row.data;
  const key = text(data, ['key']) ?? row.id;
  const ru = text(data, ['ru', 'valueRu', 'textRu']);
  if (!key || !ru) return;
  await db.query(
    `INSERT INTO translations (key, ru, kk, namespace, updated_at)
     VALUES ($1,$2,$3,COALESCE($4,'app'),NOW())
     ON CONFLICT (key) DO UPDATE SET ru=$2, kk=$3, namespace=COALESCE($4,'app'), updated_at=NOW()`,
    [key, ru, text(data, ['kk', 'valueKk', 'textKk']), text(data, ['namespace'])],
  );
}

async function importBanner(db: Database, row: ExportRow) {
  const data = row.data;
  const titleRu = text(data, ['titleRu', 'title_ru', 'title', 'name']) ?? 'Баннер';
  const imageFileId = await findFileId(db, data, ['imageUrl', 'image_url', 'url', 'photoUrl', 'filePath', 'storagePath']);
  await db.query(
    `INSERT INTO banners (title_ru, title_kk, description_ru, description_kk, image_file_id, target_type, target_value, placement, sort_order, active)
     VALUES ($1,$2,$3,$4,$5,COALESCE($6,'modal'),$7,COALESCE($8,'home_top'),COALESCE($9,0),COALESCE($10,TRUE))`,
    [titleRu, text(data, ['titleKk', 'title_kk']), text(data, ['descriptionRu', 'description_ru', 'description']), text(data, ['descriptionKk', 'description_kk']), imageFileId, text(data, ['targetType', 'target_type']), text(data, ['targetValue', 'target_value', 'route', 'url']), text(data, ['placement']), number(data, ['sortOrder', 'sort_order']), bool(data, ['active', 'isActive'])],
  );
}

async function importPromotion(db: Database, row: ExportRow) {
  const data = row.data;
  const titleRu = text(data, ['titleRu', 'title_ru', 'title', 'name']);
  if (!titleRu) return;
  const bannerFileId = await findFileId(db, data, ['bannerUrl', 'banner_url', 'imageUrl', 'image_url', 'photoUrl', 'filePath', 'storagePath']);
  await db.query(
    `INSERT INTO promotions (title_ru, title_kk, description_ru, description_kk, banner_file_id, reward_type, reward_value, max_bonus_spend_percent, once_per_customer, active, starts_at, ends_at)
     VALUES ($1,$2,$3,$4,$5,COALESCE($6,'fixed'),COALESCE($7,0),$8,COALESCE($9,FALSE),COALESCE($10,TRUE),$11,$12)`,
    [titleRu, text(data, ['titleKk', 'title_kk']), text(data, ['descriptionRu', 'description_ru', 'description']), text(data, ['descriptionKk', 'description_kk']), bannerFileId, text(data, ['rewardType', 'reward_type']), number(data, ['rewardValue', 'reward_value', 'bonus', 'amount']), number(data, ['maxBonusSpendPercent', 'max_bonus_spend_percent']), bool(data, ['oncePerCustomer', 'once_per_customer']), bool(data, ['active', 'isActive']), dateValue(data, ['startsAt', 'starts_at']), dateValue(data, ['endsAt', 'ends_at'])],
  );
}

async function importContentPage(db: Database, row: ExportRow) {
  const data = row.data;
  const slug = text(data, ['slug', 'key', 'id']) ?? row.id;
  const titleRu = text(data, ['titleRu', 'title_ru', 'title', 'name']) ?? slug;
  const bodyRu = text(data, ['bodyRu', 'body_ru', 'body', 'text', 'content']);
  if (!bodyRu) return;
  await db.query(
    `INSERT INTO content_pages (slug, title_ru, title_kk, body_ru, body_kk, kind, active)
     VALUES ($1,$2,$3,$4,$5,COALESCE($6,'info'),COALESCE($7,TRUE))
     ON CONFLICT (slug) DO UPDATE SET
       title_ru=EXCLUDED.title_ru,
       title_kk=EXCLUDED.title_kk,
       body_ru=EXCLUDED.body_ru,
       body_kk=EXCLUDED.body_kk,
       kind=EXCLUDED.kind,
       active=EXCLUDED.active,
       updated_at=NOW()`,
    [slug, titleRu, text(data, ['titleKk', 'title_kk']), bodyRu, text(data, ['bodyKk', 'body_kk', 'textKk', 'contentKk']), text(data, ['kind', 'type']), bool(data, ['active', 'isActive'])],
  );
}

async function importOrder(db: Database, row: ExportRow) {
  const data = row.data;
  const customerId = await findUserId(db, data, ['customerId', 'customer_id', 'userId', 'clientId'], ['customerPhone', 'phone', 'clientPhone']);
  if (!customerId) return;
  const packageId = await findPackageId(db, data);
  const order = (await db.query<{ id: string }>(
    `INSERT INTO service_orders
       (legacy_firestore_id, customer_id, package_id, scheduled_date, start_time, end_time, estimated_duration_minutes,
        area, status, base_amount, addon_amount, bonus_spent, total_amount, payable_amount, quality_required, created_at, updated_at)
     VALUES ($1,$2,$3,$4,$5,$6,COALESCE($7,0),$8,COALESCE($9,'pending_assignment'),COALESCE($10,0),COALESCE($11,0),COALESCE($12,0),COALESCE($13,0),COALESCE($14,$13,0),COALESCE($15,FALSE),COALESCE($16,NOW()),NOW())
     ON CONFLICT (legacy_firestore_id) DO UPDATE SET
       scheduled_date=EXCLUDED.scheduled_date,
       start_time=EXCLUDED.start_time,
       end_time=EXCLUDED.end_time,
       status=EXCLUDED.status,
       area=EXCLUDED.area,
       total_amount=EXCLUDED.total_amount,
       payable_amount=EXCLUDED.payable_amount,
       updated_at=NOW()
     RETURNING id`,
    [
      row.id,
      customerId,
      packageId,
      dateOnly(data, ['scheduledDate', 'scheduled_date', 'date']),
      timeValue(data, ['startTime', 'start_time', 'timeFrom']),
      timeValue(data, ['endTime', 'end_time', 'timeTo']),
      number(data, ['estimatedDurationMinutes', 'durationMinutes', 'duration']),
      number(data, ['area', 'square', 'apartmentArea']),
      orderStatusFromData(data),
      number(data, ['baseAmount', 'base_amount', 'basePrice']),
      number(data, ['addonAmount', 'addon_amount', 'extrasAmount']),
      number(data, ['bonusSpent', 'bonus_spent']),
      number(data, ['totalAmount', 'total_amount', 'amount']),
      number(data, ['payableAmount', 'payable_amount', 'amountToPay']),
      bool(data, ['qualityRequired', 'quality_required']),
      dateValue(data, ['createdAt', 'created_at']),
    ],
  )).rows[0];
  if (order?.id) await importOrderAddons(db, order.id, data);
}

async function importPayment(db: Database, row: ExportRow) {
  const data = row.data;
  const customerId = await findUserId(db, data, ['customerId', 'customer_id', 'userId', 'clientId'], ['customerPhone', 'phone', 'clientPhone']);
  const orderId = text(data, ['orderId', 'order_id'])
    ? (await db.query<{ id: string }>(`SELECT id FROM service_orders WHERE legacy_firestore_id=$1`, [text(data, ['orderId', 'order_id'])])).rows[0]?.id
    : null;
  await db.query(
    `INSERT INTO payments
       (legacy_firestore_id, customer_id, order_id, provider, status, amount, bonus_amount, external_id, invoice_phone, payload, paid_at, created_at, updated_at)
     VALUES ($1,$2,$3,COALESCE($4,'manual'),COALESCE($5,'pending'),COALESCE($6,0),COALESCE($7,0),$8,$9,$10,$11,COALESCE($12,NOW()),NOW())
     ON CONFLICT (legacy_firestore_id) DO UPDATE SET
       status=EXCLUDED.status,
       amount=EXCLUDED.amount,
       bonus_amount=EXCLUDED.bonus_amount,
       payload=EXCLUDED.payload,
       paid_at=EXCLUDED.paid_at,
       updated_at=NOW()`,
    [
      row.id,
      customerId,
      orderId,
      providerFromData(data),
      paymentStatusFromData(data),
      number(data, ['amount', 'sum', 'payableAmount', 'payable_amount']),
      number(data, ['bonusAmount', 'bonus_amount', 'bonusSpent']),
      text(data, ['externalId', 'external_id', 'invoiceId']),
      text(data, ['invoicePhone', 'phone']),
      data,
      dateValue(data, ['paidAt', 'paid_at']),
      dateValue(data, ['createdAt', 'created_at']),
    ],
  );
}

async function importOrderAddons(db: Database, orderId: string, data: Record<string, unknown>) {
  const items = addonItemsFromData(data);
  if (items.length === 0) return;
  await db.query(`DELETE FROM order_addons WHERE order_id=$1`, [orderId]);
  for (const item of items) {
    const addonId = await findAddonId(db, item);
    if (!addonId) continue;
    await db.query(
      `INSERT INTO order_addons (order_id, addon_id, quantity, price, duration_minutes, payment_status, created_at)
       VALUES ($1,$2,COALESCE($3,1),COALESCE($4,0),COALESCE($5,0),COALESCE($6,'paid'),COALESCE($7,NOW()))`,
      [
        orderId,
        addonId,
        item.quantity,
        item.price,
        item.durationMinutes,
        paymentStatusFromData({ status: item.paymentStatus ?? text(data, ['addonPaymentStatus', 'paymentStatus', 'status']) ?? 'paid' }),
        dateValue(data, ['createdAt', 'created_at']),
      ],
    );
  }
}

function addonItemsFromData(data: Record<string, unknown>) {
  const raw = arrayValue(data, ['addons', 'addonIds', 'extras', 'additionalServices', 'selectedAddons', 'orderAddons']);
  return raw.map((value) => {
    if (typeof value === 'string' || typeof value === 'number') {
      return { id: String(value), title: String(value) };
    }
    if (value && typeof value === 'object') {
      const item = value as Record<string, unknown>;
      return {
        id: text(item, ['id', 'addonId', 'addon_id', 'serviceId']),
        title: text(item, ['title', 'name', 'titleRu', 'title_ru', 'serviceName']),
        quantity: number(item, ['quantity', 'qty', 'count']),
        price: number(item, ['price', 'amount']),
        durationMinutes: number(item, ['durationMinutes', 'duration_minutes', 'minutes']),
        paymentStatus: text(item, ['paymentStatus', 'payment_status', 'status']),
      };
    }
    return {};
  }).filter((item) => item.id || item.title);
}

async function importPreorder(db: Database, row: ExportRow) {
  const data = row.data;
  const customerId = await findUserId(db, data, ['customerId', 'customer_id', 'userId', 'clientId'], ['customerPhone', 'phone', 'clientPhone']);
  if (!customerId) return;
  await db.query(
    `INSERT INTO preorders (customer_id, desired_date, desired_time, area, status, admin_comment, created_at, updated_at)
     VALUES ($1,COALESCE($2,CURRENT_DATE),$3,$4,COALESCE($5,'new'),$6,COALESCE($7,NOW()),NOW())`,
    [customerId, dateOnly(data, ['desiredDate', 'date']), text(data, ['desiredTime', 'time']), number(data, ['area', 'square']), text(data, ['status']), text(data, ['adminComment', 'comment']), dateValue(data, ['createdAt', 'created_at'])],
  );
}

async function importQualityCheck(db: Database, row: ExportRow) {
  const data = row.data;
  const customerId = await findUserId(db, data, ['customerId', 'customer_id', 'userId', 'clientId'], ['customerPhone', 'phone', 'clientPhone']);
  if (!customerId) return;
  const documentFileId = await findFileId(db, data, ['documentUrl', 'document_url', 'photoUrl', 'photo_url', 'planUrl', 'plan_url', 'filePath', 'storagePath']);
  await db.query(
    `INSERT INTO quality_check_requests (customer_id, requested_area, approved_area, scheduled_at, status, document_file_id, recalculation_amount, created_at, updated_at)
     VALUES ($1,$2,$3,$4,COALESCE($5,'pending'),$6,COALESCE($7,0),COALESCE($8,NOW()),NOW())`,
    [customerId, number(data, ['requestedArea', 'requested_area', 'area']), number(data, ['approvedArea', 'approved_area']), dateValue(data, ['scheduledAt', 'scheduled_at']), text(data, ['status']), documentFileId, number(data, ['recalculationAmount', 'recalculation_amount']), dateValue(data, ['createdAt', 'created_at'])],
  );
}

async function importNotification(db: Database, row: ExportRow) {
  const data = row.data;
  const userId = await findUserId(db, data, ['userId', 'user_id', 'targetUserId'], ['phone', 'userPhone']);
  const titleRu = text(data, ['titleRu', 'title_ru', 'title']) ?? 'Уведомление';
  const bodyRu = text(data, ['bodyRu', 'body_ru', 'body', 'message', 'text']) ?? titleRu;
  await db.query(
    `INSERT INTO notifications (user_id, role, title_ru, title_kk, body_ru, body_kk, target_type, target_id, dedupe_key, read_at, created_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,COALESCE($11,NOW()))
     ON CONFLICT (user_id, dedupe_key) DO NOTHING`,
    [
      userId,
      appRoleOrNull(text(data, ['role', 'targetRole'])),
      titleRu,
      text(data, ['titleKk', 'title_kk']),
      bodyRu,
      text(data, ['bodyKk', 'body_kk']),
      text(data, ['targetType', 'target_type', 'type']),
      text(data, ['targetId', 'target_id', 'orderId']),
      text(data, ['dedupeKey', 'dedupe_key']) ?? `legacy:${row.path ?? row.id}`,
      dateValue(data, ['readAt', 'read_at']),
      dateValue(data, ['createdAt', 'created_at']),
    ],
  );
}

async function importComplaint(db: Database, row: ExportRow) {
  const data = row.data;
  const photoUrls = arrayValue(data, ['photoUrls', 'photos', 'images'])
    .map(String)
    .filter(Boolean);
  const singlePhoto = text(data, ['photoUrl', 'imageUrl', 'photoURL']);
  if (singlePhoto && !photoUrls.includes(singlePhoto)) photoUrls.unshift(singlePhoto);
  await db.query(
    `INSERT INTO complaints (id, customer_id, cleaner_id, order_id, status, title, body, photo_urls, created_at, updated_at)
     VALUES ($1,$2,$3,$4,COALESCE($5,'open'),$6,$7,$8,COALESCE($9,NOW()),NOW())
     ON CONFLICT (id) DO UPDATE SET
       customer_id=EXCLUDED.customer_id,
       cleaner_id=EXCLUDED.cleaner_id,
       order_id=EXCLUDED.order_id,
       status=EXCLUDED.status,
       title=EXCLUDED.title,
       body=EXCLUDED.body,
       photo_urls=EXCLUDED.photo_urls,
       updated_at=NOW()`,
    [
      legacyIdToUuid(`complaint:${row.path ?? row.id}`),
      await findUserId(db, data, ['customerId', 'customer_id', 'userId', 'clientId'], ['customerPhone', 'phone', 'clientPhone']),
      await findUserId(db, data, ['cleanerId', 'cleaner_id'], ['cleanerPhone']),
      await findOrderId(db, data),
      complaintStatus(text(data, ['status'])),
      text(data, ['title', 'subject']) ?? `Жалоба ${row.id}`,
      text(data, ['body', 'message', 'comment', 'description']),
      JSON.stringify(photoUrls.slice(0, 5)),
      dateValue(data, ['createdAt', 'created_at']),
    ],
  );
}

async function importReview(db: Database, row: ExportRow) {
  const data = row.data;
  await db.query(
    `INSERT INTO reviews (id, customer_id, cleaner_id, order_id, rating, comment, photo_url, positive_traits, negative_traits, created_at)
     VALUES ($1,$2,$3,$4,COALESCE($5,5),$6,$7,$8,$9,COALESCE($10,NOW()))
     ON CONFLICT (id) DO UPDATE SET
       customer_id=EXCLUDED.customer_id,
       cleaner_id=EXCLUDED.cleaner_id,
       order_id=EXCLUDED.order_id,
       rating=EXCLUDED.rating,
       comment=EXCLUDED.comment,
       photo_url=EXCLUDED.photo_url,
       positive_traits=EXCLUDED.positive_traits,
       negative_traits=EXCLUDED.negative_traits`,
    [
      legacyIdToUuid(`review:${row.path ?? row.id}`),
      await findUserId(db, data, ['customerId', 'customer_id', 'userId', 'clientId'], ['customerPhone', 'phone', 'clientPhone']),
      await findUserId(db, data, ['cleanerId', 'cleaner_id'], ['cleanerPhone']),
      await findOrderId(db, data),
      number(data, ['rating', 'score']),
      text(data, ['comment', 'body', 'text']),
      text(data, ['photoUrl', 'imageUrl', 'photoURL']),
      JSON.stringify(arrayValue(data, ['positiveTraits', 'positive_traits', 'pros']).map(String).filter(Boolean)),
      JSON.stringify(arrayValue(data, ['negativeTraits', 'negative_traits', 'cons']).map(String).filter(Boolean)),
      dateValue(data, ['createdAt', 'created_at']),
    ],
  );
}

async function importPhotoReport(db: Database, row: ExportRow) {
  const data = row.data;
  const orderId = await findOrderId(db, data);
  if (!orderId) return;
  const photoUrls = arrayValue(data, ['photoUrls', 'photo_urls', 'photos', 'images', 'beforeAfterPhotos'])
    .map(String)
    .filter(Boolean);
  const singlePhoto = text(data, ['photoUrl', 'photo_url', 'imageUrl', 'image_url', 'photoURL']);
  if (singlePhoto && !photoUrls.includes(singlePhoto)) photoUrls.unshift(singlePhoto);
  if (photoUrls.length === 0) return;
  await db.query(
    `INSERT INTO photo_reports (id, order_id, cleaner_id, photo_urls, created_at, updated_at)
     VALUES ($1,$2,$3,$4,COALESCE($5,NOW()),NOW())
     ON CONFLICT (order_id) DO UPDATE SET
       cleaner_id=COALESCE(EXCLUDED.cleaner_id, photo_reports.cleaner_id),
       photo_urls=EXCLUDED.photo_urls,
       updated_at=NOW()`,
    [
      legacyIdToUuid(`photo_report:${row.path ?? row.id}`),
      orderId,
      await findUserId(db, data, ['cleanerId', 'cleaner_id', 'executorId'], ['cleanerPhone', 'executorPhone']),
      JSON.stringify(photoUrls),
      dateValue(data, ['createdAt', 'created_at', 'submittedAt']),
    ],
  );
}

async function importChat(db: Database, row: ExportRow) {
  const data = row.data;
  const chatId = legacyIdToUuid(`chat:${row.path ?? row.id}`);
  await db.query(
    `INSERT INTO chats (id, type, order_id, complaint_id, created_at)
     VALUES ($1,COALESCE($2,'order'),$3,NULL,COALESCE($4,NOW()))
     ON CONFLICT (id) DO UPDATE SET type=EXCLUDED.type, order_id=COALESCE(EXCLUDED.order_id, chats.order_id)`,
    [chatId, text(data, ['type']), await findOrderId(db, data), dateValue(data, ['createdAt', 'created_at'])],
  );
  for (const userId of [
    await findUserId(db, data, ['customerId', 'customer_id', 'userId', 'clientId'], ['customerPhone', 'phone', 'clientPhone']),
    await findUserId(db, data, ['cleanerId', 'cleaner_id'], ['cleanerPhone']),
  ].filter(Boolean)) {
    await db.query(`INSERT INTO chat_participants (chat_id, user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING`, [chatId, userId]);
  }
}

async function importChatMessage(db: Database, row: ExportRow) {
  const data = row.data;
  const parentChatKey = row.parentPath ? `chat:${row.parentPath}` : `chat:${text(data, ['chatId', 'chat_id']) ?? 'unknown'}`;
  const chatId = legacyIdToUuid(parentChatKey);
  const senderId = await findUserId(db, data, ['senderId', 'sender_id', 'userId'], ['senderPhone', 'phone']);
  const messageRu = text(data, ['messageRu', 'message_ru', 'message', 'text', 'body']);
  if (!senderId || !messageRu) return;
  await db.query(
    `INSERT INTO chats (id, type, created_at) VALUES ($1,'order',NOW()) ON CONFLICT (id) DO NOTHING`,
    [chatId],
  );
  await db.query(`INSERT INTO chat_participants (chat_id, user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING`, [chatId, senderId]);
  await db.query(
    `INSERT INTO chat_messages (id, chat_id, sender_id, message_ru, message_kk, created_at)
     VALUES ($1,$2,$3,$4,$5,COALESCE($6,NOW()))
     ON CONFLICT (id) DO UPDATE SET message_ru=EXCLUDED.message_ru, message_kk=EXCLUDED.message_kk`,
    [legacyIdToUuid(`message:${row.path ?? row.id}`), chatId, senderId, messageRu, text(data, ['messageKk', 'message_kk']), dateValue(data, ['createdAt', 'created_at'])],
  );
}

async function importSetting(db: Database, row: ExportRow) {
  const data = row.data;
  const key = text(data, ['key']) ?? row.id;
  await db.query(
    `INSERT INTO app_settings (key, value, updated_at)
     VALUES ($1,$2,NOW())
     ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=NOW()`,
    [key, json(data, ['value']) ?? data],
  );
}

async function ensureAddonGroup(db: Database, titleRu: string): Promise<string> {
  const row = (await db.query<{ id: string }>(
    `INSERT INTO addon_groups (title_ru) VALUES ($1)
     ON CONFLICT (title_ru) DO UPDATE SET title_ru=EXCLUDED.title_ru
     RETURNING id`,
    [titleRu],
  )).rows[0];
  return row.id;
}

async function findUserId(db: Database, data: Record<string, unknown>, uidKeys: string[], phoneKeys: string[]) {
  const uid = text(data, uidKeys);
  if (uid) {
    const row = (await db.query<{ id: string }>(`SELECT id FROM app_users WHERE firebase_uid=$1 OR id::text=$1 LIMIT 1`, [uid])).rows[0];
    if (row?.id) return row.id;
  }
  const phone = text(data, phoneKeys);
  if (phone) {
    const row = (await db.query<{ id: string }>(`SELECT id FROM app_users WHERE phone=$1 LIMIT 1`, [normalizePhone(phone)])).rows[0];
    if (row?.id) return row.id;
  }
  return null;
}

async function findPackageId(db: Database, data: Record<string, unknown>) {
  const explicitId = text(data, ['packageId', 'package_id', 'tariffId']);
  if (explicitId) {
    const byId = (await db.query<{ id: string }>(
      `SELECT id FROM catalog_packages WHERE id::text=$1 LIMIT 1`,
      [explicitId],
    )).rows[0]?.id;
    if (byId) return byId;
  }
  const packageName = text(data, ['packageName', 'package_name', 'tariffName', 'subscriptionName']);
  if (!packageName) return null;
  return (await db.query<{ id: string }>(
    `SELECT id FROM catalog_packages WHERE name_ru=$1 OR name_kk=$1 LIMIT 1`,
    [packageName],
  )).rows[0]?.id ?? null;
}

async function findCustomerAddressId(db: Database, customerId: string, data: Record<string, unknown>) {
  const explicitId = text(data, ['addressId', 'address_id', 'customerAddressId']);
  if (explicitId) {
    const byId = (await db.query<{ id: string }>(
      `SELECT id FROM customer_addresses WHERE user_id=$1 AND id::text=$2 LIMIT 1`,
      [customerId, explicitId],
    )).rows[0]?.id;
    if (byId) return byId;
  }
  const street = text(data, ['street', 'streetRu', 'street_ru', 'addressStreet', 'address']);
  const house = text(data, ['house', 'houseNumber', 'building']);
  if (street && house) {
    const byAddress = (await db.query<{ id: string }>(
      `SELECT id FROM customer_addresses
       WHERE user_id=$1 AND lower(street)=lower($2) AND house=$3
       ORDER BY is_primary DESC, created_at DESC LIMIT 1`,
      [customerId, street, house],
    )).rows[0]?.id;
    if (byAddress) return byAddress;
  }
  return (await db.query<{ id: string }>(
    `SELECT id FROM customer_addresses WHERE user_id=$1 ORDER BY is_primary DESC, created_at DESC LIMIT 1`,
    [customerId],
  )).rows[0]?.id ?? null;
}

async function packageCleaningCount(db: Database, packageId: string) {
  return Number((await db.query<{ cleaning_count: number }>(
    `SELECT cleaning_count FROM catalog_packages WHERE id=$1`,
    [packageId],
  )).rows[0]?.cleaning_count ?? 1);
}

async function findOrderId(db: Database, data: Record<string, unknown>) {
  const orderId = text(data, ['orderId', 'order_id', 'serviceOrderId']);
  if (!orderId) return null;
  return (await db.query<{ id: string }>(`SELECT id FROM service_orders WHERE legacy_firestore_id=$1 OR id::text=$1 LIMIT 1`, [orderId])).rows[0]?.id ?? null;
}

async function findAddonId(db: Database, item: { id?: string | null; title?: string | null }) {
  if (item.id) {
    const byId = (await db.query<{ id: string }>(
      `SELECT id FROM catalog_addons WHERE id::text=$1 LIMIT 1`,
      [item.id],
    )).rows[0]?.id;
    if (byId) return byId;
  }
  if (!item.title) return null;
  return (await db.query<{ id: string }>(
    `SELECT id FROM catalog_addons WHERE title_ru=$1 OR title_kk=$1 LIMIT 1`,
    [item.title],
  )).rows[0]?.id ?? null;
}

async function findFileId(db: Database, data: Record<string, unknown>, keys: string[]) {
  const raw = text(data, keys);
  if (!raw) return null;
  const normalized = normalizeFileReference(raw);
  const candidates = Array.from(new Set([raw, normalized, normalized ? `firebase/${normalized}` : null].filter(Boolean))) as string[];
  const row = (await db.query<{ id: string }>(
    `SELECT id
     FROM files
     WHERE object_key = ANY($1::text[])
        OR public_url = ANY($1::text[])
        OR ($2 <> '' AND object_key LIKE '%' || $2)
        OR ($2 <> '' AND public_url LIKE '%' || $2)
     ORDER BY created_at DESC
     LIMIT 1`,
    [candidates, normalized ?? ''],
  )).rows[0];
  return row?.id ?? null;
}

function normalizeFileReference(value: string) {
  const withoutQuery = value.split('?')[0].trim();
  if (!withoutQuery) return '';
  try {
    const url = new URL(withoutQuery);
    const decodedPath = safeDecodeURIComponent(url.pathname.replace(/^\/+/, ''));
    const firebaseObject = decodedPath.match(/\/o\/(.+)$/)?.[1];
    return firebaseObject ? safeDecodeURIComponent(firebaseObject) : decodedPath;
  } catch {
    return safeDecodeURIComponent(withoutQuery.replace(/^\/+/, '').replace(/^firebase\//, ''));
  }
}

function safeDecodeURIComponent(value: string) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function normalizeCollection(value: string) {
  return value.replace(/[^a-zA-Z0-9_]/g, '').toLowerCase();
}

function roleFromData(collectionKey: string, data: Record<string, unknown>) {
  const raw = String(text(data, ['role', 'type']) ?? '').toLowerCase();
  if (collectionKey === 'cleaners' || raw === 'cleaner') return 'cleaner';
  if (collectionKey === 'admins' || raw === 'admin' || raw === 'superadmin') return raw === 'superadmin' ? 'superadmin' : 'admin';
  return 'customer';
}

function statusFromData(data: Record<string, unknown>, keys = ['status', 'profileStatus', 'verificationStatus']) {
  const raw = String(text(data, keys) ?? 'new').toLowerCase();
  if (['pending', 'approved', 'rejected', 'blocked'].includes(raw)) return raw;
  return raw === 'active' || raw === 'verified' ? 'approved' : 'new';
}

function packageStatusFromData(data: Record<string, unknown>) {
  const raw = String(text(data, ['status', 'packageStatus', 'subscriptionStatus']) ?? 'active').toLowerCase();
  if (['active', 'pending_payment', 'expired', 'cancelled', 'canceled'].includes(raw)) {
    return raw === 'canceled' ? 'cancelled' : raw;
  }
  if (['paid', 'approved'].includes(raw)) return 'active';
  return 'active';
}

function hasCustomerReference(data: Record<string, unknown>) {
  return Boolean(text(data, ['userId', 'user_id', 'customerId', 'customer_id', 'clientId', 'phone', 'userPhone', 'customerPhone', 'clientPhone']));
}

function appRoleOrNull(value: string | null) {
  if (!value) return null;
  const role = value.toLowerCase();
  return ['customer', 'cleaner', 'admin', 'superadmin'].includes(role) ? role : null;
}

function complaintStatus(value: string | null) {
  if (!value) return 'open';
  const status = value.toLowerCase();
  if (['open', 'closed', 'compensation', 'refund'].includes(status)) return status;
  return status === 'done' || status === 'resolved' ? 'closed' : 'open';
}

function legacyIdToUuid(value: string) {
  const hex = createHash('sha256').update(value).digest('hex').slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
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

function bool(data: Record<string, unknown>, keys: string[]): boolean | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') {
      if (['true', '1', 'yes'].includes(value.toLowerCase())) return true;
      if (['false', '0', 'no'].includes(value.toLowerCase())) return false;
    }
  }
  return null;
}

function json(data: Record<string, unknown>, keys: string[]): unknown {
  for (const key of keys) {
    if (data[key] !== undefined && data[key] !== null) return data[key];
  }
  return {};
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

function dateOnly(data: Record<string, unknown>, keys: string[]): string | null {
  const value = dateValue(data, keys);
  return value ? value.slice(0, 10) : null;
}

function timeValue(data: Record<string, unknown>, keys: string[]): string | null {
  const raw = text(data, keys);
  if (!raw) return null;
  const match = raw.match(/(\d{1,2}):(\d{2})/);
  if (!match) return null;
  return `${match[1].padStart(2, '0')}:${match[2]}:00`;
}

function providerFromData(data: Record<string, unknown>) {
  const raw = String(text(data, ['provider', 'paymentProvider', 'type']) ?? 'manual').toLowerCase();
  if (raw.includes('kaspi')) return 'kaspi';
  if (raw.includes('bcc') || raw.includes('epay') || raw.includes('online')) return 'bcc';
  if (raw.includes('bonus')) return 'bonus';
  return 'manual';
}

function paymentStatusFromData(data: Record<string, unknown>) {
  return normalizeMigrationPaymentStatus(text(data, ['status', 'paymentStatus']));
}

function orderStatusFromData(data: Record<string, unknown>) {
  return normalizeMigrationOrderStatus(text(data, ['status', 'orderStatus']));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
