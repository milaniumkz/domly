type CheckResult = {
  name: string;
  ok: boolean;
  skipped?: boolean;
  status?: number;
  message?: string;
};

const baseUrl = (process.env.SMOKE_BASE_URL ?? process.env.PUBLIC_API_URL ?? 'http://localhost:8080').replace(/\/$/, '');
const token = process.env.SMOKE_ADMIN_TOKEN ?? '';
const testPhone = process.env.SMOKE_TEST_PHONE ?? '';

async function request(path: string, headers: Record<string, string> = {}) {
  return fetch(`${baseUrl}${path}`, {
    headers: token ? { Authorization: `Bearer ${token}`, ...headers } : headers,
  });
}

async function checkJson(name: string, path: string): Promise<CheckResult & { etag?: string }> {
  try {
    const response = await request(path);
    const text = await response.text();
    const body = text ? JSON.parse(text) : null;
    const ok = response.ok && body?.ok === true;
    return {
      name,
      ok,
      status: response.status,
      etag: response.headers.get('etag') ?? undefined,
      message: ok ? undefined : `Unexpected response: ${text.slice(0, 300)}`,
    };
  } catch (error: any) {
    return { name, ok: false, message: error?.message ?? String(error) };
  }
}

async function checkStatus(name: string, path: string, expected = 200): Promise<CheckResult> {
  try {
    const response = await request(path);
    return {
      name,
      ok: response.status === expected,
      status: response.status,
      message: response.status === expected ? undefined : `Expected ${expected}, got ${response.status}`,
    };
  } catch (error: any) {
    return { name, ok: false, message: error?.message ?? String(error) };
  }
}

async function postJson(name: string, path: string, payload: unknown): Promise<CheckResult> {
  try {
    const response = await fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(payload),
    });
    const text = await response.text();
    const body = text ? JSON.parse(text) : null;
    const ok = response.ok && body?.ok === true;
    return {
      name,
      ok,
      status: response.status,
      message: ok ? undefined : `Unexpected response: ${text.slice(0, 300)}`,
    };
  } catch (error: any) {
    return { name, ok: false, message: error?.message ?? String(error) };
  }
}

async function checkJsonShape(name: string, path: string, validate: (body: any) => string | null): Promise<CheckResult & { etag?: string }> {
  try {
    const response = await request(path);
    const text = await response.text();
    const body = text ? JSON.parse(text) : null;
    const baseOk = response.ok && body?.ok === true;
    const validationMessage = baseOk ? validate(body) : `Unexpected response: ${text.slice(0, 300)}`;
    return {
      name,
      ok: baseOk && !validationMessage,
      status: response.status,
      etag: response.headers.get('etag') ?? undefined,
      message: validationMessage ?? undefined,
    };
  } catch (error: any) {
    return { name, ok: false, message: error?.message ?? String(error) };
  }
}

async function checkEtag(name: string, path: string, etag?: string): Promise<CheckResult> {
  if (!etag) return { name, ok: false, message: 'ETag header is missing' };
  try {
    const response = await request(path, { 'If-None-Match': etag });
    return {
      name,
      ok: response.status === 304,
      status: response.status,
      message: response.status === 304 ? undefined : `Expected 304, got ${response.status}`,
    };
  } catch (error: any) {
    return { name, ok: false, message: error?.message ?? String(error) };
  }
}

async function main() {
  const results: CheckResult[] = [];
  const health = await checkJson('health', '/health');
  results.push(health);
  results.push(await checkJson('ready', '/ready'));
  const versions = await checkJson('app versions', '/api/v1/app/versions');
  results.push(versions);
  results.push(await checkEtag('app versions etag', '/api/v1/app/versions', versions.etag));
  const bootstrap = await checkJson('app bootstrap', '/api/v1/app/bootstrap?lang=ru');
  results.push(bootstrap);
  results.push(await checkEtag('app bootstrap etag', '/api/v1/app/bootstrap?lang=ru', bootstrap.etag));
  results.push(await checkJsonShape('runtime config shape', '/api/v1/app/runtime-config?lang=ru', (body) => {
    const driven = body.data?.backendDriven;
    if (!driven?.paymentFlow?.invoiceAmountUsesPayableAfterBonus) return 'paymentFlow invoice rule is missing';
    if (!driven?.addressSearch?.fallbackOnlyOnEmptyOrError) return 'addressSearch fallback rule is missing';
    if (!driven?.screenRules?.ordersTabs) return 'screenRules are missing';
    if (!driven?.trainingFlow?.interactiveMode) return 'trainingFlow interactive mode is missing';
    return null;
  }));
  results.push(await checkStatus('api docs', '/api/docs'));
  if (token) {
    results.push(await checkJsonShape('admin settings meta', '/api/v1/admin/settings/meta', (body) => {
      const sections = body.data?.sections;
      if (!Array.isArray(sections)) return 'sections array is missing';
      for (const key of ['paymentFlow', 'orderRules', 'addressSearch', 'trainingFlow', 'screenRules']) {
        if (!sections.some((section: any) => section.key === key)) return `section ${key} is missing`;
      }
      return null;
    }));
    results.push(await checkJsonShape('admin integrations status', '/api/v1/admin/integrations/status', (body) => {
      const data = body.data;
      if (!data?.env || typeof data.env.ok !== 'boolean') return 'env status is missing';
      if (!data?.storage || data.storage.provider !== 'minio') return 'minio storage status is missing';
      if (!data?.payments || typeof data.payments.bccConfigured !== 'boolean') return 'payments status is missing';
      if (!data?.backup || typeof data.backup.ok !== 'boolean') return 'backup status is missing';
      return null;
    }));
    if (testPhone) {
      results.push(await postJson('wapi test otp', '/api/v1/admin/integrations/wapi/test-otp', { phone: testPhone, code: '123456' }));
    } else {
      results.push({ name: 'wapi test otp', ok: true, skipped: true, message: 'SMOKE_TEST_PHONE is not set' });
    }
  } else {
    results.push({ name: 'admin settings meta', ok: true, skipped: true, message: 'SMOKE_ADMIN_TOKEN is not set' });
    results.push({ name: 'admin integrations status', ok: true, skipped: true, message: 'SMOKE_ADMIN_TOKEN is not set' });
    results.push({ name: 'wapi test otp', ok: true, skipped: true, message: 'SMOKE_ADMIN_TOKEN is not set' });
  }

  const failed = results.filter((result) => !result.ok);
  for (const result of results) {
    const status = result.status ? ` (${result.status})` : '';
    const prefix = result.skipped ? 'SKIP' : result.ok ? 'OK' : 'FAIL';
    console.log(`${prefix} ${result.name}${status}${result.message ? `: ${result.message}` : ''}`);
  }
  if (failed.length > 0) process.exit(1);
}

void main();
