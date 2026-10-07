import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import fs from 'node:fs';
import { ApiError, errorHandler } from '../common/api';
import { auth, signAccessToken, signRefreshToken, verifyRefreshToken, verifyAccessToken } from '../common/auth';
import { env, validateEnvConfig } from '../common/env';
import { AuthService, normalizePhone, NotificationService, PaymentService, PricingService } from '../modules/domainServices';
import { FcmService, normalizeText, PaymentGatewayService, toLatin, WapiOtpService } from '../modules/integrations';
import { acquirePaymentApplication, buildRuntimeConfig, buildRuntimeSettingsMeta, recordPaymentEvent, updatePaymentProviderPayload } from '../http/routes/v1';
import { openApiSpec } from '../http/openapi';
import { validateBootstrapPassword } from '../scripts/bootstrap-admin';
import { normalizeMigrationOrderStatus, normalizeMigrationPaymentStatus } from '../scripts/migration-utils';

test('normalizePhone returns Kazakhstan E.164 phone', () => {
  assert.equal(normalizePhone('7052597368'), '+77052597368');
  assert.equal(normalizePhone('87052597368'), '+77052597368');
  assert.equal(normalizePhone('+77052597368'), '+77052597368');
});

test('normalizeText matches Russian and Kazakh address variants', () => {
  assert.equal(normalizeText('Сыдық 39'), normalizeText('Сдык 39'));
  assert.ok(normalizeText('Тәуелсіздік даңғылы').includes('тауелсиздик'));
});

test('migration status normalization matches backend canonical statuses', () => {
  assert.equal(normalizeMigrationPaymentStatus('confirmed'), 'paid');
  assert.equal(normalizeMigrationPaymentStatus('refund'), 'refunded');
  assert.equal(normalizeMigrationPaymentStatus('expired'), 'cancelled');
  assert.equal(normalizeMigrationOrderStatus('confirmed'), 'assigned');
  assert.equal(normalizeMigrationOrderStatus('waiting_cleaner'), 'pending_assignment');
  assert.equal(normalizeMigrationOrderStatus('started'), 'in_progress');
});

