import {residentialComplexHouses} from './residentialComplexHouses';
import admin from 'firebase-admin';
import crypto from 'crypto';
import { Client as MinioClient } from 'minio';
import { Queue } from 'bullmq';
import IORedis from 'ioredis';
import { env, otpDeliveryReady } from '../common/env';
import { ApiError } from '../common/api';
import { bccConfig, bccReady, bccSign, bccTimestamp, bccNonce, bccPaymentHtml } from './bcc';

export class WapiOtpService {
  async sendOtp(phone: string, code: string): Promise<void> {
    if (!/^\+?7\d{10}$/.test(phone) || !/^\d{6}$/.test(code)) throw new ApiError(400,'invalid_otp_payload','Укажите корректный номер и шестизначный код.');
    if (!otpDeliveryReady()) throw new ApiError(503, 'integration_error', 'Сервис отправки кодов не настроен.');
    try {
      if (env.otpProvider==='greenapi') {
        // Green API can enqueue messages while WhatsApp is disconnected.
        const stateResponse=await fetch(`https://7700.api.greenapi.com/waInstance${env.greenApiInstanceId}/getStateInstance/${env.greenApiToken}`,{signal:AbortSignal.timeout(5000)});
        if(!stateResponse.ok)throw new Error('delivery_unavailable');
        const state=await stateResponse.json() as {stateInstance?:unknown};
        if(state.stateInstance!=='authorized')throw new Error('delivery_unavailable');
        const response=await fetch(`https://7700.api.greenapi.com/waInstance${env.greenApiInstanceId}/sendMessage/${env.greenApiToken}`,{
          method:'POST',signal:AbortSignal.timeout(10000),headers:{'Content-Type':'application/json'},
          body:JSON.stringify({chatId:phone.replace(/^\+/,'')+'@c.us',message:`DOMLY код подтверждения: ${code}`}),
        });
        if(!response.ok)throw new Error('delivery_failed');
        const result=await response.json() as {idMessage?:unknown};
        if(typeof result.idMessage!=='string'||!result.idMessage.trim())throw new Error('delivery_failed');
        return;
      }
      const response = await fetch(`${env.wapiBaseUrl}/sync/message/send?profile_id=${env.wapiProfileId}`, {
        method: 'POST',
        signal: AbortSignal.timeout(10000),
        headers: { Authorization: env.wapiToken, 'Content-Type': 'application/json' },
        body: JSON.stringify({recipient: phone.replace(/^\+/, ''), body: `DOMLY код подтверждения: ${code}`}),
      });
      if (!response.ok) throw new Error('delivery_failed');
      const result = await response.json() as {status?: string; error?: unknown};
      if (result.error || ['error','failed','failure'].includes(String(result.status ?? '').toLowerCase())) throw new Error('delivery_failed');
    } catch (_) {
      throw new ApiError(503, 'integration_error', 'Не удалось отправить SMS-код. Попробуйте позже.');
    }
  }
}

export function buildFcmMessage(tokens: string[], title: string, body: string, data: Record<string,string>): admin.messaging.MulticastMessage {
  const offer = ['order_offer','new_order_offer','scheduled_order_offer'].includes(data.targetType || data.type);
  return {
    tokens, notification: {title, body}, data,
    ...(offer ? {
      android: {priority: 'high' as const, notification: {
        channelId: 'domly_order_offer_alarm_v2', sound: 'domly_order_alarm',
        priority: 'max' as const, defaultVibrateTimings: true,
      }},
      apns: {headers: {'apns-priority': '10'}, payload: {aps: {sound: 'default'}}},
      webpush: {
        headers: {Urgency: 'high'},
        notification: {requireInteraction: true},
        fcmOptions: {link: `${env.publicApiUrl.replace(/\/$/, '')}/pro/#/cleaner/orders?focusOrderId=${encodeURIComponent(data.targetId || data.orderId || '')}`},
      },
    } : {}),
  };
}

export class FcmService {
  private initialized = false;

