import fs from 'node:fs';

function numberEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const value = Number(raw);
  return Number.isFinite(value) ? value : fallback;
}

function boolEnv(name: string): boolean {
  return process.env[name] === 'true' || process.env[name] === '1';
}

function parseJsonObject(raw: string): Record<string, string> | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch {
    return null;
  }
}

function resolveFcmServiceAccount(): Record<string, string> | null {
  const inline = parseJsonObject(process.env.FCM_SERVICE_ACCOUNT_JSON ?? '');
  if (inline) return inline;
  const encoded = process.env.FCM_SERVICE_ACCOUNT_BASE64 ?? '';
  if (encoded) {
    const parsed = parseJsonObject(Buffer.from(encoded, 'base64').toString('utf8'));
    if (parsed) return parsed;
  }
  const file = process.env.FCM_SERVICE_ACCOUNT_FILE ?? '';
  if (file && fs.existsSync(file)) {
    const parsed = parseJsonObject(fs.readFileSync(file, 'utf8'));
    if (parsed) return parsed;
  }
  return null;
}

const fcmServiceAccount = resolveFcmServiceAccount();

export const env = {
  nodeEnv: process.env.NODE_ENV ?? 'development',
  port: numberEnv('PORT', 8080),
  databaseUrl: process.env.DATABASE_URL ?? 'postgres://postgres:postgres@localhost:5432/domly',
  redisUrl: process.env.REDIS_URL ?? 'redis://localhost:6379',
  jwtAccessSecret: process.env.JWT_ACCESS_SECRET ?? 'dev_access_secret_change_me',
  jwtRefreshSecret: process.env.JWT_REFRESH_SECRET ?? 'dev_refresh_secret_change_me',
  jwtAccessTtlSeconds: numberEnv('JWT_ACCESS_TTL_SECONDS', 900),
  jwtRefreshTtlSeconds: numberEnv('JWT_REFRESH_TTL_SECONDS', 2592000),
  wapiToken: process.env.WAPI_TOKEN ?? '',
  wapiProfileId: process.env.WAPI_PROFILE_ID ?? '',
  wapiBaseUrl: process.env.WAPI_BASE_URL ?? 'https://wappi.pro/api',
  publicApiUrl: process.env.PUBLIC_API_URL ?? 'http://localhost:8080',
  kaspiMerchantId: process.env.KASPI_MERCHANT_ID ?? '',
  kaspiApiKey: process.env.KASPI_API_KEY ?? '',
  kaspiBaseUrl: process.env.KASPI_BASE_URL ?? '',
  moonAiWebhookToken: process.env.MOON_AI_WEBHOOK_TOKEN ?? '',
  bccMerchantId: process.env.BCC_MERCHANT_ID ?? '',
  bccTerminalId: process.env.BCC_TERMINAL_ID ?? '',
  bccPrivateKey: process.env.BCC_PRIVATE_KEY ?? '',
  bccPublicKey: process.env.BCC_PUBLIC_KEY ?? '',
  bccNotifyUrl: process.env.BCC_NOTIFY_URL ?? '',
  bccReturnUrl: process.env.BCC_RETURN_URL ?? '',
  minioEndpoint: process.env.MINIO_ENDPOINT ?? 'localhost',
  minioPort: numberEnv('MINIO_PORT', 9000),
  minioUseSsl: boolEnv('MINIO_USE_SSL'),
  minioAccessKey: process.env.MINIO_ACCESS_KEY ?? 'domly_minio',
  minioSecretKey: process.env.MINIO_SECRET_KEY ?? 'change_me',
  minioBucket: process.env.MINIO_BUCKET ?? 'domly',
  minioPublicUrl: process.env.MINIO_PUBLIC_URL ?? 'http://localhost:9000/domly',
  fcmServiceAccountJson: process.env.FCM_SERVICE_ACCOUNT_JSON ?? '',
  fcmServiceAccountBase64: process.env.FCM_SERVICE_ACCOUNT_BASE64 ?? '',
  fcmServiceAccountFile: process.env.FCM_SERVICE_ACCOUNT_FILE ?? '',
  fcmProjectId: process.env.FCM_PROJECT_ID || fcmServiceAccount?.project_id || '',
  fcmClientEmail: process.env.FCM_CLIENT_EMAIL || fcmServiceAccount?.client_email || '',
  fcmPrivateKey: (process.env.FCM_PRIVATE_KEY || fcmServiceAccount?.private_key || '').replace(/\\n/g, '\n'),
  osmNominatimUrl: process.env.OSM_NOMINATIM_URL ?? 'https://nominatim.openstreetmap.org/search',
  yandexGeocoderApiKey: process.env.YANDEX_GEOCODER_API_KEY ?? '',
  yandexGeosuggestApiKey: process.env.YANDEX_GEOSUGGEST_API_KEY ?? '',
  strictEnv: boolEnv('STRICT_ENV'),
  requireExternalIntegrations: boolEnv('REQUIRE_EXTERNAL_INTEGRATIONS'),
  requireWapi: boolEnv('REQUIRE_WAPI'),
  requireFcm: boolEnv('REQUIRE_FCM'),
  requirePayments: boolEnv('REQUIRE_PAYMENTS'),
  requireAddressFallback: boolEnv('REQUIRE_ADDRESS_FALLBACK'),
};

