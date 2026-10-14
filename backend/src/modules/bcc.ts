import crypto from 'node:crypto';
import { env, EnvConfig } from '../common/env';
import { ApiError } from '../common/api';

// Public sandbox credentials from BCC e-Commerce WEBVIEW documentation.
export const BCC_TEST = {
  gatewayUrl: 'https://test3ds.bcc.kz:5445/cgi-bin/cgi_link',
  merchantId: '00000001', terminalId: '88888881',
  macKey: '6BB0AC02E47BDF73D98FEB777F3B5294',
};

export function bccConfig(config: EnvConfig = env) {
  const test = config.bccMode === 'test';
  return {
    enabled: ['test','live'].includes(config.bccMode), test,
    gatewayUrl: test ? BCC_TEST.gatewayUrl : config.bccGatewayUrl || 'https://3dsecure.bcc.kz/webview',
    merchantId: test ? BCC_TEST.merchantId : config.bccMerchantId,
    terminalId: test ? BCC_TEST.terminalId : config.bccTerminalId,
    macKey: test ? BCC_TEST.macKey : config.bccPrivateKey,
    merchantName: config.bccMerchantName,
    notifyUrl: config.bccNotifyUrl,
    returnUrl: `${config.publicApiUrl.replace(/\/$/,'')}/api/v1/payments/bcc/return`,
  };
}

export function bccReady(config: EnvConfig = env): boolean {
  const c = bccConfig(config);
  return Boolean(c.enabled && c.merchantId && c.terminalId && /^[a-f0-9]{32,64}$/i.test(c.macKey)
    && c.notifyUrl && c.returnUrl && (c.test || !['88888881','88888888'].includes(c.terminalId)));
}

const macFields: Record<string,string[]> = {
  '1': ['AMOUNT','CURRENCY','ORDER','MERCHANT','TERMINAL','MERCH_GMT','TIMESTAMP','TRTYPE','NONCE'],
  '90': ['ORDER','TERMINAL','TIMESTAMP','TRTYPE','NONCE'],
  '14': ['ORDER','ORG_AMOUNT','AMOUNT','CURRENCY','RRN','INT_REF','TERMINAL','TIMESTAMP','TRTYPE','NONCE'],
};
export function bccSign(fields: Record<string,unknown>, keyHex: string): string {
  const names = macFields[String(fields.TRTYPE)];
  if (!names || !/^[a-f0-9]{32,64}$/i.test(keyHex)) throw new ApiError(503,'bcc_not_configured','Не настроена подпись BCC.');
  const source = names.map(name => {
    const value = String(fields[name] ?? '');
    return `${Buffer.byteLength(value,'utf8')}${value}`;
  }).join('');
  return crypto.createHmac('sha1',Buffer.from(keyHex,'hex')).update(source,'utf8').digest('hex').toUpperCase();
}

export function bccTimestamp(date = new Date()): string {
  return date.toISOString().replace(/[-:T]/g,'').slice(0,14);
}
export function bccNonce(): string { return crypto.randomBytes(16).toString('hex').toUpperCase(); }

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}
export function bccPaymentHtml(actionUrl: string, fields: Record<string,unknown>, method: 'get'|'post' = 'post'): string {
  const inputs = Object.entries(fields).map(([name,value])=>`<input type="hidden" name="${escapeHtml(name)}" value="${escapeHtml(value)}">`).join('\n');
  return `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Domly — BCC</title></head><body><p>Открываем страницу банка…</p><form id="bcc-payment" method="${method}" action="${escapeHtml(actionUrl)}">${inputs}<button type="submit">Перейти к оплате</button></form><script>document.getElementById('bcc-payment').submit();</script></body></html>`;
}

function decodeHtml(value: string): string {
  return value.replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&');
}
export function parseBccResponse(raw: string): Record<string,string> {
  try {
    const object = JSON.parse(raw);
    if (object && typeof object==='object' && !Array.isArray(object)) return Object.fromEntries(Object.entries(object).map(([key,value])=>[key.toUpperCase(),String(value)]));
  } catch (_) {}
  const result: Record<string,string> = {};
  for (const tag of raw.match(/<input\b[^>]*>/gi) ?? []) {
    const attributes: Record<string,string> = {};
    for (const match of tag.matchAll(/([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g)) attributes[match[1].toLowerCase()] = decodeHtml(match[2] ?? match[3] ?? match[4]);
    if (attributes.name && attributes.value!==undefined) result[attributes.name.toUpperCase()] = attributes.value;
  }
  for (const match of raw.matchAll(/<([A-Z_]+)>([^<]*)<\/\1>/g)) result[match[1]] = decodeHtml(match[2]);
  if (!Object.keys(result).length && /(?:^|&)ACTION=/.test(raw)) {
    for (const [key,value] of new URLSearchParams(raw.trim())) result[key.toUpperCase()] = value;
  }
  return result;
}

export function bccResultStatus(fields: Record<string,unknown>): 'paid'|'rejected'|'cancelled'|'pending' {
  const action = String(fields.ACTION ?? ''), rc = String(fields.RC ?? '');
  if (['-16','-31','-33','-34','-39','-40','-43','-46','-47'].includes(rc)) return 'pending';
  if (action==='0' && (rc==='00'||rc==='0')) return 'paid';
  if (action==='14' || ['-25','-35','-36'].includes(rc)) return 'cancelled';
  if (['2','3','6','7','8'].includes(action)) return 'rejected';
  return 'pending';
}

export async function postBccFields(fields: Record<string,unknown>, fetcher: typeof fetch = fetch) {
  const c = bccConfig();
  const params = new URLSearchParams(Object.entries(fields).map(([key,value])=>[key,String(value)]));
  // The public sandbox currently rejects POST with a CGI form-decoding error.
  // Only non-card server operations use GET here; live traffic always uses POST.
  const response = await fetcher(c.test ? c.gatewayUrl+'?'+params.toString() : c.gatewayUrl,{method:c.test?'GET':'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
    ...(c.test ? {} : {body:params}),
    signal:AbortSignal.timeout(15000),redirect:'error'});
  if (!response.ok) throw new ApiError(502,'bcc_unavailable','Сервис BCC временно недоступен. Попробуйте позже.');
  const raw = await response.text();
  const result = parseBccResponse(raw);
  if (!result.ACTION || result.RC===undefined) throw new ApiError(502,'bcc_invalid_response','Банк не вернул статус платежа. Попробуйте проверить оплату позже.');
  return result;
}
