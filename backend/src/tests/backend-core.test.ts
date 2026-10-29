import { formatAddonRecord, formatServiceDescription } from '../modules/serviceDescription';
import {gunzipSync} from 'node:zlib';
import {PublicTextCatalog} from '../modules/publicTextCatalog';
import {canonicalMediaUrl,httpsMediaUrl,mapMediaValues,verifyMediaLink} from '../modules/mediaLinks';
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import fs from 'node:fs';
import { ApiError, errorHandler } from '../common/api';
import { auth, signAccessToken, signRefreshToken, verifyRefreshToken, verifyAccessToken } from '../common/auth';
import { env, validateEnvConfig } from '../common/env';
import { AuthService, normalizePhone, NotificationService, PaymentService, PricingService, SchedulingService } from '../modules/domainServices';
import { buildFcmMessage, FcmService, normalizeText, PaymentGatewayService, toLatin, WapiOtpService } from '../modules/integrations';
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
  assert.equal(normalizeText('Сыдық 39'), normalizeText('Сидик 39'));
  assert.ok(normalizeText('Тәуелсіздік даңғылы').includes('тауелсиздик'));
  assert.equal(normalizeText('Тауелсиздык 29/2'), normalizeText('Тәуелсіздік 29/2'));
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
    transaction: async (work: any) => work(fakeDb),
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
  assert.deepEqual(spends[0].slice(0,5), ['user-1', 10000, 'Оплата бонусами', 'order-1', 'pay-1']);
  assert.equal(queries.some((entry) => entry.sql.includes('UPDATE service_orders')), true);
});