  private init(): void {
    if (this.initialized || !env.fcmProjectId || !env.fcmClientEmail || !env.fcmPrivateKey) return;
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: env.fcmProjectId,
          clientEmail: env.fcmClientEmail,
          privateKey: env.fcmPrivateKey,
        }),
      });
    }
    this.initialized = true;
  }

  async send(tokens: string[], title: string, body: string, data: Record<string, string> = {}) {
    this.init();
    if (!this.initialized || tokens.length === 0) return { sent: 0, failed: 0, skipped: true };
    try {
      const result = await admin.messaging().sendEachForMulticast(buildFcmMessage(tokens, title, body, data));
      const invalidTokens = result.responses.flatMap((response,index) =>
        ['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(response.error?.code ?? '') ? [tokens[index]] : []);
      return { sent: result.successCount, failed: result.failureCount, skipped: false, invalidTokens,
        retryableFailed: result.failureCount-invalidTokens.length };
    } catch (error) {
      console.warn('[fcm] push failed', error instanceof Error ? error.message : String(error));
      return { sent: 0, failed: tokens.length, skipped: false, error: 'fcm_send_failed' };
    }
  }
}

export class StorageService {
  readonly client = new MinioClient({
    endPoint: env.minioEndpoint,
    port: env.minioPort,
    useSSL: env.minioUseSsl,
    accessKey: env.minioAccessKey,
    secretKey: env.minioSecretKey,
  });

  async uploadBuffer(objectKey: string, buffer: Buffer, mimeType?: string): Promise<string> {
    const exists = await this.client.bucketExists(env.minioBucket).catch(() => false);
    if (!exists) await this.client.makeBucket(env.minioBucket);
    await this.client.putObject(env.minioBucket, objectKey, buffer, buffer.length, {
      'Content-Type': mimeType ?? 'application/octet-stream',
    });
    return `${env.minioPublicUrl.replace(/\/$/, '')}/${objectKey}`;
  }
}

export class PaymentGatewayService {
  async createKaspiInvoice(input: {
    paymentId: string;
    amount: number;
    phone?: string;
    description: string;
  }) {
    const payload = {
      merchantId: env.kaspiMerchantId,
      orderId: input.paymentId,
      amount: input.amount,
      phone: input.phone?.replace(/\D/g, ''),
      description: input.description,
      notifyUrl: `${env.publicApiUrl.replace(/\/$/, '')}/api/v1/payments/kaspi/webhook`,
    };
    if (!env.kaspiBaseUrl || !env.kaspiApiKey) return { providerPayload: payload, providerResponse: null, paymentUrl: null };
    const response = await fetch(`${env.kaspiBaseUrl.replace(/\/$/, '')}/invoice`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.kaspiApiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) return { providerPayload: payload, providerResponse: data, paymentUrl: null };
    return { providerPayload: payload, providerResponse: data, paymentUrl: data.paymentUrl ?? data.url ?? null };
  }

  async createBccPayment(input: {
    paymentId: string;
    amount: number;
    description: string;
    clientIp?: string;
    language?: string;
    mInfo?: string;
    customerPhone?: string;
    externalOrderId?: string;
  }) {
    if (!bccReady()) throw new ApiError(503,'bcc_not_configured','Онлайн-оплата BCC не настроена.');
    if (!Number.isFinite(input.amount) || input.amount<=0) throw new ApiError(400,'invalid_amount','Укажите сумму платежа.');
    const config = bccConfig();
    const orderId = input.externalOrderId ?? this.bccOrderId(input.paymentId);
    const returnUrl = new URL(config.returnUrl);
    returnUrl.searchParams.set('paymentId',input.paymentId);
    const phone = String(input.customerPhone ?? '').replace(/\D/g,'');
    const mInfo: Record<string,unknown> = {browserScreenHeight:'1920',browserScreenWidth:'1080',billAddrLine1:config.test?'Kazakhstan':toLatin(input.mInfo ?? 'Kazakhstan').slice(0,50)};
    if (!config.test && phone.length>=10) mInfo.mobilePhone={cc:'7',subscriber:phone.slice(-10)};
    const payload = {
      TRTYPE: '1',
      AMOUNT: input.amount.toFixed(2),
      CURRENCY: '398',
      ORDER: orderId,
      DESC: input.description,
      M_INFO: Buffer.from(JSON.stringify(mInfo),'utf8').toString('base64'),
      MERCH_RN_ID: '1'+bccNonce().slice(0,15),
      MERCHANT: config.merchantId,
      MERCH_NAME: config.merchantName,
      TERMINAL: config.terminalId,
      TIMESTAMP: bccTimestamp(),
      NONCE: bccNonce(),
      MERCH_GMT: '0',
      CLIENT_IP: input.clientIp ?? '127.0.0.1',
      LANG: input.language ?? 'ru',
      NOTIFY_URL: config.notifyUrl,
      BACKREF: returnUrl.toString(),
      MK_TOKEN: 'MERCH',
    };
    const providerPayload = {...payload,P_SIGN:bccSign(payload,config.macKey)};
    return { providerPayload, providerResponse:null,paymentUrl:null,externalOrderId:orderId,
      paymentHtml:bccPaymentHtml(config.gatewayUrl,providerPayload,config.test?'get':'post'),actionUrl:config.gatewayUrl,
      orderId:input.paymentId,testMode:config.test,bccTestMode:config.test,bccSessionCreatedAt:new Date().toISOString() };
  }

  private bccOrderId(paymentId: string): string {
    return BigInt('0x'+crypto.createHash('sha256').update(paymentId).digest('hex').slice(0,24)).toString().slice(-18).padStart(7,'0');
  }

  async createBccRefund(input: {
    paymentId: string;
    amount: number;
    referenceId?: string | null;
    language?: string;
    externalOrderId?: string;
    originalAmount?: number;
    intRef?: string;
    merchRnId?: string;
  }) {
    const config = bccConfig();
    const orderId = input.externalOrderId ?? this.bccOrderId(input.paymentId);
    const payload = {
      TRTYPE: '14',
      AMOUNT: input.amount.toFixed(2),
      ORG_AMOUNT: Number(input.originalAmount ?? input.amount).toFixed(2),
      CURRENCY: '398',
      ORDER: orderId,
      MERCH_RN_ID: input.merchRnId ?? '',
      TERMINAL: config.terminalId,
      LANG: input.language ?? 'ru',
      RRN: input.referenceId ?? '',
      INT_REF: input.intRef ?? '',
      TIMESTAMP: bccTimestamp(), NONCE:bccNonce(),MERCH_GMT:'0',NOTIFY_URL:config.notifyUrl,
    };
    return { providerPayload: { ...payload, P_SIGN: bccSign(payload,config.macKey) }, providerResponse: null, paymentUrl: null, externalOrderId: orderId };
  }

  async createBccStatusCheck(input: {
    paymentId: string;
    originalTrType?: string;
    language?: string;
    externalOrderId?: string;
  }) {
    const config = bccConfig();
    const orderId = input.externalOrderId ?? this.bccOrderId(input.paymentId);
    const payload = {
      TRTYPE: '90',
      ORDER: orderId,
      TERMINAL: config.terminalId,
      TRAN_TRTYPE: input.originalTrType ?? '1',
      LANG: input.language ?? 'ru',
      TIMESTAMP:bccTimestamp(),NONCE:bccNonce(),MERCH_GMT:'0',
    };
    return { providerPayload: { ...payload, P_SIGN: bccSign(payload,config.macKey) }, providerResponse: null, paymentUrl: null, externalOrderId: orderId };
  }

  async createBccConnectionCheck(input: { language?: string }) {
    const payload = {
      TRTYPE: '800',
      TERMINAL: bccConfig().terminalId,
      LANG: input.language ?? 'ru',
    };
    return { providerPayload: payload, providerResponse: null, paymentUrl: null };
  }
}

export type AddressSuggestion = {
  source: 'connected_house' | 'osm' | 'yandex';
  label: string;
  city?: string | null;
  street?: string | null;
  house?: string | null;
  residentialComplex?: string | null;
  lat?: number | null;
  lng?: number | null;
  distanceKm?: number | null;
  raw?: unknown;
};

export class AddressSearchService {
  async externalSuggestions(input: {
    query: string;
    lang?: string;
    city?: string | null;
    lat?: number | null;
    lng?: number | null;
    radiusKm?: number;
    limit?: number;
  }): Promise<AddressSuggestion[]> {
    const radiusKm = input.radiusKm ?? 50;
    const limit = input.limit ?? 10;
    const query = [input.query, input.city].filter(Boolean).join(', ');
    const osm = await this.searchOsm({ ...input, query, radiusKm, limit }).catch(() => []);
    const expanded = await Promise.all(osm.map(row => this.expandResidentialComplex(row).catch(() => [])));
    const houses = expanded.flat();
    if (houses.length) return houses;
    if (osm.length >= Math.min(3, limit)) return osm.slice(0, limit);
    const yandex = await this.searchYandex({ ...input, query, radiusKm, limit }).catch(() => []);
    return [...osm, ...yandex].slice(0, limit);
  }

  private readonly complexCache = new Map<string, {expires: number; rows: AddressSuggestion[]}>();
  private async expandResidentialComplex(complex: AddressSuggestion): Promise<AddressSuggestion[]> {
    const raw = complex.raw as any;
    if (complex.house || !complex.residentialComplex || raw?.type !== 'residential'
        || raw?.osm_type !== 'way' || !/^\d+$/.test(String(raw?.osm_id))) return [];
    const bounds = (raw.boundingbox ?? []).map(Number);
    if (bounds.length !== 4 || bounds.some((n: number) => !Number.isFinite(n))) return [];
    const [south,north,west,east] = bounds;
    if (south >= north || west >= east || north-south > .02 || east-west > .04
        || south < -90 || north > 90 || west < -180 || east > 180) return [];
    const key = `${raw.osm_id}:${complex.city}`;
    const cached = this.complexCache.get(key);
    if (cached && cached.expires > Date.now()) return cached.rows;
    const response = await fetch(`https://api.openstreetmap.org/api/0.6/map.json?bbox=${west},${south},${east},${north}`, {
      headers: {'User-Agent':'DOMLY backend address search'}, signal:AbortSignal.timeout(7000),
    });
    if (!response.ok) return [];
    const rows = residentialComplexHouses(complex, await response.json());
    if (this.complexCache.size >= 100) this.complexCache.delete(this.complexCache.keys().next().value!);
    if (rows.length) this.complexCache.set(key,{expires:Date.now()+30*60*1000,rows});
    return rows;
  }

  async reverse(lat: number, lng: number): Promise<AddressSuggestion | null> {
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      throw new Error('Invalid coordinates');
    }
    const endpoint = new URL(env.osmNominatimUrl);
    endpoint.pathname = endpoint.pathname.replace(/search\/?$/, 'reverse');
    endpoint.search = new URLSearchParams({lat: String(lat), lon: String(lng), format: 'jsonv2', 'accept-language': 'ru'}).toString();
    const response = await fetch(endpoint, {headers: {'User-Agent': 'DOMLY backend address search'}, signal: AbortSignal.timeout(7000)});
    if (response.ok) {
      const row = await response.json() as any;
      if (row.display_name) return {source: 'osm', label: row.display_name, city: row.address?.city ?? row.address?.town ?? row.address?.village ?? null,
        street: row.address?.road ?? null, house: row.address?.house_number ?? null, residentialComplex: row.address?.residential ?? null,
        lat: Number(row.lat), lng: Number(row.lon), distanceKm: 0, raw: row};
    }
    const rows = await this.searchYandex({query: `${lng},${lat}`, lat, lng, radiusKm: 50, limit: 1});
    return rows[0] ?? null;
  }

  private async searchOsm(input: {
    query: string;
    lang?: string;
    city?: string | null;
    lat?: number | null;
    lng?: number | null;
    radiusKm: number;
    limit: number;
  }): Promise<AddressSuggestion[]> {
    if (!env.osmNominatimUrl || input.query.trim().length < 2) return [];
    const params = new URLSearchParams({
      q: input.query,
      format: 'jsonv2',
      addressdetails: '1',
      namedetails: '1',
      'accept-language': input.lang === 'kk' ? 'kk' : 'ru',
      limit: String(input.limit),
      countrycodes: 'kz',
    });
    const response = await fetch(`${env.osmNominatimUrl}?${params}`, {
      headers: { 'User-Agent': 'DOMLY backend address search' }, signal: AbortSignal.timeout(7000),
    });
    if (!response.ok) return [];
    const rows = await response.json() as any[];
    return rows
      .filter((row) => this.isAddressLike(row))
      .map((row) => {
        const lat = Number(row.lat);
        const lng = Number(row.lon);
        const distanceKm = this.distanceKm(input.lat, input.lng, lat, lng);
        return {
          source: 'osm' as const,
          label: row.display_name,
          city: row.address?.city ?? row.address?.town ?? row.address?.village ?? input.city ?? null,
          street: row.address?.road ?? row.address?.pedestrian ?? row.address?.neighbourhood ?? null,
          house: row.address?.house_number ?? null,
          residentialComplex: row.address?.residential ?? row.address?.suburb ?? null,
          lat,
          lng,
          distanceKm,
          raw: row,
        };
      })
      .filter((row) => this.inScope(row, input.city, input.lat, input.lng, input.radiusKm))
      .slice(0, input.limit);
  }

  private async searchYandex(input: {
    query: string;
    city?: string | null;
    lat?: number | null;
    lng?: number | null;
    radiusKm: number;
    limit: number;
  }): Promise<AddressSuggestion[]> {
    if (!env.yandexGeocoderApiKey || input.query.trim().length < 2) return [];
    const params = new URLSearchParams({
      apikey: env.yandexGeocoderApiKey,
      geocode: input.query,
      format: 'json',
      lang: 'ru_RU',
      kind: 'house',
      results: String(input.limit),
    });
    if (input.lat && input.lng) {
      params.set('ll', `${input.lng},${input.lat}`);
      params.set('spn', '0.45,0.45');
    }
    const response = await fetch(`https://geocode-maps.yandex.ru/1.x/?${params}`, {signal: AbortSignal.timeout(7000)});
    if (!response.ok) return [];
    const data = await response.json() as any;
    const members = data?.response?.GeoObjectCollection?.featureMember ?? [];
    return members
      .map((item: any) => {
        const object = item.GeoObject;
        const [lng, lat] = String(object?.Point?.pos ?? '').split(' ').map(Number);
        const components = object?.metaDataProperty?.GeocoderMetaData?.Address?.Components ?? [];
        const get = (kind: string) => components.find((c: any) => c.kind === kind)?.name ?? null;
        const distanceKm = this.distanceKm(input.lat, input.lng, lat, lng);
        return {
          source: 'yandex' as const,
          label: object?.metaDataProperty?.GeocoderMetaData?.text ?? object?.name,
          city: get('locality') ?? input.city ?? null,
          street: get('street') ?? object?.name ?? null,
          house: get('house'),
          residentialComplex: get('district'),
          lat,
          lng,
          distanceKm,
          raw: object,
        };
      })
      .filter((row: AddressSuggestion) => this.inScope(row, input.city, input.lat, input.lng, input.radiusKm))
      .slice(0, input.limit);
  }

  private isAddressLike(row: any): boolean {
    const cls = String(row.class ?? '');
    const type = String(row.type ?? '');
    if (['amenity', 'shop', 'tourism', 'leisure', 'office', 'craft'].includes(cls)) return false;
    return ['place', 'boundary', 'highway', 'building'].includes(cls)
      || ['house', 'residential', 'road', 'street', 'apartments'].includes(type)
      || Boolean(row.address?.road || row.address?.house_number || row.address?.residential);
  }

  private inScope(row: AddressSuggestion, city?: string | null, lat?: number | null, lng?: number | null, radiusKm = 50): boolean {
    if (city && row.city && !normalizeText(row.city).includes(normalizeText(city))) return false;
    if (lat && lng && row.distanceKm != null && row.distanceKm > radiusKm) return false;
    return true;
  }

  private distanceKm(lat1?: number | null, lng1?: number | null, lat2?: number | null, lng2?: number | null): number | null {
    if (!lat1 || !lng1 || !lat2 || !lng2 || [lat1, lng1, lat2, lng2].some((v) => !Number.isFinite(v))) return null;
    const toRad = (v: number) => v * Math.PI / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return Math.round(6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 100) / 100;
  }
}