export type EnvConfig = typeof env;

export class EnvValidationError extends Error {
  constructor(public readonly issues: string[]) {
    super(`Invalid DOMLY backend environment:\n- ${issues.join('\n- ')}`);
  }
}

function isMissing(value: string | number | boolean | undefined | null): boolean {
  return value === undefined || value === null || value === '';
}

function isPlaceholder(value: string): boolean {
  const normalized = value.toLowerCase();
  return normalized.includes('change_me') || normalized.startsWith('dev_') || normalized === 'domly_minio';
}

function missingFields(config: EnvConfig, fields: Array<keyof EnvConfig>): string[] {
  return fields.filter((field) => isMissing(config[field])).map(String);
}

function hasAnyField(config: EnvConfig, fields: Array<keyof EnvConfig>): boolean {
  return fields.some((field) => !isMissing(config[field]));
}

function isValidHttpUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === 'http:' || url.protocol === 'https:';
  } catch {
    return false;
  }
}

function isHttpsPublicUrl(value: string): boolean {
  try {
    const url = new URL(value);
    const hostname = url.hostname.toLowerCase();
    const isLocal = hostname === 'localhost' || hostname === '0.0.0.0' || hostname === '::1' || hostname.startsWith('127.');
    return url.protocol === 'https:' && !isLocal;
  } catch {
    return false;
  }
}