test('PaymentService creates external invoice only for payable amount after bonuses', async () => {
  const queries: Array<{ sql: string; params?: unknown[] }> = [];
  const fakeDb = {
    transaction: async (work: any) => work(fakeDb),
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
  assert.deepEqual(spends[0].slice(0,5), ['user-1', 18000, 'Оплата бонусами', 'order-1', 'pay-2']);
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
  assert.deepEqual(queries[0].params, ['payment-1', null]);
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
    async atomic(work: () => Promise<unknown>) { return work(); },
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

test('Green API sends only a fixed OTP message and requires a message receipt',async()=>{
  const original={provider:env.otpProvider,instance:env.greenApiInstanceId,token:env.greenApiToken,fetch:globalThis.fetch};
  try {
    env.otpProvider='greenapi';env.greenApiInstanceId='770012345678';env.greenApiToken='fixture-secret';
    const calls:any[]=[];
    globalThis.fetch=(async(url:any,init:any)=>{if(String(url).includes('/getStateInstance/'))return {ok:true,json:async()=>({stateInstance:'authorized'})};calls.push({url,body:JSON.parse(init.body)});return {ok:true,json:async()=>({idMessage:'receipt'})};}) as any;
    await new WapiOtpService().sendOtp('+77052597368','123456');
    assert.equal(calls[0].url,'https://7700.api.greenapi.com/waInstance770012345678/sendMessage/fixture-secret');
    assert.deepEqual(calls[0].body,{chatId:'77052597368@c.us',message:'DOMLY код подтверждения: 123456'});
    for(const code of ['hello','12345','1234567'])await assert.rejects(()=>new WapiOtpService().sendOtp('+77052597368',code),(e:any)=>e.code==='invalid_otp_payload');
    assert.equal(calls.length,1);
    for(const mock of [async()=>({ok:false}),async()=>({ok:true,json:async()=>({})}),async()=>({ok:true,json:async()=>({idMessage:''})}),async()=>{throw Error('secret URL must not escape');}]) {
      globalThis.fetch=(async(url:any)=>String(url).includes('/getStateInstance/')?{ok:true,json:async()=>({stateInstance:'authorized'})}:mock()) as any;
      await assert.rejects(()=>new WapiOtpService().sendOtp('+77052597368','123456'),(e:any)=>e.code==='integration_error'&&!e.message.includes('secret'));
    }
    env.greenApiToken='';
    await assert.rejects(()=>new WapiOtpService().sendOtp('+77052597368','123456'),(e:any)=>e.code==='integration_error');
  }finally{env.otpProvider=original.provider;env.greenApiInstanceId=original.instance;env.greenApiToken=original.token;globalThis.fetch=original.fetch;}
});

test('disconnected WhatsApp channel never queues an OTP and activates failure-only fallback',async()=>{
  const saved={provider:env.otpProvider,instance:env.greenApiInstanceId,token:env.greenApiToken,fetch:globalThis.fetch,show:env.otpShowCode,failure:env.otpFailureFallback,until:env.otpFailureFallbackUntil};
  try {
    env.otpProvider='greenapi';env.greenApiInstanceId='770012345678';env.greenApiToken='fixture-secret';
    env.otpShowCode=false;env.otpFailureFallback=true;env.otpFailureFallbackUntil='';
    let sends=0,storedHash='';
    const db={query:async(sql:string,args:any[])=>{if(sql.includes('INSERT INTO auth_otp_codes'))storedHash=args[1];return {rows:[]};}} as any;
    for(const state of ['notAuthorized','blocked','starting',null]){
      globalThis.fetch=(async(url:any)=>{
        if(!String(url).includes('/getStateInstance/'))sends++;
        return {ok:true,json:async()=>({stateInstance:state,idMessage:'would-have-been-queued'})};
      }) as any;
      const result=await new AuthService(db,new WapiOtpService()).requestOtp('+77052597368');
      assert.equal(result.codeSent,false);assert.equal(result.deliveryFailed,true);
      assert.match(result.fallbackCode!,/^\d{6}$/);
      assert.equal(await (await import('bcryptjs')).compare(result.fallbackCode!,storedHash),true);
    }
    assert.equal(sends,0);
  }finally{env.otpProvider=saved.provider;env.greenApiInstanceId=saved.instance;env.greenApiToken=saved.token;globalThis.fetch=saved.fetch;env.otpShowCode=saved.show;env.otpFailureFallback=saved.failure;env.otpFailureFallbackUntil=saved.until;}
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
  const previous={bccMode:env.bccMode,bccNotifyUrl:env.bccNotifyUrl,publicApiUrl:env.publicApiUrl};
  Object.assign(env,{bccMode:'test',bccNotifyUrl:'https://domly.kz:443/api/v1/payments/bcc/webhook',publicApiUrl:'https://domly.kz'});
  try {
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
  assert.equal(payload.AMOUNT, '7500.00');
  assert.equal(payload.CURRENCY, '398');
  assert.equal(payload.CLIENT_IP, '127.0.0.1');
  assert.equal(payload.LANG, 'ru');
  assert.equal(payload.DESC, 'Оплата заказа DOMLY');
  assert.equal(JSON.parse(Buffer.from(String(payload.M_INFO),'base64').toString()).billAddrLine1, 'Kazakhstan');
  assert.match(String(payload.ORDER),/^\d{7,32}$/);
  assert.match(String(payload.P_SIGN),/^[A-F0-9]{40}$/);
  assert.match(result.paymentHtml,/<form[^>]+method="get"/);
  assert.equal(result.testMode,true);
  assert.ok(String(payload.ORDER).length >= 6);
  assert.equal((result as any).externalOrderId, payload.ORDER);
  } finally {Object.assign(env,previous);}
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
  const previous=env.bccMode;env.bccMode='test';
  try {
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
  } finally {env.bccMode=previous;}
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
    await assert.rejects(()=>service.requestOtp('+77052597368'),(e:any)=>e.code==='account_blocked');
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
    for(const account of [{role:'admin',status:'approved'},{role:'superadmin',status:'approved'}]) {
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

test('failure-only OTP fallback has no deadline and hides codes after provider acceptance',async()=>{
  const saved={show:env.otpShowCode,failure:env.otpFailureFallback,until:env.otpFailureFallbackUntil};
  let storedHash='';
  const db={query:async(sql:string,args:any[])=>{if(sql.includes('INSERT INTO auth_otp_codes'))storedHash=args[1];return {rows:[]};}} as any;
  try {
    env.otpShowCode=false;env.otpFailureFallback=true;env.otpFailureFallbackUntil='';
    const accepted=await new AuthService(db,{sendOtp:async()=>{}} as any).requestOtp('+77052597368');
    assert.equal(accepted.codeSent,true);assert.equal(accepted.fallbackCode,undefined);
    const failed=await new AuthService(db,{sendOtp:async()=>{throw Error('timeout');}} as any).requestOtp('+77052597368');
    assert.equal(failed.codeSent,false);assert.equal(failed.deliveryFailed,true);assert.match(failed.fallbackCode!,/^\d{6}$/);
    assert.equal(await (await import('bcryptjs')).compare(failed.fallbackCode!,storedHash),true);
  }finally{env.otpShowCode=saved.show;env.otpFailureFallback=saved.failure;env.otpFailureFallbackUntil=saved.until;}
});

test('blocked and rejected accounts report their status before OTP delivery or verification', async () => {
  for (const status of ['blocked','rejected']) {
    let mutations=0,deliveries=0;
    const codeHash=await (await import('bcryptjs')).hash('123456',8);
    const db={query:async(sql:string)=>{
      if (/INSERT|UPDATE/.test(sql)) mutations++;
      if(sql.includes('FROM app_users')) return {rows:[{id:'account',role:'cleaner',status}]};
      if(sql.includes('FROM auth_otp_codes')) return {rows:[{id:'otp',code_hash:codeHash}]};
      throw new Error('Unexpected query');
    }} as any;
    const service=new AuthService(db,{sendOtp:async()=>{deliveries++;}} as any);
    const matches=(error:any)=>error.status===403 && error.code===`account_${status}`;
    await assert.rejects(()=>service.requestOtp('+77052597368'),matches);
    await assert.rejects(()=>service.verifyOtp('+77052597368','123456','cleaner'),matches);
    assert.equal(mutations,0);
    assert.equal(deliveries,0);
  }
});

test('signed media URLs preserve storage references, expire and reject tampering',()=>{
  const raw=env.minioPublicUrl.replace(/\/$/,'')+'/photo_reports/user/image.jpg';
  const link=new URL(httpsMediaUrl(raw));
  assert.equal(link.pathname,'/api/v1/files/media');
  assert.equal(canonicalMediaUrl(link.toString()),raw);
  assert.equal(httpsMediaUrl(link.toString()),link.toString());
  const key=link.searchParams.get('key')!,expires=link.searchParams.get('expires')!,signature=link.searchParams.get('signature')!;
  assert.equal(verifyMediaLink(key,expires,signature),true);
  assert.equal(verifyMediaLink('private/other.jpg',expires,signature),false);
  assert.equal(verifyMediaLink(key,'1',signature),false);
  assert.equal(verifyMediaLink('../secret',expires,signature),false);
  assert.equal(httpsMediaUrl('https://external.example/image.jpg'),'https://external.example/image.jpg');
  const date=new Date();
  const mapped=mapMediaValues({photos:[raw],created_at:date},httpsMediaUrl);
  assert.equal(mapped.photos[0],link.toString());
  assert.equal(mapped.created_at,date);
});


test('order offers repeat full rounds for one, two and three available cleaners', async () => {
  for (const ids of [['a'], ['a','b'], ['a','b','c']]) {
    let clock=0;
    let orderStatus='pending_assignment';
    let available=ids.map(id=>({id}));
    const offers: any[]=[];
    const query=async(sql:string,values:any[]=[]) => {
      if(sql.startsWith('SELECT * FROM service_orders')) return {rows:[{id:'order',status:orderStatus,scheduled_date:'2030-01-02',start_time:'10:00',end_time:'12:00'}]};
      if(sql.includes("SET status='declined'")) {
        const offer=offers.find(o=>o.cleaner_id===values[1] && o.status==='offered');
        if(!offer)return {rows:[]};
        offer.status='declined';return {rows:[{id:offer.id}]};
      }
      if(sql.includes("status IN ('declined','expired')")) return {rows:offers.filter(o=>['declined','expired'].includes(o.status))};
      if(sql.startsWith('SELECT * FROM order_offers'))return {rows:offers.filter(o=>o.status==='offered')};
      if(sql.includes('ORDER BY created_at ASC'))return {rows:[...offers].sort((a,b)=>a.created_at-b.created_at)};
      if(sql.includes('INSERT INTO order_offers')) {
        let offer=offers.find(o=>o.cleaner_id===values[1]);
        if(!offer){offer={id:values[1],cleaner_id:values[1],order_id:values[0]};offers.push(offer);}
        Object.assign(offer,{status:'offered',created_at:++clock,expires_at:new Date(Date.now()+clock+120000)});
        return {rows:[{...offer}]};
      }
      if(sql.includes("SET status='waiting_cleaner'"))return {rows:[]};
      throw Error('Unexpected query: '+sql);
    };
    const db={query,transaction:async(fn:any)=>fn({query})};
    const service=new SchedulingService(db as any);
    service.availableCleaners=async()=>available;
    let offer:any=await service.offerNextCleaner('order');
    for(let turn=0;turn<ids.length*3;turn++) {
      assert.equal(offer.cleaner_id,ids[turn%ids.length]);
      assert.equal(offers.filter(o=>o.status==='offered').length,1);
      const unchanged:any=await service.offerNextCleaner('order');
      assert.equal(unchanged.expires_at,offers.find(o=>o.status==='offered').expires_at);
      offer=await service.declineOffer('order',offer.cleaner_id);
    }
    offers.forEach(o=>o.status='expired');
    available=available.slice(-1);
    const renewed:any=await service.offerNextCleaner('order',ids);
    assert.equal(renewed.cleaner_id,ids[ids.length-1]);
    offers.forEach(o=>o.status='expired');available=[];
    assert.equal(await service.offerNextCleaner('order',ids),null);
    for(const status of ['assigned','cancelled','completed','in_progress']) {
      orderStatus=status;
      assert.equal(await service.offerNextCleaner('order',ids),null);
    }
  }
});

test('unpaid extras block cleaner dispatch and acceptance even with stale assignment status', async () => {
  let reads = 0;
  const db = {transaction: async (fn: any) => fn({query: async (sql: string) => {
    if (sql.includes('FROM service_orders')) {
      reads++;
      return {rows: [{id: 'order', status: 'pending_assignment', payable_amount: '1500.00'}]};
    }
    if (sql.includes('FROM app_users')) return {rows: [{id: 'cleaner'}]};
    throw new Error('Unpaid order must not reach assignment queries');
  }})};
  const scheduling = new SchedulingService(db as any);
  assert.equal(await scheduling.offerNextCleaner('order'), null);
  await assert.rejects(scheduling.acceptOffer('order', 'cleaner'), (error: any) => error.code === 'order_unavailable');
  assert.equal(reads, 2);
});

test('Kazakh system translations retain dynamic values and parameter names', async()=>{
 const {translateKazakh}=await import('../localization');
 assert.equal(translateKazakh('Разовый пакет'),'Бір реттік пакет');
 const translated=translateKazakh('Подтверждённая площадь квартиры: 110 м².');
 assert.ok(translated.includes('110'));assert.ok(!translated.includes('площадь'));
 assert.equal(translateKazakh('unregistered-external-text'),'unregistered-external-text');
});

test('push messages use each recipient language without mixing device groups',async()=>{
 const {sendLocalizedPush}=await import('../localization');const calls:any[]=[];
 const db={query:async(sql:string,args:any[])=>{assert.ok(sql.includes('u.id=$1'));assert.deepEqual(args,['user-kk']);return {rows:[{token:'kk-device',language:'kk'},{token:'ru-device',language:'ru'}]};}} as any;
 await sendLocalizedPush(db,{send:async(...args:any[])=>calls.push(args)},{userId:'user-kk',titleRu:'Площадь подтверждена',bodyRu:'Подтверждённая площадь квартиры: 110 м².'},{notificationId:'fixture'});
 assert.equal(calls.length,2);assert.deepEqual(calls[0][0],['ru-device']);assert.equal(calls[0][1],'Площадь подтверждена');assert.deepEqual(calls[1][0],['kk-device']);assert.equal(calls[1][1],'Аудан расталды');assert.ok(calls[1][2].includes('110'));assert.ok(!calls[1][2].includes('площадь'));assert.deepEqual(calls[1][3],{notificationId:'fixture'});
});

test('booking date validation rejects malformed, rolled-over and past local times',async()=>{
  const {validateBookingStart}=await import('../modules/bookingValidation');
  const now=Date.parse('2026-10-23T10:00:00Z');
  for(const [day,time] of [['2026-02-30','12:00'],['2001-01-01','08:00'],['2026-10-23','14:59'],['2026-11-01','24:00'],['2026-11-01','wrong']]) {
    assert.throws(()=>validateBookingStart(day,time,now));
  }
  assert.doesNotThrow(()=>validateBookingStart('2026-10-23','15:01',now));
  assert.doesNotThrow(()=>validateBookingStart('2026-11-01','08:00:00',now));
});

test('all web bootstraps preserve detail identifiers before Flutter starts', async () => {
  const {runInNewContext} = await import('node:vm');
  for (const surface of ['domly', 'domly_pro', 'admin']) {
    const script = fs.readFileSync(`../scripts/build_web_${surface}.sh`, 'utf8');
    const source = script.split('"""  <script>')[1].split('</script>')[0];
    const route = '/cleaner/checklist?orderId=11111111-1111-4111-8111-111111111111';
    const window: any = {
      location: {hash: '#' + route, href: 'https://example.test/pro/#' + route},
      history: {replaceState() {}}, setInterval() {}, clearInterval() {},
      addEventListener() {}, sessionStorage: {getItem() {return null;}, setItem() {}}
    };
    runInNewContext(source, {window, URL, Date, navigator: {}, document: {addEventListener() {}}, fetch: () => Promise.resolve({ok: false})});
    assert.equal(window.name, 'domly_boot_route=' + route, surface);
    assert.equal(window.__domlyBootRoute, route, surface);
  }
});

test('role notification uses one recipient batch without dropping recipients or bypassing live role filtering',async()=>{
  const realtime=require('../realtime/sse');const originalOne=realtime.publishToUser,originalMany=realtime.publishToUsers;
  const users=Array.from({length:100},(_,i)=>({id:'recipient-'+i}));const calls:Array<{ids:string[];event:any}>=[];
  realtime.publishToUser=async(id:string,event:any)=>{calls.push({ids:[id],event});};
  realtime.publishToUsers=async(ids:string[],event:any)=>{calls.push({ids,event});};
  const db:any={query:async(sql:string,params:any[])=>{
    if(sql.includes('SELECT id FROM app_users WHERE role=')){assert.match(sql,/status <> 'blocked'/);assert.equal(params[0],'admin');return{rows:users};}
    return {rows:[]};
  }};
  try {
    const row={id:'notification-batch',user_id:null,role:'admin'};
    await new NotificationService(db,{send:async()=>undefined} as any).deliver(row,{role:'admin',titleRu:'Новый заказ',bodyRu:'Создан заказ'});
    assert.equal(calls.length,1,'one stored role event must not require one Redis round trip per recipient');
    assert.deepEqual(calls[0].ids,users.map(u=>u.id));assert.equal(calls[0].event.notification.id,row.id);
  } finally {realtime.publishToUser=originalOne;if(originalMany)realtime.publishToUsers=originalMany;else delete realtime.publishToUsers;}
});


test('public text catalogue coalesces concurrent readers, expires and invalidates edits', async () => {
  let calls=0,now=0;
  const cache=new PublicTextCatalog(async()=>{calls++;return [{ru:'value '+calls}];},()=>now);
  const responses=await Promise.all(Array.from({length:1000},()=>cache.get()));
  assert.equal(gunzipSync(responses[0].gzip).toString(),responses[0].body);
  assert.equal(calls,1);assert.ok(responses.every(r=>r.body===responses[0].body));
  now=5001;const next=await cache.get();assert.equal(calls,2);assert.notEqual(next.etag,responses[0].etag);
  cache.invalidate();await cache.get();assert.equal(calls,3);
});

test('public text catalogue retries errors and cannot cache an outdated in-flight edit', async () => {
  let calls=0,release!: (rows: unknown[])=>void;
  const cache=new PublicTextCatalog(async()=>{
    calls++;if(calls===1)throw Error('offline');
    if(calls===2)return new Promise<unknown[]>(resolve=>release=resolve);
    return [{ru:'new'}];
  });
  await assert.rejects(cache.get(),/offline/);
  const old=cache.get();cache.invalidate();
  const current=await cache.get();release([{ru:'old'}]);await old;
  assert.equal((await cache.get()).body,current.body);assert.equal(calls,3);
});

test('legacy oven paragraphs and included items render without a new client', () => {
  const source = 'Удаление жира.  В стоимость входит:  Очистка стенок.  Очистка дверцы.  Размер техники: духовка до 70 литров.';
  assert.equal(formatServiceDescription(source), 'Удаление жира.\n\nВ стоимость входит:\n• Очистка стенок.\n• Очистка дверцы.\n\nРазмер техники: духовка до 70 литров.');
  const result = formatServiceDescription(source);
  assert.equal(formatServiceDescription(result), result);
});

test('preserves explicit paragraphs, ordinary text, amounts and missing values', () => {
  for (const value of [null, undefined, '', 'Цена: 2  500.00 ₸', 'Текст. Обычный текст.', 'Входит:\n\n• Пункт 1.\n• Пункт 2.', 'Слово  слово  слово', 'Абзац.\r\nВторой абзац.']) {
    assert.equal(formatServiceDescription(value), value);
  }
});

test('formats both languages without changing source records or business fields', () => {
  const row = { id:'oven', price:'2500.00', duration_minutes:25, description_ru:'Описание.  Что входит:  Первый пункт.  Второй пункт.', description_kk:'Сипаттама.  Құнына кіреді:  Бірінші.  Екінші.' };
  const result = formatAddonRecord(row);
  assert.equal(result.price,row.price);
  assert.equal(result.duration_minutes,row.duration_minutes);
  assert.ok(result.description_ru.includes('\n• Первый'));
  assert.ok(result.description_kk.includes('\n• Бірінші'));
  assert.ok(!row.description_ru.includes('\n'));
});


test('cleaner offer pushes request background priority, audible channels and retain order navigation', () => {
  for (const targetType of ['order_offer','new_order_offer','scheduled_order_offer']) {
    const data={targetType,targetId:'order-1',notificationId:'notification-1'};
    const message=buildFcmMessage(['device'],'Заказ','Подтвердите заказ',data);
    assert.equal(message.android?.priority,'high');
    assert.equal(message.android?.notification?.channelId,'domly_order_offer_alarm_v2');
    assert.equal(message.android?.notification?.sound,'domly_order_alarm');
    assert.equal(message.apns?.payload?.aps.sound,'default');
    assert.equal(message.webpush?.headers?.Urgency,'high');
    const webLink=new URL(message.webpush!.fcmOptions!.link!);
    assert.equal(webLink.pathname,'/pro/');
    assert.equal(webLink.hash,'#/cleaner/orders?focusOrderId=order-1');
    assert.deepEqual(message.data,data);
    assert.deepEqual(message.notification,{title:'Заказ',body:'Подтвердите заказ'});
  }
  assert.equal(buildFcmMessage(['device'],'Сообщение','Текст',{targetType:'chat'}).android,undefined);
});