test('OpenAPI documents every v1 Express route', () => {
  const source = ['src/http/routes/v1.ts', 'src/http/routes/mobile.ts'].map(file => fs.readFileSync(file, 'utf8')).join('\n');
  const routePairs = Array.from(source.matchAll(/router\.(get|post|patch|put|delete)\('([^']+)'/g))
    .map((match) => `${match[1].toUpperCase()} ${match[2].replace(/:([A-Za-z0-9_]+)/g, '{$1}')}`);
  const paths = openApiSpec.paths as Record<string, Record<string, unknown>>;
  const documented = new Set<string>();
  for (const [routePath, methods] of Object.entries(paths)) {
    for (const method of ['get', 'post', 'patch', 'put', 'delete']) {
      if (methods[method]) documented.add(`${method.toUpperCase()} ${routePath}`);
    }
  }
  const missing = Array.from(new Set(routePairs)).filter((route) => !documented.has(route));
  assert.deepEqual(missing, []);
});

test('nginx config exposes health, ready, api, realtime and files routes', () => {
  const config = fs.readFileSync('nginx/default.conf', 'utf8');
  for (const expected of [
    'location = /health',
    'location = /ready',
    'location /api/',
    'location /api/v1/realtime',
    'location /files/',
    'proxy_buffering off',
  ]) {
    assert.ok(config.includes(expected), `${expected} is missing from nginx config`);
  }
});

test('readiness checks exact MinIO bucket availability', () => {
  const server = fs.readFileSync('src/http/server.ts', 'utf8');
  assert.ok(server.includes('storage.client.bucketExists(env.minioBucket)'), 'ready endpoint must check configured MinIO bucket');
  assert.ok(server.includes('bucketExists'), 'ready endpoint must expose bucketExists flag');
  assert.equal(server.includes('storage.client.listBuckets().then(() => ({ ok: true'), false);
});

test('docker compose includes VPS runtime services and API healthcheck dependencies', () => {
  const compose = fs.readFileSync('../docker-compose.yml', 'utf8');
  for (const service of ['api', 'worker', 'postgres', 'redis', 'minio', 'nginx', 'backup']) {
    assert.match(compose, new RegExp(`^  ${service}:`, 'm'));
  }
  assert.match(compose, /curl -fsS http:\/\/localhost:8080\/health/);
  assert.match(compose, /dockerfile: backup\/Dockerfile/);

  const dockerfile = fs.readFileSync('Dockerfile', 'utf8');
  assert.match(dockerfile, /apk add --no-cache postgresql-client curl/);
  assert.match(dockerfile, /ENTRYPOINT \["\.\/docker-entrypoint\.sh"\]/);
});

test('BullMQ queues and worker cover notifications, alarms, payments and maintenance', () => {
  const integrations = fs.readFileSync('src/modules/integrations.ts', 'utf8');
  const workers = fs.readFileSync('src/jobs/workers.ts', 'utf8');
  for (const queue of ['notifications', 'cleaner-alarms', 'payments', 'maintenance']) {
    assert.ok(integrations.includes(`new Queue('${queue}'`), `${queue} queue is missing from API queue factory`);
    assert.ok(workers.includes(`new Worker('${queue}'`), `${queue} worker is missing`);
  }
  assert.ok(workers.includes("maintenanceQueue.add('expire-order-offers'"), 'offer expiration repeat job is missing');
  assert.ok(workers.includes("maintenanceQueue.add('cleanup-expired-auth'"), 'auth cleanup repeat job is missing');
});

test('migration audit recognizes collections handled by importer', () => {
  const auditSource = fs.readFileSync('src/scripts/migration-audit.ts', 'utf8');
  for (const collection of [
    'customeraddresses',
    'customerpackages',
    'notifications',
    'complaints',
    'reviews',
    'chats',
    'messages',
  ]) {
    assert.ok(auditSource.includes(`'${collection}'`), `${collection} is missing from migration audit mapped collections`);
  }
});

test('migration importer uses deterministic dependency order', () => {
  const importerSource = fs.readFileSync('src/scripts/import-to-postgres.ts', 'utf8');
  assert.ok(importerSource.includes('sortCollectionsForMapping'), 'migration importer must sort collections before mapping');
  assert.ok(importerSource.includes('collectionImportPriority'), 'migration importer must define import priorities');
  assert.ok(importerSource.indexOf('importLegacy(db, collection, row)') < importerSource.indexOf('importMapped(db, collection, row)'), 'legacy documents must be stored before mapped import');
});

test('PricingService calculates package amount from profile area', () => {
  const pricing = new PricingService();
  assert.equal(pricing.calculatePackage(5000, 100, 70, 4, 1), 48000);
});

test('PricingService applies bonus limit and keeps payable remainder', () => {
  const pricing = new PricingService();
  assert.deepEqual(pricing.splitBonus(29500, 18000, 30000, 100), { bonus: 18000, payable: 11500 });
  assert.deepEqual(pricing.splitBonus(29500, 30000, 30000, 50), { bonus: 14750, payable: 14750 });
  assert.deepEqual(pricing.splitBonus(10000, 10000, 10000, 100), { bonus: 10000, payable: 0 });
});

test('PaymentService turns full bonus payment into paid bonus-only payment', async () => {
  const queries: Array<{ sql: string; params?: unknown[] }> = [];
  const fakeDb = {
    async query(sql: string, params?: unknown[]) {
      queries.push({ sql, params });
      if (sql.includes('SELECT bonus_balance')) return { rows: [{ bonus_balance: '30000' }] };
      if (sql.includes('INSERT INTO payments')) {
        return {
          rows: [{
            id: 'pay-1',
            provider: params?.[3],
            status: params?.[4],
            amount: params?.[5],
            bonus_amount: params?.[6],
          }],
        };
      }
      if (sql.includes('UPDATE service_orders')) return { rows: [] };
      return { rows: [] };
    },
  } as any;
  const spends: unknown[][] = [];
  const fakeBonus = { spend: async (...args: unknown[]) => spends.push(args) } as any;
  const service = new PaymentService(fakeDb, fakeBonus);

  const result = await service.createPayment({
    customerId: 'user-1',
    orderId: 'order-1',
    amount: 10000,
    provider: 'kaspi',
    useBonus: true,
    requestedBonus: 10000,
    maxBonusPercent: 100,
  });

  assert.equal((result.payment as any).provider, 'bonus');
  assert.equal((result.payment as any).status, 'paid');
  assert.equal((result.payment as any).amount, 0);
  assert.equal((result.payment as any).bonus_amount, 10000);
  assert.equal(result.payableAmount, 0);
  assert.equal(result.bonusSpent, 10000);
  assert.deepEqual(spends[0], ['user-1', 10000, 'Оплата бонусами', 'order-1', 'pay-1']);
  assert.equal(queries.some((entry) => entry.sql.includes('UPDATE service_orders')), true);
});

test('PaymentService creates external invoice only for payable amount after bonuses', async () => {
  const queries: Array<{ sql: string; params?: unknown[] }> = [];
  const fakeDb = {
    async query(sql: string, params?: unknown[]) {
      queries.push({ sql, params });
      if (sql.includes('SELECT bonus_balance')) return { rows: [{ bonus_balance: '30000' }] };
      if (sql.includes('INSERT INTO payments')) {
        return {
          rows: [{
            id: 'pay-2',
            provider: params?.[3],
            status: params?.[4],
            amount: params?.[5],
            bonus_amount: params?.[6],
          }],
        };
      }
      if (sql.includes('UPDATE service_orders')) return { rows: [] };
      return { rows: [] };
    },
  } as any;
  const spends: unknown[][] = [];
  const fakeBonus = { spend: async (...args: unknown[]) => spends.push(args) } as any;
  const service = new PaymentService(fakeDb, fakeBonus);

  const result = await service.createPayment({
    customerId: 'user-1',
    orderId: 'order-1',
    amount: 29500,
    provider: 'kaspi',
    useBonus: true,
    requestedBonus: 18000,
    maxBonusPercent: 100,
  });

  assert.equal((result.payment as any).provider, 'kaspi');
  assert.equal((result.payment as any).status, 'pending');
  assert.equal((result.payment as any).amount, 11500);
  assert.equal((result.payment as any).bonus_amount, 18000);
  assert.equal(result.payableAmount, 11500);
  assert.equal(result.bonusSpent, 18000);
  assert.deepEqual(spends[0], ['user-1', 18000, 'Оплата бонусами', 'order-1', 'pay-2']);
  const orderUpdate = queries.find((entry) => entry.sql.includes('UPDATE service_orders'));
  assert.deepEqual(orderUpdate?.params, ['order-1', 18000, 11500]);
});

test('PaymentService markPaid does not revive cancelled or refunded payments', async () => {
  const queries: Array<{ sql: string; params?: unknown[] }> = [];
  const fakeDb = {
    async query(sql: string, params?: unknown[]) {
      queries.push({ sql, params });
      return { rows: [] };
    },
  } as any;
  const service = new PaymentService(fakeDb, {} as any);

  const result = await service.markPaid('payment-1');

  assert.equal(result, null);
  assert.match(queries[0].sql, /status NOT IN \('cancelled','refunded'\)/);
  assert.deepEqual(queries[0].params, ['payment-1']);
});

test('AuthService logout revokes sessions and disables device token', async () => {
  const queries: Array<{ sql: string; params?: unknown[] }> = [];
  const fakeDb = {
    async query(sql: string, params?: unknown[]) {
      queries.push({ sql, params });
      return { rows: [] };
    },
  } as any;
  const service = new AuthService(fakeDb, {} as any);
  const result = await service.logout({
    userId: 'user-1',
    refreshToken: 'refresh-token',
    deviceToken: 'fcm-token',
  });

  assert.deepEqual(result, { loggedOut: true });
  assert.equal(queries.length, 2);
  assert.match(queries[0].sql, /UPDATE refresh_sessions/);
  assert.equal(queries[0].params?.[0], 'user-1');
  assert.match(queries[1].sql, /UPDATE device_tokens/);
  assert.deepEqual(queries[1].params, ['user-1', 'fcm-token']);
});

test('NotificationService creates backend-driven admin events for admin roles', async () => {
  const inserts: Array<{ role: string; dedupeKey: string }> = [];
  const fakeDb = {
    async query(sql: string, params?: unknown[]) {
      if (sql.includes("WHERE key='adminNotificationRules'")) {
        return { rows: [{ value: { enabled: true, events: ['new_order'] } }] };
      }
      if (sql.includes('SELECT * FROM notifications WHERE role=')) return { rows: [] };
      if (sql.includes('INSERT INTO notifications')) {
        inserts.push({ role: String(params?.[1]), dedupeKey: String(params?.[8]) });
        return { rows: [{ id: `n-${inserts.length}`, user_id: null, role: params?.[1] }] };
      }
      if (sql.includes('SELECT dt.token')) return { rows: [] };
      if (sql.includes('SELECT id FROM app_users WHERE role=')) return { rows: [] };
      return { rows: [] };
    },
  } as any;
  const service = new NotificationService(fakeDb, { send: async () => undefined } as any);

  const result = await service.createAdminEvent({
    event: 'new_order',
    titleRu: 'Новый заказ',
    bodyRu: 'Создан заказ.',
    targetType: 'order',
    targetId: 'order-1',
    dedupeKey: 'order-1',
  });

  assert.equal(result.length, 2);
  assert.deepEqual(inserts.map((row) => row.role), ['admin', 'superadmin']);
  assert.deepEqual(inserts.map((row) => row.dedupeKey), ['admin-event-admin-order-1', 'admin-event-superadmin-order-1']);
});

test('FcmService skips push safely when FCM is not configured', async () => {
  const result = await new FcmService().send(['token-1'], 'Тест', 'Проверка');
  assert.deepEqual(result, { sent: 0, failed: 0, skipped: true });
});

test('WapiOtpService returns friendly integration error on provider failure', async () => {
  const originalFetch = globalThis.fetch;
  const originalToken = env.wapiToken;
  const originalProfileId = env.wapiProfileId;
  env.wapiToken = 'token';
  env.wapiProfileId = 'profile';
  try {
    for (const mock of [
      async () => ({ok:false}),
      async () => ({ok:true,json:async()=>({status:'error'})}),
      async () => {throw new Error('network timeout');},
    ]) {
      globalThis.fetch = mock as any;
      await assert.rejects(
        () => new WapiOtpService().sendOtp('+77052597368', '123456'),
        (error: any) => error instanceof ApiError && error.code === 'integration_error' && error.status === 503,
      );
    }
    globalThis.fetch = (async()=>({ok:true,json:async()=>({status:'done'})})) as any;
    await new WapiOtpService().sendOtp('+77052597368','123456');
    env.wapiToken='';
    await assert.rejects(()=>new WapiOtpService().sendOtp('+77052597368','123456'),(error:any)=>error.code==='integration_error');
  } finally {
    globalThis.fetch = originalFetch;
    env.wapiToken = originalToken;
    env.wapiProfileId = originalProfileId;
  }
});

test('auth middleware accepts query access token when enabled for SSE', async () => {
  const token = signAccessToken({ id: 'user-1', role: 'customer', phone: '+77052597368' });
  const req = Object.assign(new EventEmitter(), {
    header: () => '',
    query: { access_token: token },
  }) as any;
  let nextError: unknown;
  await new Promise<void>((resolve) => {
    auth([], { allowQueryToken: true })(req, {} as any, (error?: unknown) => {
      nextError = error;
      resolve();
    });
  });
  assert.equal(nextError, undefined);
  assert.equal(req.user.id, 'user-1');
});

test('errorHandler returns localized friendly error payload without stack traces', () => {
  const payloads: any[] = [];
  const res = {
    statusCode: 200,
    status(code: number) {
      this.statusCode = code;
      return this;
    },
    json(payload: unknown) {
      payloads.push({ status: this.statusCode, payload });
      return this;
    },
  } as any;
  errorHandler(
    new ApiError(401, 'unauthorized', 'raw unauthorized'),
    { query: { lang: 'kk' }, headers: {} } as any,
    res,
    (() => undefined) as any,
  );
  assert.equal(payloads[0].status, 401);
  assert.equal(payloads[0].payload.ok, false);
  assert.equal(payloads[0].payload.code, 'unauthorized');
  assert.equal(payloads[0].payload.message, 'Аккаунтқа қайта кіріңіз.');
  assert.equal(payloads[0].payload.messageRu, 'Войдите в аккаунт заново.');
  assert.equal('stack' in payloads[0].payload, false);
});

test('PaymentGatewayService builds BCC payload with required fields', async () => {
  const gateway = new PaymentGatewayService();
  const result = await gateway.createBccPayment({
    paymentId: '12345678-1234-1234-1234-123456789012',
    amount: 7500,
    description: 'Оплата заказа DOMLY',
    clientIp: '127.0.0.1',
    language: 'ru',
    mInfo: 'Астана, Тәуелсіздік 39',
  });
  const payload = result.providerPayload as Record<string, unknown>;
  assert.equal(payload.TRTYPE, '1');
  assert.equal(payload.AMOUNT, 7500);
  assert.equal(payload.CURRENCY, 'KZT');
  assert.equal(payload.CLIENT_IP, '127.0.0.1');
  assert.equal(payload.LANG, 'ru');
  assert.equal(payload.DESC, 'Оплата заказа DOMLY');
  assert.equal(payload.M_INFO, 'Astana, Tauelsizdik 39');
  assert.ok(String(payload.ORDER).length >= 6);
  assert.equal((result as any).externalOrderId, payload.ORDER);
});

test('updatePaymentProviderPayload stores BCC ORDER as payment external id', async () => {
  const queries: Array<{ sql: string; params?: unknown[] }> = [];
  const fakeDb = {
    async query(sql: string, params?: unknown[]) {
      queries.push({ sql, params });
      return { rows: [] };
    },
  } as any;

  await updatePaymentProviderPayload(fakeDb, 'payment-1', {
    providerPayload: { ORDER: '123456' },
    providerResponse: null,
    externalOrderId: '123456',
  });

  assert.equal(queries.length, 1);
  assert.match(queries[0].sql, /external_id=COALESCE/);
  assert.deepEqual(queries[0].params, [
    'payment-1',
    { providerPayload: { ORDER: '123456' }, providerResponse: null, externalOrderId: '123456' },
    '123456',
  ]);
});

test('PaymentGatewayService builds BCC refund/status/connection payloads', async () => {
  const gateway = new PaymentGatewayService();
  const refund = await gateway.createBccRefund({
    paymentId: '12345678-1234-1234-1234-123456789012',
    amount: 1000,
    referenceId: 'rrn-test',
    language: 'ru',
  });
  const refundPayload = refund.providerPayload as Record<string, unknown>;
  assert.equal(refundPayload.TRTYPE, '14');
  assert.equal(refundPayload.MERCH_RN_ID, '');
  assert.equal(refundPayload.LANG, 'ru');

  const status = await gateway.createBccStatusCheck({
    paymentId: '12345678-1234-1234-1234-123456789012',
    originalTrType: '1',
    language: 'ru',
  });
  const statusPayload = status.providerPayload as Record<string, unknown>;
  assert.equal(statusPayload.TRTYPE, '90');
  assert.equal(statusPayload.TRAN_TRTYPE, '1');
  assert.equal(statusPayload.LANG, 'ru');
  assert.equal(Object.hasOwn(statusPayload, 'MERCHANT'), false);
  assert.equal(Object.hasOwn(statusPayload, 'INT_REF'), false);

  const connection = await gateway.createBccConnectionCheck({ language: 'ru' });
  const connectionPayload = connection.providerPayload as Record<string, unknown>;
  assert.equal(connectionPayload.TRTYPE, '800');
  assert.equal(connectionPayload.LANG, 'ru');
  assert.equal(Object.hasOwn(connectionPayload, 'TIMESTAMP'), false);
  assert.equal(Object.hasOwn(connectionPayload, 'NONCE'), false);
  assert.equal(Object.hasOwn(connectionPayload, 'P_SIGN'), false);
});

test('recordPaymentEvent stores idempotent payment provider events', async () => {
  const queries: Array<{ sql: string; params?: unknown[] }> = [];
  const fakeDb = {
    async query(sql: string, params?: unknown[]) {
      queries.push({ sql, params });
      return { rows: [] };
    },
  } as any;

  await recordPaymentEvent(fakeDb, {
    paymentId: '11111111-1111-1111-1111-111111111111',
    provider: 'bcc',
    eventType: 'webhook',
    status: 'paid',
    externalId: 'rrn-1',
    idempotencyKey: 'event-1',
    payload: { ORDER: '000001', RESPONSE: '00' },
  });

  assert.equal(queries.length, 1);
  assert.match(queries[0].sql, /INSERT INTO payment_events/);
  assert.match(queries[0].sql, /ON CONFLICT \(provider, idempotency_key\)/);
  assert.deepEqual(queries[0].params, [
    '11111111-1111-1111-1111-111111111111',
    'bcc',
    'webhook',
    'paid',
    'rrn-1',
    'event-1',
    { ORDER: '000001', RESPONSE: '00' },
  ]);
});

test('acquirePaymentApplication applies a payment only once', async () => {
  const queries: Array<{ sql: string; params?: unknown[] }> = [];
  const fakeDb = {
    async query(sql: string, params?: unknown[]) {
      queries.push({ sql, params });
      return { rows: [{ id: params?.[0], applied_at: new Date().toISOString() }] };
    },
  } as any;

  const result = await acquirePaymentApplication(fakeDb, 'payment-1');

  assert.equal((result as any).id, 'payment-1');
  assert.equal(queries.length, 1);
  assert.match(queries[0].sql, /UPDATE payments/);
  assert.match(queries[0].sql, /WHERE id=\$1 AND applied_at IS NULL/);
  assert.deepEqual(queries[0].params, ['payment-1']);
});

test('buildRuntimeConfig returns backend-driven defaults for thin clients', () => {
  const config = buildRuntimeConfig({});
  assert.equal(config.rules.qualityCheckHours, 48);
  assert.equal(config.backendDriven.booking.allowCustomTime, false);
  assert.equal(config.backendDriven.booking.requireAvailableCleaner, true);
  assert.equal(config.backendDriven.paymentFlow.requireBonusCheckbox, true);
  assert.equal(config.backendDriven.paymentFlow.hideExternalInvoiceForZeroPayable, true);
  assert.equal(config.backendDriven.paymentFlow.invoiceAmountUsesPayableAfterBonus, true);
  assert.deepEqual(config.backendDriven.navigation.customerTabs, ['home', 'orders', 'profile', 'notifications', 'settings']);
  assert.deepEqual(config.backendDriven.localization.enabledLanguages, ['ru', 'kk']);
  assert.equal(config.backendDriven.localization.translationMode.liveSwitch, true);
  assert.equal(config.backendDriven.addressSearch.fallbackOnlyOnEmptyOrError, true);
  assert.equal(config.backendDriven.addressSearch.radiusKm, 50);
  assert.equal(config.backendDriven.assignmentRules.preventTimeOverlap, true);
  assert.equal(config.backendDriven.orderRules.cancelRemovesPaidAddons, true);
  assert.equal(config.backendDriven.adminNotificationRules.enabled, true);
  assert.equal(config.backendDriven.trainingFlow.interactiveMode, true);
  assert.equal(config.backendDriven.screenRules.adminSortDefault, 'newest_first');
  assert.equal(config.backendDriven.customerTierRules[0].tier, 'NEWBIE');
  assert.equal(config.backendDriven.customerTierRules[0].labelRu, 'Наш любимый Новичок');
  assert.equal(config.backendDriven.customerTierRules[1].minMonthlySpent, 100000);
  assert.equal(config.backendDriven.customerTierRules.at(-1).maxMonthlySpent, null);
});

test('buildRuntimeConfig applies admin app_settings overrides', () => {
  const config = buildRuntimeConfig({
    minBookingDate: '2026-09-02',
    allowCustomTime: true,
    requireAvailableCleaner: false,
    customerTabs: ['home', 'orders'],
    paymentFlow: { afterInvoiceAction: 'orders', requireBonusCheckbox: true },
    uiBehavior: { bannerFit: 'cover' },
    validationRules: { addressSearchLimit: 10, addressSearchRadiusKm: 50 },
    addressSearch: { primaryProvider: 'osm', fallbackProvider: 'yandex', limit: 7 },
    localization: { enabledLanguages: ['kk'], defaultLanguage: 'kk' },
    screenRules: { adminSortDefault: 'oldest_first' },
    customerTierRules: [
      { tier: 'test', labelRu: 'Тест', labelKk: 'Тест', minMonthlySpent: 0, maxMonthlySpent: null, discountPercent: 12 },
    ],
  });
  assert.equal(config.rules.minBookingDate, '2026-09-02');
  assert.equal(config.backendDriven.booking.minBookingDate, '2026-09-02');
  assert.equal(config.backendDriven.booking.allowCustomTime, true);
  assert.equal(config.backendDriven.booking.requireAvailableCleaner, false);
  assert.deepEqual(config.backendDriven.navigation.customerTabs, ['home', 'orders']);
  assert.equal(config.backendDriven.paymentFlow.afterInvoiceAction, 'orders');
  assert.equal(config.backendDriven.paymentFlow.requireBonusCheckbox, true);
  assert.equal(config.backendDriven.paymentFlow.invoiceAmountUsesPayableAfterBonus, true);
  assert.equal(config.backendDriven.uiBehavior.bannerFit, 'cover');
  assert.equal(config.backendDriven.uiBehavior.stickyAddonButtons, true);
  assert.equal(config.backendDriven.validationRules.addressSearchLimit, 10);
  assert.equal(config.backendDriven.validationRules.blockQualitySubmitUntilComplete, true);
  assert.equal(config.backendDriven.addressSearch.limit, 7);
  assert.equal(config.backendDriven.addressSearch.excludeOrganizations, true);
  assert.deepEqual(config.backendDriven.localization.enabledLanguages, ['kk']);
  assert.equal(config.backendDriven.localization.defaultLanguage, 'kk');
  assert.equal(config.backendDriven.screenRules.adminSortDefault, 'oldest_first');
  assert.equal(config.backendDriven.customerTierRules[0].tier, 'TEST');
  assert.equal(config.backendDriven.customerTierRules[0].discountPercent, 12);
});

test('buildRuntimeSettingsMeta exposes editable backend-first sections', () => {
  const meta = buildRuntimeSettingsMeta({
    paymentFlow: { afterInvoiceAction: 'orders' },
    addressSearch: { limit: 7 },
  });
  assert.ok(meta.version);
  const payment = meta.sections.find((section) => section.key === 'paymentFlow');
  const address = meta.sections.find((section) => section.key === 'addressSearch');
  const customerTiers = meta.sections.find((section) => section.key === 'customerTierRules');
  assert.ok(payment);
  assert.ok(address);
  assert.ok(customerTiers);
  assert.equal((payment.value as any).afterInvoiceAction, 'orders');
  assert.equal((payment.value as any).invoiceAmountUsesPayableAfterBonus, true);
  assert.equal((address.value as any).limit, 7);
  assert.equal((address.value as any).excludeOrganizations, true);
  assert.equal((customerTiers.value as any[])[0].tier, 'NEWBIE');
  assert.ok(payment.fields.some((field) => field.key === 'requireBonusCheckbox'));
  assert.ok(meta.sections.some((section) => section.key === 'trainingFlow'));
});

test('validateEnvConfig rejects production placeholders and missing required integrations', () => {
  const config = {
    ...env,
    nodeEnv: 'production',
    strictEnv: true,
    jwtAccessSecret: 'dev_access_secret_change_me',
    jwtRefreshSecret: 'dev_refresh_secret_change_me',
    minioSecretKey: 'change_me',
    publicApiUrl: 'http://localhost:8080',
    requireExternalIntegrations: true,
    wapiToken: '',
    fcmPrivateKey: '',
    kaspiApiKey: '',
    bccNotifyUrl: '',
  };
  const report = validateEnvConfig(config);
  assert.equal(report.ok, false);
  assert.ok(report.issues.some((issue) => issue.includes('JWT_ACCESS_SECRET')));
  assert.ok(report.issues.some((issue) => issue.includes('WAPI is required')));
  assert.ok(report.issues.some((issue) => issue.includes('FCM is required')));
});

test('validateEnvConfig allows optional external integrations when core env is valid', () => {
  const config = {
    ...env,
    nodeEnv: 'production',
    strictEnv: true,
    jwtAccessSecret: 'a'.repeat(40),
    jwtRefreshSecret: 'b'.repeat(40),
    minioSecretKey: 'c'.repeat(40),
    publicApiUrl: 'https://api.domly.kz',
    requireExternalIntegrations: false,
    requireWapi: false,
    requireFcm: false,
    requirePayments: false,
    requireAddressFallback: false,
    wapiToken: '',
    wapiProfileId: '',
    fcmProjectId: '',
    fcmClientEmail: '',
    fcmPrivateKey: '',
    kaspiMerchantId: '',
    kaspiApiKey: '',
    kaspiBaseUrl: '',
    bccMerchantId: '',
    bccTerminalId: '',
    bccNotifyUrl: '',
    bccReturnUrl: '',
  };
  const report = validateEnvConfig(config);
  assert.equal(report.ok, true);
  assert.ok(report.warnings.some((warning) => warning.includes('WAPI is not fully configured')));
});

test('validateEnvConfig enforces BCC callback URL format and explicit TRTYPE=1 port', () => {
  const config = {
    ...env,
    requirePayments: false,
    bccMerchantId: 'merchant',
    bccTerminalId: 'terminal',
    bccPrivateKey: 'private-key',
    bccPublicKey: 'public-key',
    bccNotifyUrl: 'https://api.domly.kz/api/v1/payments/bcc/webhook',
    bccReturnUrl: 'not-a-url',
  };
  const report = validateEnvConfig(config);
  assert.equal(report.ok, false);
  assert.ok(report.issues.some((issue) => issue.includes('BCC_NOTIFY_URL must include an explicit port')));
  assert.ok(report.issues.some((issue) => issue.includes('BCC_RETURN_URL must be a valid')));
});

test('validateEnvConfig rejects non-HTTPS public URLs in production', () => {
  const config = {
    ...env,
    nodeEnv: 'production',
    strictEnv: true,
    jwtAccessSecret: 'a'.repeat(40),
    jwtRefreshSecret: 'b'.repeat(40),
    minioSecretKey: 'c'.repeat(40),
    publicApiUrl: 'http://api.domly.kz',
    requirePayments: false,
    bccMerchantId: 'merchant',
    bccTerminalId: 'terminal',
    bccPrivateKey: 'private-key',
    bccPublicKey: 'public-key',
    bccNotifyUrl: 'http://api.domly.kz:443/api/v1/payments/bcc/webhook',
    bccReturnUrl: 'http://domly.kz/payments/return',
    kaspiMerchantId: 'merchant',
    kaspiApiKey: 'api-key',
    kaspiBaseUrl: 'http://kaspi.domly.kz',
  };
  const report = validateEnvConfig(config);
  assert.equal(report.ok, false);
  assert.ok(report.issues.some((issue) => issue.includes('PUBLIC_API_URL must be a public HTTPS URL')));
  assert.ok(report.issues.some((issue) => issue.includes('BCC_NOTIFY_URL must be a public HTTPS URL')));
  assert.ok(report.issues.some((issue) => issue.includes('BCC_RETURN_URL must be a public HTTPS URL')));
  assert.ok(report.issues.some((issue) => issue.includes('KASPI_BASE_URL must be a public HTTPS URL')));
});

test('validateEnvConfig accepts complete BCC config with explicit notify port', () => {
  const config = {
    ...env,
    requirePayments: true,
    kaspiMerchantId: '',
    kaspiApiKey: '',
    kaspiBaseUrl: '',
    bccMerchantId: 'merchant',
    bccTerminalId: 'terminal',
    bccPrivateKey: 'private-key',
    bccPublicKey: 'public-key',
    bccNotifyUrl: 'https://api.domly.kz:443/api/v1/payments/bcc/webhook',
    bccReturnUrl: 'https://domly.kz/payments/return',
  };
  const report = validateEnvConfig(config);
  assert.equal(report.ok, true);
});

test('validateEnvConfig rejects invalid Kaspi base URL when configured', () => {
  const report = validateEnvConfig({
    ...env,
    requirePayments: false,
    kaspiMerchantId: 'merchant',
    kaspiApiKey: 'api-key',
    kaspiBaseUrl: 'kaspi-host',
  });
  assert.equal(report.ok, false);
  assert.ok(report.issues.some((issue) => issue.includes('KASPI_BASE_URL')));
});

test('validateBootstrapPassword rejects placeholders and accepts strong password', () => {
  assert.throws(() => validateBootstrapPassword('change_me_min_8_chars'), /placeholder/);
  assert.throws(() => validateBootstrapPassword('123456'), /at least 8/);
  assert.doesNotThrow(() => validateBootstrapPassword('DomlySecure123!'));
});

test('toLatin transliterates payment m_info without Cyrillic', () => {
  assert.equal(toLatin('Астана, улица Брусиловского, 110'), 'Astana, ulitsa Brusilovskogo, 110');
  assert.equal(toLatin('Тәуелсіздік даңғылы 39'), 'Tauelsizdik dangyly 39');
});

test('OTP delivery fallback reveals a verifiable code only during the configured window', async () => {
  const original = env.otpFailureFallbackUntil;
  const failure = new ApiError(503, 'integration_error', 'Delivery failed');
  const delivery = {sendOtp: async () => {throw failure;}} as any;
  let storedHash = '';
  let user: any;
  const db = {query: async (sql: string, args: any[]) => {
    if (sql.includes('INSERT INTO auth_otp_codes')) storedHash=args[1];
    return {rows: sql.includes('FROM app_users') && user ? [user] : []};
  }} as any;
  const service = new AuthService(db,delivery);
  try {
    for (const value of ['', 'invalid', new Date(Date.now()-1000).toISOString()]) {
      env.otpFailureFallbackUntil=value;
      await assert.rejects(()=>service.requestOtp('+77052597368'),failure);
    }
    env.otpFailureFallbackUntil=new Date(Date.now()+60000).toISOString();
    const result = await service.requestOtp('+77052597368');
    assert.match(result.fallbackCode!,/^\d{6}$/);
    assert.equal(result.codeSent,false);
    assert.equal(result.expiresInSeconds,300);
    const bcrypt = await import('bcryptjs');
    assert.equal(await bcrypt.compare(result.fallbackCode!,storedHash),true);
    for (const role of ['admin','superadmin']) {
      user={role,status:'approved'};
      await assert.rejects(()=>service.requestOtp('+77052597368'),failure);
    }
    user={role:'customer',status:'blocked'};
    await assert.rejects(()=>service.requestOtp('+77052597368'),failure);
    for (const role of ['customer','cleaner']) {
      user={role,status:'new'};
      assert.match((await service.requestOtp('+77052597368')).fallbackCode!,/^\d{6}$/);
    }
    const sent = await new AuthService(db,{sendOtp:async()=>{}} as any).requestOtp('+77052597368');
    assert.equal(sent.codeSent,true);
    assert.equal(sent.fallbackCode,undefined);
  } finally {env.otpFailureFallbackUntil=original;}
});

test('OTP signup cannot create privileged roles', async () => {
  const service = new AuthService({query:async()=>{throw Error('Unexpected DB access');}} as any,{} as any);
  for (const role of ['admin','superadmin']) {
    await assert.rejects(()=>service.verifyOtp('+77052597368','123456',role as any),(e:any)=>e instanceof ApiError && e.code==='invalid_role');
  }
});


test('refresh tokens renew access without carrying old JWT expiry claims', () => {
  const user = { id: 'admin', role: 'superadmin' as const, phone: '+77000000000' };
  const refresh = signRefreshToken(user);
  const restored = verifyRefreshToken(refresh);
  assert.deepEqual(restored, user);
  assert.equal(verifyAccessToken(signAccessToken(restored)).id, user.id);
  assert.notEqual(signRefreshToken(restored), refresh);
  assert.throws(() => verifyRefreshToken('invalid'), (error: unknown) => error instanceof ApiError && error.status === 401);
});


test('explicit OTP display has no deadline and shows the real code on success or failure', async () => {
  const originalFlag=env.otpShowCode, originalUntil=env.otpFailureFallbackUntil;
  let storedHash='', user: any;
  const db={query:async(sql:string,args:any[])=>{
    if(sql.includes('INSERT INTO auth_otp_codes'))storedHash=args[1];
    return {rows:sql.includes('FROM app_users') && user ? [user] : []};
  }} as any;
  const failure=new ApiError(503,'integration_error','Provider unavailable');
  try {
    env.otpShowCode=true;env.otpFailureFallbackUntil='';
    for(const role of [undefined,'customer','cleaner']) {
      user=role?{role,status:'approved'}:undefined;
      for(const succeeds of [true,false]) {
        const service=new AuthService(db,{sendOtp:async()=>{if(!succeeds)throw failure;}} as any);
        const result=await service.requestOtp('+77052597368');
        assert.match(result.fallbackCode!,/^\d{6}$/);
        assert.equal(result.codeSent,succeeds);
        assert.equal(result.expiresInSeconds,300);
        assert.equal(await (await import('bcryptjs')).compare(result.fallbackCode!,storedHash),true);
      }
    }
    for(const account of [{role:'admin',status:'approved'},{role:'superadmin',status:'approved'},{role:'customer',status:'blocked'},{role:'cleaner',status:'rejected'}]) {
      user=account;
      const sent=await new AuthService(db,{sendOtp:async()=>{}} as any).requestOtp('+77052597368');
      assert.equal(sent.fallbackCode,undefined);
      await assert.rejects(()=>new AuthService(db,{sendOtp:async()=>{throw failure;}} as any).requestOtp('+77052597368'),failure);
    }
    env.otpShowCode=false;user={role:'customer',status:'approved'};
    assert.equal((await new AuthService(db,{sendOtp:async()=>{}} as any).requestOtp('+77052597368')).fallbackCode,undefined);
    await assert.rejects(()=>new AuthService(db,{sendOtp:async()=>{throw failure;}} as any).requestOtp('+77052597368'),failure);
  } finally {env.otpShowCode=originalFlag;env.otpFailureFallbackUntil=originalUntil;}
});