export function normalizeText(value: string): string {
  return value
    .toLowerCase()
    .replace(/[ә]/g, 'а')
    .replace(/[і]/g, 'и')
    .replace(/[ң]/g, 'н')
    .replace(/[ғ]/g, 'г')
    .replace(/[үұ]/g, 'у')
    .replace(/[қ]/g, 'к')
    .replace(/[ө]/g, 'о')
    .replace(/[һ]/g, 'х')
    .replace(/[ы]/g, 'и')
    .replace(/ё/g, 'е')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

export function toLatin(value: string): string {
  const table: Record<string, string> = {
    а: 'a', б: 'b', в: 'v', г: 'g', ғ: 'g', д: 'd', е: 'e', ё: 'e', ж: 'zh', з: 'z',
    и: 'i', і: 'i', й: 'i', к: 'k', қ: 'k', л: 'l', м: 'm', н: 'n', ң: 'n', о: 'o',
    ө: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ұ: 'u', ү: 'u', ф: 'f', х: 'h',
    һ: 'h', ц: 'ts', ч: 'ch', ш: 'sh', щ: 'shch', ъ: '', ы: 'y', ь: '', э: 'e',
    ю: 'yu', я: 'ya', ә: 'a',
  };
  return value
    .split('')
    .map((char) => {
      const lower = char.toLowerCase();
      const mapped = table[lower];
      if (!mapped) return char;
      return char === lower ? mapped : mapped.charAt(0).toUpperCase() + mapped.slice(1);
    })
    .join('')
    .replace(/[^\x20-\x7E]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function buildQueues() {
  const connection = new IORedis(env.redisUrl, { maxRetriesPerRequest: null });
  const queues = {
    notifications: new Queue('notifications', { connection }),
    cleanerAlarms: new Queue('cleaner-alarms', { connection }),
    payments: new Queue('payments', { connection }),
    maintenance: new Queue('maintenance', { connection }),
    close: async () => {
      await Promise.all([
        queues.notifications.close(),
        queues.cleanerAlarms.close(),
        queues.payments.close(),
        queues.maintenance.close(),
      ]);
      await connection.quit();
    },
  };
  return queues;
}
