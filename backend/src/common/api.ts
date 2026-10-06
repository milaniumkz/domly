import { NextFunction, Request, Response } from 'express';

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export function ok<T>(res: Response, data: T, status = 200): Response {
  return res.status(status).json({ ok: true, data });
}

export function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<unknown>) {
  return (req: Request, res: Response, next: NextFunction) => {
    fn(req, res, next).catch(next);
  };
}

const ruMessages: Record<string, string> = {
  unauthorized: 'Войдите в аккаунт заново.',
  forbidden: 'Недостаточно прав для этого действия.',
  not_found: 'Запись не найдена.',
  invalid_request: 'Проверьте заполненные данные.',
  invalid_json: 'Некорректные данные запроса.',
  duplicate: 'Такая запись уже существует.',
  foreign_key: 'Связанная запись не найдена или уже удалена.',
  database_error: 'Не удалось сохранить данные. Попробуйте позже.',
  file_too_large: 'Файл слишком большой.',
  integration_error: 'Внешний сервис временно недоступен. Попробуйте позже.',
  slot_unavailable: 'Это время уже занято. Выберите другое время.',
  payment_required: 'Сначала подтвердите оплату.',
  cleaner_unavailable: 'Уборщица недоступна на выбранное время.',
  internal_error: 'Произошла ошибка. Попробуйте позже.',
};

const kkMessages: Record<string, string> = {
  unauthorized: 'Аккаунтқа қайта кіріңіз.',
  forbidden: 'Бұл әрекетке құқық жеткіліксіз.',
  not_found: 'Жазба табылмады.',
  invalid_request: 'Толтырылған деректерді тексеріңіз.',
  invalid_json: 'Сұрау деректері дұрыс емес.',
  duplicate: 'Мұндай жазба бұрыннан бар.',
  foreign_key: 'Байланысты жазба табылмады немесе жойылған.',
  database_error: 'Деректерді сақтау мүмкін болмады. Кейінірек қайталап көріңіз.',
  file_too_large: 'Файл тым үлкен.',
  integration_error: 'Сыртқы сервис уақытша қолжетімсіз. Кейінірек қайталап көріңіз.',
  slot_unavailable: 'Бұл уақыт бос емес. Басқа уақыт таңдаңыз.',
  payment_required: 'Алдымен төлемді растаңыз.',
  cleaner_unavailable: 'Таңдалған уақытта орындаушы қолжетімсіз.',
  package_not_found: 'Белсенді пакет табылмады. Пакетті таңдаңыз немесе төлемді растаңыз.',
  address_not_found: 'Мекенжай табылмады. Профиль деректерін тексеріңіз.',
  order_not_found: 'Тапсырыс табылмады немесе өзгертілген.',
  duplicate_date: 'Әртүрлі тазалау күндерін таңдаңыз.',
  invalid_schedule_count: 'Пакетке сәйкес күндер санын таңдаңыз.',
  cleaner_not_found: 'Орындаушы табылмады немесе қолжетімсіз.',
  draft_not_found: 'Жоба табылмады. Пакетті қайта жинаңыз.',
  internal_error: 'Қате пайда болды. Кейінірек қайталап көріңіз.',
};

const legacyMessageMap: Array<[RegExp, { status: number; code: string; message: string }]> = [
  [/active package not found|user package not found|package plan not found/i, {
    status: 404,
    code: 'package_not_found',
    message: 'Активный пакет не найден. Выберите или оплатите пакет заново.',
  }],
  [/apartment not found/i, {
    status: 404,
    code: 'address_not_found',
    message: 'Адрес не найден. Проверьте данные профиля.',
  }],
  [/cleaning not found|order .* not found/i, {
    status: 404,
    code: 'order_not_found',
    message: 'Заказ не найден или уже изменён.',
  }],
  [/slot unavailable|requested new slot is unavailable/i, {
    status: 409,
    code: 'slot_unavailable',
    message: ruMessages.slot_unavailable,
  }],
  [/duplicate date is not allowed/i, {
    status: 400,
    code: 'duplicate_date',
    message: 'Выберите разные даты уборки.',
  }],
  [/expected exactly \d+ selections/i, {
    status: 400,
    code: 'invalid_schedule_count',
    message: 'Выберите нужное количество дат для пакета.',
  }],
  [/cleaner not found/i, {
    status: 404,
    code: 'cleaner_not_found',
    message: 'Уборщица не найдена или недоступна.',
  }],
  [/no cleaner selected/i, {
    status: 409,
    code: 'cleaner_unavailable',
    message: 'Нет доступной уборщицы на это время. Выберите другое время или назначьте уборщицу вручную.',
  }],
  [/draft not found|draft not created/i, {
    status: 404,
    code: 'draft_not_found',
    message: 'Черновик не найден. Соберите пакет заново.',
  }],
];

export function errorHandler(error: Error, req: Request, res: Response, _next: NextFunction): Response {
  const lang = requestLanguage(req);
  if (error instanceof ApiError) {
    return res.status(error.status).json(errorPayload(error.code, error.message, lang));
  }
  const friendly = knownError(error);
  return res.status(friendly.status).json(errorPayload(friendly.code, friendly.message, lang));
}

export function friendlyError(code: string, fallback: string): ApiError {
  return new ApiError(code === 'not_found' ? 404 : 400, code, ruMessages[code] ?? fallback);
}

function knownError(error: any): { status: number; code: string; message: string } {
  if (error?.type === 'entity.parse.failed' || error instanceof SyntaxError) {
    return { status: 400, code: 'invalid_json', message: ruMessages.invalid_json };
  }
  if (error?.code === 'LIMIT_FILE_SIZE') {
    return { status: 400, code: 'file_too_large', message: ruMessages.file_too_large };
  }
  if (error?.name === 'TokenExpiredError' || error?.name === 'JsonWebTokenError') {
    return { status: 401, code: 'unauthorized', message: ruMessages.unauthorized };
  }
  if (error?.code === '23505') {
    return { status: 409, code: 'duplicate', message: ruMessages.duplicate };
  }
  if (error?.code === '23503') {
    return { status: 400, code: 'foreign_key', message: ruMessages.foreign_key };
  }
  if (typeof error?.code === 'string' && error.code.startsWith('23')) {
    return { status: 400, code: 'database_error', message: ruMessages.database_error };
  }
  if (['FetchError', 'TimeoutError'].includes(error?.name) || String(error?.message ?? '').includes('fetch failed')) {
    return { status: 503, code: 'integration_error', message: ruMessages.integration_error };
  }
  const message = String(error?.message ?? '');
  const legacy = legacyMessageMap.find(([pattern]) => pattern.test(message));
  if (legacy) return legacy[1];
  return { status: 500, code: 'internal_error', message: ruMessages.internal_error };
}

function requestLanguage(req: Request): 'ru' | 'kk' {
  const raw = String(req.query?.lang ?? req.headers['x-app-language'] ?? req.headers['accept-language'] ?? '').toLowerCase();
  return raw.includes('kk') || raw.includes('kz') || raw.includes('қаз') ? 'kk' : 'ru';
}

function errorPayload(code: string, fallbackRu: string, lang: 'ru' | 'kk') {
  const messageRu = ruMessages[code] ?? fallbackRu;
  const messageKk = kkMessages[code] ?? messageRu;
  return {
    ok: false,
    code,
    message: lang === 'kk' ? messageKk : messageRu,
    messageRu,
    messageKk,
  };
}
