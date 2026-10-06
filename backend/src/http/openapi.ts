export const openApiSpec = {
  openapi: '3.0.0',
  info: {
    title: 'DOMLY Backend API',
    version: '1.0.0',
    description: 'REST API для backend без Firebase. Firebase используется только для FCM push.',
  },
  servers: [{ url: '/api/v1' }],
  externalDocs: {
    description: 'Root smoke endpoints: GET /health, GET /ready',
  },
  components: {
    securitySchemes: {
      bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
    },
    schemas: {
      Success: {
        type: 'object',
        properties: { ok: { type: 'boolean', example: true }, data: { type: 'object' } },
      },
      Error: {
        type: 'object',
        properties: {
          ok: { type: 'boolean', example: false },
          code: { type: 'string', example: 'not_found' },
          message: { type: 'string', example: 'Запись не найдена.' },
          messageRu: { type: 'string', example: 'Запись не найдена.' },
          messageKk: { type: 'string', example: 'Жазба табылмады.' },
        },
      },
    },
  },
  paths: {
    '/auth/otp/request': {
      post: {
        summary: 'Отправить OTP через WAPI',
        requestBody: jsonBody({ phone: '+77052597368' }),
        responses: okError(),
      },
    },
    '/auth/otp/verify': {
      post: {
        summary: 'Проверить OTP и выдать JWT',
        requestBody: jsonBody({ phone: '+77052597368', code: '123456', role: 'customer' }),
        responses: okError(),
      },
    },
    '/auth/password/login': {
      post: {
        summary: 'Вход админа/уборщицы по паролю',
        requestBody: jsonBody({ phone: '+77781110170', password: 'secret' }),
        responses: okError(),
      },
    },
    '/auth/refresh': {
      post: {
        summary: 'Обновить access/refresh токены',
        requestBody: jsonBody({ refreshToken: '...' }),
        responses: okError(),
      },
    },
    '/auth/logout': {
      post: {
        ...secured('Выйти из аккаунта, отозвать refresh-сессию и отключить FCM token'),
        requestBody: jsonBody({ refreshToken: '...', deviceToken: 'fcm-token', allDevices: false }),
      },
    },
    '/me': {
      get: secured('Текущий пользователь'),
      patch: {
        ...secured('Обновить профиль пользователя'),
        requestBody: jsonBody({ fullName: 'Иван Иванов', email: 'client@example.kz', language: 'ru' }),
      },
    },
    '/me/settings': {
      get: secured('Настройки текущего пользователя'),
      patch: {
        ...secured('Обновить настройки пользователя: язык, обучение, уведомления'),
        requestBody: jsonBody({ language: 'kk', trainingCompleted: true, notificationsEnabled: true }),
      },
    },
    '/me/device-tokens': {
      post: {
        ...secured('Сохранить FCM token устройства'),
        requestBody: jsonBody({ platform: 'android', token: 'fcm-token' }),
      },
    },
    '/me/device-tokens/{token}': {
      delete: secured('Отключить FCM token устройства'),
    },
    '/files': {
      post: {
        ...secured('Загрузить файл в MinIO'),
        requestBody: multipartBody({ file: 'binary', folder: 'documents' }),
      },
    },
    '/users': {
      get: {
        ...secured('Админ: список пользователей с фильтрами'),
        parameters: [query('role', 'customer'), query('search', '7705')],
      },
    },
    '/users/{id}': {
      get: { ...secured('Админ: карточка пользователя'), parameters: [path('id')] },
    },
    '/addresses': {
      get: secured('Адреса текущего пользователя'),
      post: {
        ...secured('Добавить адрес пользователя'),
        requestBody: jsonBody({ city: 'Астана', street: 'Кабанбай батыра', house: '29/2', apartment: '12', area: 70 }),
      },
    },
    '/addresses/{id}': {
      patch: {
        ...secured('Обновить адрес пользователя'),
        parameters: [path('id')],
        requestBody: jsonBody({ area: 75, apartment: '12' }),
      },
    },
    '/bonus/history': { get: secured('История бонусов клиента: начисления, списания, возвраты') },
    '/bonus/transactions': {
      post: {
        ...secured('Создать бонусную транзакцию backend-правилами'),
        requestBody: jsonBody({ userId: 'uuid', amount: 2000, type: 'credit', reasonRu: 'Бонус' }),
      },
    },
    '/packages/my': { get: secured('Активные и купленные пакеты клиента') },
    '/packages/my/{id}': {
      patch: {
        ...secured('Обновить клиентский пакет: площадь, статус, перерасчёт'),
        parameters: [path('id')],
        requestBody: jsonBody({ area: 80, status: 'active' }),
      },
    },
    '/cleaner/profile': {
      get: secured('Профиль уборщицы'),
      patch: {
        ...secured('Обновить профиль, районы и настройки звука уборщицы'),
        requestBody: jsonBody({ fullName: 'Анна', soundVolume: 80, alarmSound: 'system' }),
      },
    },
    '/cleaner/documents': {
      post: {
        ...secured('Загрузить документ уборщицы'),
        requestBody: multipartBody({ file: 'binary', type: 'identity' }),
      },
    },
    '/cleaner/verification': {
      post: {
        ...secured('Отправить документы уборщицы на верификацию по URL уже загруженных файлов'),
        requestBody: jsonBody({ idCardFront: 'https://files.example/id-front.jpg', idCardBack: 'https://files.example/id-back.jpg' }),
      },
    },
    '/app/config': {
      get: {
        summary: 'Backend-driven конфигурация приложения, каталог, переводы и правила',
        parameters: [{ name: 'lang', in: 'query', schema: { type: 'string', enum: ['ru', 'kk'] } }],
        responses: okError(),
      },
    },
    '/app/bootstrap': {
      get: {
        summary: 'Полный bootstrap для тонкого клиента: runtime-правила, переводы, каталог, баннеры, акции и страницы с ETag',
        parameters: [{ name: 'lang', in: 'query', schema: { type: 'string', enum: ['ru', 'kk'] } }],
        responses: {
          200: { description: 'Bootstrap payload' },
          304: { description: 'Bootstrap не изменился' },
          ...okError(),
        },
      },
    },
    '/app/versions': {
      get: {
        summary: 'Лёгкая проверка версий settings/translations/catalog/content с ETag',
        responses: {
          200: { description: 'Versions payload' },
          304: { description: 'Версии не изменились' },
          ...okError(),
        },
      },
    },
    '/app/runtime-config': {
      get: {
        summary: 'Лёгкий backend-driven runtime-конфиг UI/оплаты/записи/поиска/переводов с ETag для обновлений без релиза приложения',
        parameters: [{ name: 'lang', in: 'query', schema: { type: 'string', enum: ['ru', 'kk'] } }],
        responses: {
          200: { description: 'Runtime config' },
          304: { description: 'Конфиг не изменился' },
          ...okError(),
        },
      },
    },
    '/realtime': {
      get: {
        summary: 'SSE события пользователя. Для Web EventSource можно передать access_token в query.',
        parameters: [query('access_token', 'jwt-access-token')],
        responses: okError(),
      },
    },
    '/geo/address-suggestions': {
      get: {
        summary: 'Подсказки адресов: подключённые дома, затем OSM/Yandex fallback',
        parameters: [
          query('search', 'Сдык 39'),
          query('city', 'Астана'),
          query('lat', '51.128'),
          query('lng', '71.43'),
          query('radiusKm', '50'),
          query('limit', '10'),
        ],
        responses: okError(),
      },
    },
    '/geo/connected-houses': {
      get: {
        summary: 'Поиск подключённых домов',
        parameters: [query('city', 'Астана'), query('search', 'Кабанбай')],
        responses: okError(),
      },
    },
    '/geo/service-address-requests': {
      post: {
        ...secured('Создать заявку клиента на подключение адреса/дома'),
        requestBody: jsonBody({ residentialComplex: 'ЖК Example', address: 'Кабанбай батыра 29', city: 'Астана', area: 70 }),
      },
    },
    '/order-requests': {
      post: {
        ...secured('Создать заявку на заказ/подключение из тонкого клиента'),
        requestBody: jsonBody({ type: 'quality_check', addressId: 'uuid', requestedDate: '2026-09-25' }),
      },
    },
    '/catalog/packages': { get: { summary: 'Активные пакеты', responses: okError() } },
    '/catalog/addons': { get: { summary: 'Активные доп. услуги', responses: okError() } },
    '/catalog/banners': {
      get: { summary: 'Активные баннеры по placement', parameters: [query('placement', 'home_top')], responses: okError() },
    },
    '/translations': { get: { summary: 'Публичный словарь переводов RU/KK', responses: okError() } },
    '/packages/purchase': {
      post: {
        ...secured('Купить пакет'),
        requestBody: jsonBody({ packageId: 'uuid', addressId: 'uuid', provider: 'kaspi', invoicePhone: '77052597368' }),
      },
    },
    '/orders': {
      get: secured('Список заказов текущего пользователя'),
      post: {
        ...secured('Создать уборку из активного пакета'),
        requestBody: jsonBody({ customerPackageId: 'uuid', date: '2026-09-25', startTime: '10:00', addons: [{ addonId: 'uuid', quantity: 1 }] }),
      },
    },
    '/cleaner/orders': { get: secured('Уборщица: подтверждённые и предложенные заказы') },
    '/orders/{id}/details': { get: { ...secured('Детали заказа для клиента, уборщицы или админа'), parameters: [path('id')] } },
    '/orders/{id}/pay': {
      post: {
        ...secured('Оплатить заказ Kaspi/BCC/бонусами'),
        parameters: [path('id')],
        requestBody: jsonBody({ provider: 'kaspi', useBonus: true, requestedBonus: 5000, invoicePhone: '77052597368' }),
      },
    },
    '/orders/{id}/cancel': { post: { ...secured('Отменить заказ с возвратом оплат/бонусов'), parameters: [path('id')] } },
    '/orders/{id}/confirm-start': {
      post: {
        ...secured('Клиент: подтвердить или отклонить старт уборки'),
        parameters: [path('id')],
        requestBody: jsonBody({ confirmed: true }),
      },
    },
    '/orders/{id}/offer-next-cleaner': { post: { ...secured('Админ: передать заказ следующей доступной уборщице'), parameters: [path('id')] } },
    '/orders/{id}/offers/accept': { post: { ...secured('Уборщица: принять предложение заказа по orderId'), parameters: [path('id')] } },
    '/orders/{id}/offers/decline': { post: { ...secured('Уборщица: отклонить предложение заказа по orderId'), parameters: [path('id')], requestBody: jsonBody({ reason: 'busy' }) } },
    '/orders/{id}/checklist': {
      get: { ...secured('Чек-лист заказа с базовыми пунктами и выбранными допами'), parameters: [path('id')] },
      post: {
        ...secured('Сохранить чек-лист заказа'),
        parameters: [path('id')],
        requestBody: jsonBody({ items: [{ title: 'Протереть пыль', checked: true }] }),
      },
    },
    '/orders/{id}/reschedule': {
      post: {
        ...secured('Предложить или подтвердить перенос времени заказа'),
        parameters: [path('id')],
        requestBody: jsonBody({ date: '2026-09-25', startTime: '12:00' }),
      },
    },
    '/orders/{id}/notify': {
      post: {
        ...secured('Отправить сервисное уведомление по заказу'),
        parameters: [path('id')],
        requestBody: jsonBody({ type: 'order_updated', bodyRu: 'Детали уборки обновлены' }),
      },
    },
    '/orders/{id}/addon-requests': {
      post: {
        ...secured('Уборщица/клиент: предложить или заказать доп. услуги по активной уборке'),
        parameters: [path('id')],
        requestBody: jsonBody({ addons: [{ addonId: 'uuid', quantity: 1 }] }),
      },
    },
    '/orders/{id}/addon-requests/approve': { post: { ...secured('Клиент/админ: подтвердить заявку на допы'), parameters: [path('id')] } },
    '/orders/{id}/addon-requests/reject': { post: { ...secured('Клиент/админ: отклонить заявку на допы'), parameters: [path('id')] } },
    '/addon-requests': { get: secured('Список заявок на доп. услуги') },
    '/orders/{id}/checklist/items/{itemId}': {
      patch: {
        ...secured('Уборщица/админ: отметить пункт чек-листа'),
        parameters: [path('id'), path('itemId')],
        requestBody: jsonBody({ checked: true }),
      },
    },
    '/orders/{id}/photo-report': {
      get: { ...secured('Фотоотчёт по заказу'), parameters: [path('id')] },
      post: {
        ...secured('Уборщица/админ: отправить фотоотчёт по заказу'),
        parameters: [path('id')],
        requestBody: jsonBody({ photoUrls: ['https://files.domly.kz/report-1.jpg', 'https://files.domly.kz/report-2.jpg', 'https://files.domly.kz/report-3.jpg'] }),
      },
    },
    '/orders/{id}/status': {
      post: {
        ...secured('Уборщица/админ: сменить статус заказа'),
        parameters: [path('id')],
        requestBody: jsonBody({ status: 'in_progress', comment: 'Начала уборку' }),
      },
    },
    '/preorders': {
      get: secured('Список предварительных записей'),
      post: {
        ...secured('Создать предварительную запись'),
        requestBody: jsonBody({ addressId: 'uuid', packageId: 'uuid', desiredDate: '2026-09-25', desiredTime: '10:00', area: 70 }),
      },
    },
    '/preorders/{id}/pay': {
      post: {
        ...secured('Оплатить предварительную запись и активировать пакет после подтверждения платежа'),
        parameters: [path('id')],
        requestBody: jsonBody({ provider: 'kaspi', invoicePhone: '77052597368' }),
      },
    },
    '/preorders/{id}/cancel': { post: { ...secured('Отменить предварительную запись клиентом'), parameters: [path('id')] } },
    '/scheduling/available-slots': {
      get: {
        ...secured('Свободные слоты только при наличии доступной уборщицы'),
        parameters: [query('date', '2026-09-25'), query('addressId', 'uuid'), query('addons', 'uuid,uuid')],
      },
    },
    '/cleaner/offers': { get: secured('Активные предложения уборщицы') },
    '/cleaner/offers/{id}/accept': { post: { ...secured('Принять предложение'), parameters: [path('id')] } },
    '/cleaner/offers/{id}/decline': { post: { ...secured('Отклонить предложение'), parameters: [path('id')] } },
    '/payments/my': { get: secured('Клиент: история своих платежей') },
    '/payments': { get: secured('Админ: платежи с данными клиента/заказа') },
    '/payouts': {
      get: secured('Уборщица: история заявок на выплаты'),
      post: { ...secured('Уборщица: создать заявку на выплату'), requestBody: jsonBody({ amount: 15000 }) },
    },
    '/admin/payouts': {
      post: { ...secured('Админ: создать выплату вручную'), requestBody: jsonBody({ cleanerId: 'uuid', amount: 15000 }) },
    },
    '/admin/payouts/{id}': {
      patch: {
        ...secured('Админ: изменить статус выплаты'),
        parameters: [path('id')],
        requestBody: jsonBody({ status: 'approved' }),
      },
    },
    '/payments/{id}/confirm': { post: { ...secured('Админ: подтвердить оплату'), parameters: [path('id')] } },
    '/payments/{id}/reject': { post: { ...secured('Админ: отклонить оплату'), parameters: [path('id')] } },
    '/payments/{id}/kaspi-invoice': {
      post: {
        ...secured('Клиент: отправить номер KASPI.KZ и запросить счёт по созданному платежу'),
        parameters: [path('id')],
        requestBody: jsonBody({ invoicePhone: '+77052597368' }),
      },
    },
    '/payments/{id}/bcc-session': {
      post: {
        ...secured('Клиент: открыть онлайн-оплату BCC/ePay по созданному платежу'),
        parameters: [path('id')],
      },
    },
    '/payments/{id}/status-check': { post: { ...secured('Админ: проверить статус BCC/ePay'), parameters: [path('id')] } },
    '/payments/{id}/refund': { post: { ...secured('Админ: вернуть оплату'), parameters: [path('id')] } },
    '/payments/bcc/connection-check': { post: secured('Админ: TRTYPE=800 проверка соединения BCC') },
    '/payments/kaspi/webhook': { post: { summary: 'Webhook Kaspi', requestBody: jsonBody({ status: 'paid', invoiceId: '...' }), responses: okError() } },
    '/payments/moon-ai/kaspi-status': {
      post: {
        summary: 'Webhook Moon AI: статус выставленного счёта Kaspi',
        description: 'Moon AI отправляет статус, сумму, телефон и дату/время по счёту Kaspi. Защита: Authorization: Bearer <MOON_AI_WEBHOOK_TOKEN> или X-MoonAI-Token.',
        requestBody: jsonBody({
          paymentId: '12345678-1234-1234-1234-123456789012',
          invoiceId: 'moon-kaspi-000001',
          status: 'paid',
          amount: 11500,
          phone: '+77052597368',
          dateTime: '2026-09-29T12:30:00+05:00',
        }),
        responses: okError(),
      },
    },
    '/payments/bcc/webhook': { post: { summary: 'Webhook BCC/ePay', requestBody: jsonBody({ ORDER: '000123', RESPONSE: '00' }), responses: okError() } },
    '/notifications': {
      get: secured('Уведомления пользователя'),
      post: { ...secured('Создать уведомление пользователю/роли'), requestBody: jsonBody({ userId: 'uuid', titleRu: 'Уведомление', bodyRu: 'Текст' }) },
    },
    '/notifications/unread-count': { get: secured('Количество непрочитанных уведомлений') },
    '/notifications/{id}/read': { post: { ...secured('Отметить уведомление прочитанным'), parameters: [path('id')] } },
    '/notifications/read-all': { post: secured('Отметить все уведомления прочитанными') },
    '/admin/notifications': {
      get: secured('Админ: список уведомлений админки с персональным read/unread для текущего админа'),
      post: { ...secured('Админ: отправить уведомление пользователю или роли'), requestBody: jsonBody({ role: 'admin', titleRu: 'Платёж', bodyRu: 'Новая заявка на оплату', targetType: 'payments', targetId: 'uuid' }) },
    },
    '/admin/integrations/wapi/test-otp': {
      post: { ...secured('Админ: отправить тестовый OTP через WAPI'), requestBody: jsonBody({ phone: '+77052597368', code: '123456' }) },
    },
    '/chats': {
      get: secured('Список чатов пользователя или все чаты для админа'),
      post: {
        ...secured('Создать или получить чат заказа/жалобы'),
        requestBody: jsonBody({ type: 'order', orderId: 'uuid', complaintId: null, participantIds: ['uuid'] }),
      },
    },
    '/chats/{id}/messages': {
      get: { ...secured('Сообщения чата'), parameters: [path('id')] },
      post: {
        ...secured('Отправить сообщение в чат'),
        parameters: [path('id')],
        requestBody: jsonBody({ messageRu: 'Здравствуйте', messageKk: 'Сәлеметсіз бе' }),
      },
    },
    '/chats/{id}/read': {
      post: { ...secured('Отметить чат прочитанным'), parameters: [path('id')] },
    },
    '/complaints': {
      get: secured('Список жалоб пользователя или админа'),
      post: {
        ...secured('Создать жалобу'),
        requestBody: jsonBody({ orderId: 'uuid', text: 'Описание проблемы', photoUrls: [] }),
      },
    },
    '/reviews': {
      get: secured('Список отзывов пользователя или админа'),
      post: {
        ...secured('Оставить отзыв и пересчитать рейтинг'),
        requestBody: jsonBody({ orderId: 'uuid', cleanerId: 'uuid', rating: 5, text: 'Хорошо' }),
      },
    },
    '/quality-checks': {
      post: {
        ...secured('Отправить площадь и документ на проверку'),
        requestBody: multipartBody({ document: 'binary', addressId: 'uuid', requestedArea: '75' }),
      },
    },
    '/quality-checks/from-file': {
      post: {
        ...secured('Создать проверку площади по уже загруженному файлу'),
        requestBody: jsonBody({ addressId: 'uuid', requestedArea: 75, fileUrl: 'https://files.domly.kz/plan.jpg' }),
      },
    },
    '/admin/users/{id}': {
      patch: {
        ...secured('Админ: обновить профиль, статус, язык или рейтинг пользователя'),
        parameters: [path('id')],
        requestBody: jsonBody({ fullName: 'Иван Иванов', status: 'approved', rating: 5, isPhoneVerified: true }),
      },
    },
    '/admin/users/{id}/confirm-area': {
      post: {
        ...secured('Админ: подтвердить площадь пользователя и создать перерасчёт'),
        parameters: [path('id')],
        requestBody: jsonBody({ area: 80, createPayment: true }),
      },
    },
    '/admin/users/{id}/bonus-adjustment': {
      post: {
        ...secured('Админ: ручная корректировка бонусов пользователя'),
        parameters: [path('id')],
        requestBody: jsonBody({ amount: 2000, reasonRu: 'Бонус за подтверждение площади', reasonKk: 'Ауданды растау бонусы' }),
      },
    },
    '/admin/cleaners': {
      post: {
        ...secured('Админ: создать уборщицу'),
        requestBody: jsonBody({ phone: '+77001112233', fullName: 'Айгуль', city: 'Астана', monthlyAreaLimit: 220, dailyWorkLimitMinutes: 540 }),
      },
    },
    '/admin/cleaners/{id}': {
      patch: {
        ...secured('Админ: обновить профиль уборщицы, лимиты и звук'),
        parameters: [path('id')],
        requestBody: jsonBody({ fullName: 'Айгуль', status: 'approved', monthlyAreaLimit: 220, soundEnabled: true, soundVolume: 80, soundKey: 'system' }),
      },
      delete: {
        ...secured('Админ: деактивировать уборщицу без удаления истории'),
        parameters: [path('id')],
      },
    },
    '/admin/settings': {
      get: secured('Админ: список backend-настроек'),
      post: {
        ...secured('Админ: сохранить одну или несколько backend-настроек'),
        requestBody: jsonBody({
          key: 'allowCustomTime',
          value: false,
          settings: {
            allowCustomTime: false,
            minBookingDate: '2026-09-02',
            enabledLanguages: ['ru', 'kk'],
            translationMode: { liveSwitch: true, adminEditable: true, fallbackLanguage: 'ru', dynamicDataLocales: true },
            addressSearch: { primaryProvider: 'osm', fallbackProvider: 'yandex', fallbackOnlyOnEmptyOrError: true, radiusKm: 50, limit: 10 },
            assignmentRules: { requireAvailableCleanerForSlot: true, preventTimeOverlap: true, reassignOnCleanerConflict: true },
            orderRules: { cancelRefundsBonuses: true, cancelRemovesPaidAddons: true, hideCleanerEarningsFromCleanerApp: true },
            adminNotificationRules: { enabled: true, events: ['new_user', 'new_order', 'new_payment'], deepLinks: true },
          },
        }),
      },
    },
    '/admin/settings/meta': {
      get: secured('Админ: схема backend-driven настроек для построения формы без обновления админки'),
    },
    '/admin/integrations/status': { get: secured('Админ: smoke-status WAPI, FCM, MinIO, backup, платежей и геопоиска') },
    '/admin/translations': {
      get: secured('Админ: словарь переводов с фильтрами'),
      post: { ...secured('Админ: сохранить перевод'), requestBody: jsonBody({ key: 'home.title', ru: 'Главная', kk: 'Басты бет', namespace: 'app' }) },
    },
    '/admin/translations/stats': { get: secured('Админ: статистика переводов RU/KK') },
    '/admin/translations/bulk': {
      post: {
        ...secured('Админ: массово сохранить переводы'),
        requestBody: jsonBody({ items: [{ key: 'home.title', ru: 'Главная', kk: 'Басты бет', namespace: 'app' }] }),
      },
    },
    '/admin/translations/sync-defaults': {
      post: {
        ...secured('Админ: добавить дефолтные строки перевода без обновления приложения'),
        requestBody: jsonBody({ overwrite: false }),
      },
    },
    '/admin/{section}': {
      get: {
        ...secured('Админ: общий список раздела с фильтрами'),
        parameters: [path('section'), query('status', 'paid'), query('dateFrom', '2026-09-01'), query('dateTo', '2026-09-30'), query('search', 'Дмитрий')],
      },
    },
    '/admin/audit': {
      get: {
        ...secured('Админ: аудит действий с данными актора'),
        parameters: [query('dateFrom', '2026-09-01'), query('dateTo', '2026-09-30'), query('search', 'payment.confirmed')],
      },
      post: {
        ...secured('Админ: записать аудит действия'),
        requestBody: jsonBody({ action: 'payment.confirmed', entityType: 'payment', entityId: 'uuid', metadata: {} }),
      },
    },
    '/admin/orders/{id}/details': { get: { ...secured('Админ: детали заказа, клиент, уборщица, допы, платежи'), parameters: [path('id')] } },
    '/admin/orders/{id}': {
      patch: {
        ...secured('Админ: изменить статус заказа или назначение'),
        parameters: [path('id')],
        requestBody: jsonBody({ status: 'assigned', cleanerId: 'uuid' }),
      },
    },
    '/admin/orders/{id}/assign-cleaner': {
      post: {
        ...secured('Админ: назначить свободную уборщицу на заказ'),
        parameters: [path('id')],
        requestBody: jsonBody({ cleanerId: 'uuid' }),
      },
    },
    '/admin/payments/{id}/details': { get: { ...secured('Админ: детали платежа, события webhook/status/refund'), parameters: [path('id')] } },
    '/admin/cleaners/{id}/details': { get: { ...secured('Админ: карточка уборщицы, районы, заказы, выплаты'), parameters: [path('id')] } },
    '/admin/cleaners/{id}/verification': {
      patch: {
        ...secured('Админ: подтвердить/отклонить уборщицу'),
        parameters: [path('id')],
        requestBody: jsonBody({ status: 'approved', comment: 'OK' }),
      },
    },
    '/admin/cleaners/{id}/zones': {
      put: {
        ...secured('Админ: заменить зоны уборщицы'),
        parameters: [path('id')],
        requestBody: jsonBody({ zoneIds: ['uuid'] }),
      },
    },
    '/admin/quality-checks/{id}/details': { get: { ...secured('Админ: детали проверки площади с клиентом, адресом, заказами и платежами'), parameters: [path('id')] } },
    '/admin/quality-checks/{id}': {
      patch: {
        ...secured('Админ: обновить проверку площади'),
        parameters: [path('id')],
        requestBody: jsonBody({ status: 'reviewed', approvedArea: 80 }),
      },
    },
    '/admin/quality-checks/{id}/approve': {
      post: {
        ...secured('Админ: подтвердить площадь и создать перерасчёт при необходимости'),
        parameters: [path('id')],
        requestBody: jsonBody({ approvedArea: 80, recalculationAmount: 15200 }),
      },
    },
    '/admin/complaints/{id}/details': { get: { ...secured('Админ: детали жалобы с клиентом, уборщицей, заказом и чатом'), parameters: [path('id')] } },
    '/admin/complaints/{id}': {
      patch: {
        ...secured('Админ: изменить статус жалобы'),
        parameters: [path('id')],
        requestBody: jsonBody({ status: 'closed', resolution: 'Решено' }),
      },
    },
    '/admin/reviews/{id}/details': { get: { ...secured('Админ: детали отзыва с клиентом, уборщицей и историей отзывов'), parameters: [path('id')] } },
    '/admin/checklist-reports/{id}/details': { get: { ...secured('Админ: детали чек-листа с заказом, клиентом, уборщицей и пунктами'), parameters: [path('id')] } },
    '/admin/payouts/{id}/details': { get: { ...secured('Админ: детали выплаты с карточкой уборщицы и историей'), parameters: [path('id')] } },
    '/admin/preorders/start': { post: { ...secured('Админ: объявить старт и уведомить предзаписи'), requestBody: jsonBody({ startDate: '2026-09-25' }) } },
    '/admin/preorders/{id}': { patch: { ...secured('Админ: изменить статус предзаписи'), parameters: [path('id')], requestBody: jsonBody({ status: 'worked', adminComment: 'Клиент обработан' }) } },
    '/admin/catalog/packages': {
      post: { ...secured('Админ: создать пакет'), requestBody: jsonBody({ nameRu: '4 раза в месяц', cleaningCount: 4, basePrice: 36000 }) },
    },
    '/admin/catalog/packages/{id}': {
      patch: { ...secured('Админ: обновить пакет'), parameters: [path('id')], requestBody: jsonBody({ active: true, nameKk: 'Айына 4 рет' }) },
    },
    '/admin/catalog/addon-groups': {
      post: { ...secured('Админ: создать группу допов'), requestBody: jsonBody({ titleRu: 'Санузлы', titleKk: 'Сантораптар', sortOrder: 10 }) },
    },
    '/admin/catalog/addon-groups/{id}': {
      patch: { ...secured('Админ: обновить группу допов'), parameters: [path('id')], requestBody: jsonBody({ titleKk: 'Сантораптар', active: true }) },
    },
    '/admin/catalog/addons': {
      post: { ...secured('Админ: создать доп. услугу'), requestBody: jsonBody({ groupId: 'uuid', titleRu: 'Мытье окон', price: 3000, durationMinutes: 30 }) },
    },
    '/admin/catalog/addons/{id}': {
      patch: { ...secured('Админ: обновить доп. услугу'), parameters: [path('id')], requestBody: jsonBody({ price: 3500, hintRu: 'Описание' }) },
    },
    '/admin/service-zones': {
      post: { ...secured('Админ: создать район/зону'), requestBody: jsonBody({ city: 'Астана', nameRu: 'Астана', polygon: null }) },
    },
    '/admin/service-zones/{id}': {
      patch: { ...secured('Админ: обновить район/зону'), parameters: [path('id')], requestBody: jsonBody({ active: true }) },
    },
    '/admin/connected-houses': {
      post: { ...secured('Админ: добавить подключённый дом'), requestBody: jsonBody({ city: 'Астана', streetRu: 'Сыдық', houseNumber: '39' }) },
    },
    '/admin/connected-houses/{id}': {
      patch: { ...secured('Админ: обновить подключённый дом'), parameters: [path('id')], requestBody: jsonBody({ streetKk: 'Сыдық' }) },
    },
    '/admin/checklist-templates': {
      post: { ...secured('Админ: создать шаблон чек-листа'), requestBody: jsonBody({ packageId: 'uuid', titleRu: 'Основная уборка', titleKk: 'Негізгі жинау' }) },
    },
    '/admin/checklist-templates/{id}': {
      patch: { ...secured('Админ: обновить шаблон чек-листа'), parameters: [path('id')], requestBody: jsonBody({ active: true }) },
    },
    '/admin/checklist-templates/{id}/items': {
      post: { ...secured('Админ: добавить пункт чек-листа'), parameters: [path('id')], requestBody: jsonBody({ titleRu: 'Протереть пыль', titleKk: 'Шаңды сүрту', sortOrder: 10 }) },
    },
    '/admin/checklist-template-items/{id}': {
      patch: { ...secured('Админ: обновить пункт чек-листа'), parameters: [path('id')], requestBody: jsonBody({ checkedByDefault: false, active: true }) },
    },
    '/admin/banners': {
      post: { ...secured('Админ: создать баннер'), requestBody: jsonBody({ placement: 'home_top', imageUrl: 'https://...', titleRu: 'Акция' }) },
    },
    '/admin/banners/{id}': {
      patch: { ...secured('Админ: обновить баннер'), parameters: [path('id')], requestBody: jsonBody({ descriptionRu: 'Описание' }) },
    },
    '/admin/promotions': {
      post: { ...secured('Админ: создать акцию'), requestBody: jsonBody({ titleRu: 'Кэшбэк', rewardType: 'percent', rewardValue: 50 }) },
    },
    '/admin/promotions/{id}': {
      patch: { ...secured('Админ: обновить акцию'), parameters: [path('id')], requestBody: jsonBody({ oncePerCustomer: true }) },
    },
    '/admin/content-pages': {
      post: { ...secured('Админ: создать страницу политики/оферты'), requestBody: jsonBody({ slug: 'privacy', titleRu: 'Политика', bodyRu: '...' }) },
    },
    '/admin/content-pages/{slug}': {
      patch: { ...secured('Админ: обновить страницу политики/оферты'), parameters: [path('slug')], requestBody: jsonBody({ bodyKk: '...' }) },
    },
    '/admin/{section}/{id}/active': {
      patch: {
        ...secured('Админ: включить/отключить справочник без удаления'),
        parameters: [path('section'), path('id')],
        requestBody: jsonBody({ active: false }),
      },
    },
    '/content-pages': { get: { summary: 'Публичный список инфо-страниц', responses: okError() } },
    '/content-pages/{slug}': { get: { summary: 'Публичная оферта/политика/инфо-страница', parameters: [path('slug')], responses: okError() } },
    '/training/video-views': {
      get: { ...secured('Мои просмотренные обучающие видео') },
    },
    '/training/videos/{id}/viewed': {
      post: {
        ...secured('Отметить обучающее видео просмотренным'),
        parameters: [path('id')],
        requestBody: jsonBody({ audienceType: 'customer', completed: true, lastProgressSeconds: 120 }),
      },
    },
  },
};

function secured(summary: string) {
  return { summary, security: [{ bearerAuth: [] }], responses: okError() };
}

function okError() {
  return {
    200: { description: 'OK', content: { 'application/json': { schema: { $ref: '#/components/schemas/Success' } } } },
    400: { description: 'Ошибка запроса', content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } } },
    401: { description: 'Нужна авторизация', content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } } },
  };
}

function jsonBody(example: unknown) {
  return {
    required: true,
    content: { 'application/json': { schema: { type: 'object' }, example } },
  };
}

function multipartBody(example: unknown) {
  return {
    required: true,
    content: { 'multipart/form-data': { schema: { type: 'object' }, example } },
  };
}

function query(name: string, example: string) {
  return { name, in: 'query', required: false, schema: { type: 'string', example } };
}

function path(name: string) {
  return { name, in: 'path', required: true, schema: { type: 'string' } };
}