function hasExplicitUrlPort(value: string): boolean {
  return /^https?:\/\/(?:\[[^\]]+\]|[^/?#:]+):\d+(?:[/?#]|$)/i.test(value);
}

export function validateEnvConfig(config: EnvConfig = env): { ok: boolean; issues: string[]; warnings: string[] } {
  const strict = config.strictEnv || config.nodeEnv === 'production';
  const requireExternal = config.requireExternalIntegrations;
  const issues: string[] = [];
  const warnings: string[] = [];

  for (const field of missingFields(config, ['databaseUrl', 'redisUrl', 'publicApiUrl', 'minioEndpoint', 'minioAccessKey', 'minioSecretKey', 'minioBucket', 'minioPublicUrl'])) {
    issues.push(`${field} is required`);
  }

  if (!Number.isInteger(config.port) || config.port <= 0) issues.push('PORT must be a positive number');
  if (!Number.isInteger(config.minioPort) || config.minioPort <= 0) issues.push('MINIO_PORT must be a positive number');
  if (!Number.isInteger(config.jwtAccessTtlSeconds) || config.jwtAccessTtlSeconds <= 0) issues.push('JWT_ACCESS_TTL_SECONDS must be a positive number');
  if (!Number.isInteger(config.jwtRefreshTtlSeconds) || config.jwtRefreshTtlSeconds <= 0) issues.push('JWT_REFRESH_TTL_SECONDS must be a positive number');

  if (strict) {
    if (isPlaceholder(config.jwtAccessSecret) || config.jwtAccessSecret.length < 32) issues.push('JWT_ACCESS_SECRET must be a real secret with at least 32 characters');
    if (isPlaceholder(config.jwtRefreshSecret) || config.jwtRefreshSecret.length < 32) issues.push('JWT_REFRESH_SECRET must be a real secret with at least 32 characters');
    if (isPlaceholder(config.minioSecretKey)) issues.push('MINIO_SECRET_KEY must be changed from placeholder');
    if (!isHttpsPublicUrl(config.publicApiUrl)) issues.push('PUBLIC_API_URL must be a public HTTPS URL in production');
  }

  const missingWapi = missingFields(config, ['wapiToken', 'wapiProfileId']);
  const missingFcm = missingFields(config, ['fcmProjectId', 'fcmClientEmail', 'fcmPrivateKey']);
  const kaspiFields: Array<keyof EnvConfig> = ['kaspiMerchantId', 'kaspiApiKey', 'kaspiBaseUrl'];
  const bccFields: Array<keyof EnvConfig> = ['bccMerchantId', 'bccTerminalId', 'bccPrivateKey', 'bccPublicKey', 'bccNotifyUrl', 'bccReturnUrl'];
  const missingKaspi = missingFields(config, kaspiFields);
  const missingBcc = missingFields(config, bccFields);
  const kaspiConfigured = hasAnyField(config, kaspiFields);
  const bccConfigured = hasAnyField(config, bccFields);
  const missingYandex = missingFields(config, ['yandexGeocoderApiKey', 'yandexGeosuggestApiKey']);

  const requireWapi = requireExternal || config.requireWapi;
  const requireFcm = requireExternal || config.requireFcm;
  const requirePayments = requireExternal || config.requirePayments;
  const requireAddressFallback = requireExternal || config.requireAddressFallback;

  if (requireWapi && missingWapi.length) issues.push(`WAPI is required: ${missingWapi.join(', ')}`);
  else if (missingWapi.length) warnings.push(`WAPI is not fully configured: ${missingWapi.join(', ')}`);

  if (requireFcm && missingFcm.length) issues.push(`FCM is required: ${missingFcm.join(', ')}`);
  else if (missingFcm.length) warnings.push(`FCM is not fully configured: ${missingFcm.join(', ')}`);

  if (kaspiConfigured && config.kaspiBaseUrl && !isValidHttpUrl(config.kaspiBaseUrl)) {
    issues.push('KASPI_BASE_URL must be a valid http(s) URL');
  }
  if (strict && kaspiConfigured && config.kaspiBaseUrl && !isHttpsPublicUrl(config.kaspiBaseUrl)) {
    issues.push('KASPI_BASE_URL must be a public HTTPS URL in production');
  }

  if (bccConfigured) {
    if (config.bccNotifyUrl && !isValidHttpUrl(config.bccNotifyUrl)) issues.push('BCC_NOTIFY_URL must be a valid http(s) URL');
    if (strict && config.bccNotifyUrl && !isHttpsPublicUrl(config.bccNotifyUrl)) issues.push('BCC_NOTIFY_URL must be a public HTTPS URL in production');
    if (config.bccNotifyUrl && isValidHttpUrl(config.bccNotifyUrl) && !hasExplicitUrlPort(config.bccNotifyUrl)) {
      issues.push('BCC_NOTIFY_URL must include an explicit port for TRTYPE=1, for example https://api.domly.kz:443/api/v1/payments/bcc/webhook');
    }
    if (config.bccReturnUrl && !isValidHttpUrl(config.bccReturnUrl)) issues.push('BCC_RETURN_URL must be a valid http(s) URL');
    if (strict && config.bccReturnUrl && !isHttpsPublicUrl(config.bccReturnUrl)) issues.push('BCC_RETURN_URL must be a public HTTPS URL in production');
  }

  if (requirePayments && missingKaspi.length && missingBcc.length) {
    issues.push(`At least one payment provider must be fully configured: Kaspi (${missingKaspi.join(', ')}) or BCC (${missingBcc.join(', ')})`);
  }
  else {
    if (missingKaspi.length) warnings.push(`Kaspi is not fully configured: ${missingKaspi.join(', ')}`);
    if (missingBcc.length) warnings.push(`BCC is not fully configured: ${missingBcc.join(', ')}`);
  }

  if (requireAddressFallback && missingYandex.length) issues.push(`Yandex address fallback is required: ${missingYandex.join(', ')}`);
  else if (missingYandex.length) warnings.push(`Yandex address fallback is not fully configured: ${missingYandex.join(', ')}`);

  return { ok: issues.length === 0, issues, warnings };
}

export function validateEnvForRuntime(): void {
  const report = validateEnvConfig(env);
  if (report.warnings.length) {
    for (const warning of report.warnings) console.warn(`[env] ${warning}`);
  }
  if (!report.ok) throw new EnvValidationError(report.issues);
}
