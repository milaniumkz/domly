# DOMLY Backend Migration

Новая серверная часть DOMLY без Firestore/Auth/Functions.

Стек:

- Express + TypeScript
- PostgreSQL
- Redis + BullMQ
- MinIO
- Firebase Admin SDK только для FCM

Основные команды:

```bash
npm install
npm run build
npm test
npm run dev
npm run start:worker
npm run bootstrap:admin
npm run smoke:vps
```

Production запуск описан в `VPS_DEPLOY.md`.
Docker runtime применяет `sql/schema.sql` при старте `api` и `worker`, поэтому существующая база на VPS получает новые таблицы/индексы без ручного SQL.
Секреты в `.env.example` заменены на плейсхолдеры; рабочие WAPI/Kaspi/BCC/FCM ключи хранятся только в реальном `.env`.
При `NODE_ENV=production` или `STRICT_ENV=true` backend валидирует `.env` до подключения к базе и не стартует с dev-секретами или неполной базовой конфигурацией.
WAPI, FCM, платежи и Yandex fallback можно сделать обязательными через `REQUIRE_*` флаги в `.env`.
Smoke endpoint-ы: `/health` проверяет API/PostgreSQL, `/ready` проверяет PostgreSQL, Redis, MinIO и конфигурацию WAPI/FCM.
`npm run smoke:vps` проверяет `/health`, `/ready`, `/api/v1/app/versions`, `/api/v1/app/bootstrap`, `/api/v1/app/runtime-config`, `/api/docs`, ETag/304 и shape backend-driven правил.
Если передать `SMOKE_ADMIN_TOKEN`, дополнительно проверяется `/api/v1/admin/settings/meta`.

## Backend-driven app

Чтобы меньше обновлять мобильные приложения, клиент должен читать настройки с:

- `GET /api/v1/app/config`
- `GET /api/v1/app/bootstrap`
- `GET /api/v1/app/versions`
- `GET /api/v1/app/runtime-config`
- `GET /api/v1/translations`
- `GET /api/v1/catalog/packages`
- `GET /api/v1/catalog/addons`
- `GET /api/v1/catalog/banners`

Через backend/admin API редактируются:

- переводы RU/KK;
- пакеты, допы, группы допов;
- акции и баннеры;
- правила бонусов и платежей;
- дата старта, лимиты, обязательность проверки площади;
- тексты уведомлений;
- слоты и назначение уборщиц.

Flutter после переключения должен быть тонким клиентом: отображать данные backend и не хранить бизнес-правила локально.
Для этого `GET /api/v1/app/config` отдаёт блок `backendDriven`: флаги функций, правила записи, оплату бонусами, обязательность проверки площади, навигацию и тексты уведомлений RU/KK.
Для частого обновления без лишней загрузки каталога есть лёгкий `GET /api/v1/app/runtime-config`: он отдаёт только runtime-правила, `version`, `updatedAt`, `ETag` и поддерживает `If-None-Match`/`304`.
Для первого запуска или полной синхронизации есть `GET /api/v1/app/bootstrap`: он отдаёт runtime-правила, переводы, пакеты, допы, баннеры, акции и страницы контента с `ETag`/`304`.
Для дешёвой проверки изменений есть `GET /api/v1/app/versions`: версии по секциям `settings`, `translations`, `packages`, `addons`, `banners`, `promotions`, `contentPages`.
Эти значения меняются через `POST /api/v1/admin/settings` без обновления приложения: можно сохранить один ключ `{ "key": "allowCustomTime", "value": false }` или сразу набор `{ "settings": { "allowCustomTime": false, "minBookingDate": "2026-09-02" } }`.
`GET /api/v1/admin/settings/meta` отдаёт секции, поля, типы и текущие merged-значения для построения формы настроек в админке без релиза клиента.
Ключевые runtime-настройки: `paymentFlow`, `uiBehavior`, `validationRules`, `errorMessages`, `appText`, `featureFlags`, `customerTabs`, `cleanerTabs`.
Расширенные backend-first правила также отдаются через `runtime-config`: `localization`, `addressSearch`, `assignmentRules`, `orderRules`, `adminNotificationRules`, `contentRules`, `trainingFlow`, `screenRules`.
Даже если админ меняет только одно поле внутри JSON-настройки, backend возвращает полную секцию с дефолтами, поэтому приложение не должно держать fallback-бизнес-логику локально.
Их нужно менять в `app_settings`, чтобы мобильные приложения только перечитывали конфиг и не требовали новой сборки для бизнес-логики, текстов, маршрутизации, поиска адресов, правил оплаты, назначения уборщиц и уведомлений.
`adminNotificationRules` управляет пушами и внутренними уведомлениями админки. Сейчас backend создаёт события для новых пользователей/уборщиц, новых заказов, заявок на оплату, проверок площади и предварительных записей. Уведомления создаются для ролей `admin` и `superadmin`, поддерживают `targetType/targetId` для перехода в нужный раздел админки и дедуплицируются по событию.

Дополнительно уже вынесено на backend:

- JWT refresh-сессии: `POST /api/v1/auth/refresh`;
- выход из аккаунта и отзыв сессий/FCM token: `POST /api/v1/auth/logout`, `DELETE /api/v1/me/device-tokens/:token`;
- вход админки/уборщицы по паролю: `POST /api/v1/auth/password/login`;
- адреса пользователя: `GET/POST/PATCH /api/v1/addresses`;
- история бонусов: `GET /api/v1/bonus/history`;
- покупки пакетов клиента: `GET /api/v1/packages/my`;
- профиль уборщицы, документы и настройки звука: `GET/PATCH /api/v1/cleaner/profile`, `POST /api/v1/cleaner/documents`;
- жалобы и статусы жалоб;
- отзывы с пересчётом рейтинга уборщицы;
- чаты заказов/жалоб: `GET/POST /api/v1/chats`, `GET/POST /api/v1/chats/:id/messages`, `POST /api/v1/chats/:id/read`;
- детальные карточки админки без сырых Firebase/UUID вместо данных.
- Kaspi/BCC init payload формируется на backend и сохраняется в `payments.payload`; Flutter получает уже готовый результат оплаты.
- BCC status/refund/connection payload формируется на backend:
  - `POST /api/v1/payments/:id/status-check`
  - `POST /api/v1/payments/:id/refund`
  - `POST /api/v1/payments/bcc/connection-check`
- webhook/status/refund события сохраняются в `payment_events` и видны в `GET /api/v1/admin/payments/:id/details`;
- чек-лист заказа формируется backend из стандартных пунктов пакета и оплаченных допов;
- выплаты уборщиц проверяются по доступному балансу и уходят админу на подтверждение;
- общий admin list поддерживает `status`, `dateFrom`, `dateTo`, `search`, `limit`, `offset`.
- webhook Kaspi/BCC при `paid` активирует пакет или заказ, помечает допы оплаченными и запускает подбор уборщицы;
- повторные webhook/ручные подтверждения одного платежа не применяют оплату второй раз: backend атомарно фиксирует `payments.applied_at`;
- поздний `paid` webhook не оживляет платежи в статусах `cancelled/refunded`;
- дома, зоны покрытия и шаблоны чек-листов редактируются через backend/admin API;
- поиск подключённых домов: `GET /api/v1/geo/connected-houses?city=Астана&search=...`.
- единый backend-поиск адресов для приложения:
  `GET /api/v1/geo/address-suggestions?city=Астана&search=Сдык 39&lat=51.12&lng=71.43`.
  Сначала ищет подключённые дома/ЖК в PostgreSQL, затем при нехватке результатов включает OSM, затем Yandex Geocoder. Внешние результаты ограничены городом/радиусом 50 км и не возвращают заведения.
- отмена заказа на backend отменяет допы, офферы уборщиц, ожидающие платежи, возвращает бонусы и помечает оплаченные платежи как `refunded`;
- создание заказа списывает одну уборку из активного пакета, отмена заказа возвращает её обратно;
- уведомления админки доступны через `GET /api/v1/admin/notifications`.
- админская верификация и зоны уборщиц: `PATCH /api/v1/admin/cleaners/:id/verification`, `PUT /api/v1/admin/cleaners/:id/zones`.
- доступные слоты считаются на backend через `GET /api/v1/scheduling/available-slots`; длительность берётся из `app_settings`: `baseCleaningMinutes`, `minutesPerM2`, `slotStartTimes`.
- акции применяются на backend после подтверждения оплаты пакета: начисляются бонусы, пишется история, есть защита от повторного начисления и режима “один раз клиенту”.
- акции, баннеры, пакеты, допы и группы допов доступны в общем admin list и редактируются backend API без релиза приложения.
- политика, оферта и информационные страницы хранятся в `content_pages` и редактируются через:
  - `GET /api/v1/content-pages`
  - `GET /api/v1/content-pages/:slug`
  - `POST /api/v1/admin/content-pages`
  - `PATCH /api/v1/admin/content-pages/:slug`
- уведомления управляются backend API:
  - `GET /api/v1/notifications`
  - `GET /api/v1/notifications/unread-count`
  - `POST /api/v1/notifications/:id/read`
  - `POST /api/v1/notifications/read-all`
  - `GET /api/v1/admin/notifications`
  - `POST /api/v1/admin/notifications`
  - новые уведомления также уходят в SSE `/api/v1/realtime`.
  Role-уведомления админки читаются персонально через `notification_reads`: если один админ отметил уведомление прочитанным, у других админов оно остаётся непрочитанным.
  Для web EventSource поддерживается `GET /api/v1/realtime?access_token=...`; соединение держится heartbeat-событиями `ping`.
  Realtime работает через Redis pub/sub, поэтому события из API и worker доходят до открытых SSE-соединений без Firestore listeners.
- словари переводов управляются backend API:
  - `GET /api/v1/admin/translations?missing=kk&namespace=app&search=...`
  - `GET /api/v1/admin/translations/stats`
  - `POST /api/v1/admin/translations`
  - `POST /api/v1/admin/translations/bulk`
  - `POST /api/v1/admin/translations/sync-defaults` — добавить базовые RU/KK строки, не перетирая правки админа;
- настройки backend правил доступны через `GET/POST /api/v1/admin/settings`.
- smoke-status интеграций доступен админам через `GET /api/v1/admin/integrations/status`: WAPI, FCM, MinIO, backup, Kaspi/BCC, OSM/Yandex и полный env-отчёт `issues/warnings`.
- пользователи управляются через `GET /api/v1/users`, `GET /api/v1/users/:id`, `PATCH /api/v1/admin/users/:id`, `POST /api/v1/admin/users/:id/bonus-adjustment`.
- уборщицы управляются через `POST /api/v1/admin/cleaners`, `PATCH /api/v1/admin/cleaners/:id`, `DELETE /api/v1/admin/cleaners/:id`, детали через `GET /api/v1/admin/cleaners/:id/details`.
- справочники и контент можно включать/отключать без удаления через `PATCH /api/v1/admin/:section/:id/active`, где `section`: `packages`, `addons`, `addonGroups`, `banners`, `promotions`, `contentPages`, `zones`, `houses`.

## Orders and cleaner offers

Backend сам решает, когда заказ можно отдавать уборщице:

- заказ без доплат после создания сразу получает `pending_assignment` и уходит ближайшей свободной уборщице;
- заказ с доплатой сначала получает `pending_payment`;
- после подтверждения оплаты backend сам помечает допы оплаченными и отправляет заказ следующей доступной уборщице;
- уборщица работает только через предложения:
  - `GET /api/v1/cleaner/offers`
  - `POST /api/v1/cleaner/offers/:id/accept`
  - `POST /api/v1/cleaner/offers/:id/decline`
- если уборщица отказалась, backend передаёт заказ следующей доступной уборщице;
- если уборщица не ответила за 15 минут, worker переводит предложение в `expired` и передаёт заказ следующей уборщице;
- если свободных нет, заказ остаётся `waiting_cleaner`, а админ получает уведомление.

TTL оффера и тихие часы звуков уборщицы управляются на backend через `app_settings`:
`cleanerOfferTtlMinutes`, `cleanerQuietHoursEnabled`, `cleanerQuietHoursStart`, `cleanerQuietHoursEnd`.

## Workers

Запуск:

```bash
npm run start:worker
```

Очереди BullMQ:

- `notifications` — отправка push;
- `cleaner-alarms` — громкое уведомление уборщице о новом заказе;
- `payments` — аудит платёжных событий;
- `maintenance` — истечение предложений уборщиц, повторное распределение заказов, очистка просроченных OTP/refresh-сессий/старых выключенных FCM-токенов.

Админка может читать audit через `GET /api/v1/admin/audit`; ответ включает действие, объект, payload и данные актора: номер, имя, телефон, email, роль.

## API contract

OpenAPI доступен после запуска backend:

```bash
curl http://localhost:8080/api/docs
```

Все новые и legacy endpoint-ы отвечают единообразно:

- success: `{ "ok": true, "data": ... }`;
- error: `{ "ok": false, "code": "...", "message": "понятный текст", "messageRu": "...", "messageKk": "..." }`.

Язык ошибки выбирается по `?lang=kk`, `X-App-Language` или `Accept-Language`. Технические stack trace пользователю не отдаются.

Контракт покрывает основные группы endpoint-ов:

- auth/session/device tokens;
- app config, переводы, справочники, content pages;
- адреса, бонусы, пакеты, заказы, слоты;
- платежи Kaspi/BCC, webhook, refund/status checks;
- уведомления, чаты, жалобы, отзывы, checklists;
- profile/documents/settings уборщицы;
- admin списки, details, settings, CRUD справочников и контента.

## Test coverage

`npm test` проверяет сборку TypeScript и критичные правила:

- нормализация телефонов и адресов RU/KZ;
- расчёт пакетов и бонусной оплаты;
- 100% бонусная оплата создаёт `paid` payment без внешнего счёта;
- обязательные поля BCC/ePay payload;
- fairness/scheduling: пересечения времени, дневная загрузка, назначение уборщицы.

## Migration coverage

Скрипты миграции работают read-only к Firebase:

- `npm run firebase:export` — выгружает Firestore в JSON, включая вложенные subcollections, и пишет `storage-manifest.json` по Firebase Storage;
- `npm run firebase:audit` — проверяет JSON-выгрузку до импорта и пишет `firebase-export/migration-audit.json`;
- `npm run firebase:import` — сохраняет каждый документ в `legacy_firestore_documents`, мапит известные коллекции в PostgreSQL, переносит metadata файлов в `files` и связывает файлы с баннерами, акциями и проверками площади;
- `npm run firebase:verify` — сверяет количество legacy-документов и базовые инварианты, пишет `firebase-export/migration-verify.json`.
- `firebase:verify` дополнительно сверяет суммы оплат, бонусные суммы, статусы платежей/заказов,
  общий баланс бонусов пользователей, счётчики активных пакетов, наличие цели у paid-платежей,
  сиротские связи заказов/платежей/чатов/уведомлений, соответствие бонусного баланса истории
  операций, количество файлов из `storage-manifest.json` и битые ссылки на файлы.
- `firebase:audit` заранее показывает коллекции без маппинга и критичные проблемы в данных:
  телефоны пользователей, названия/цены пакетов и допов, клиенты у адресов/купленных пакетов,
  даты/время заказов, суммы платежей, проверки площади, жалобы и отзывы.
- `firebase:import` работает в несколько проходов и не зависит от порядка коллекций в export:
  сначала сохраняет legacy-документы, затем файлы, затем пользователей, справочники,
  адреса/пакеты клиентов, заказы, платежи и зависимые сущности.

Мапятся: пользователи, уборщицы, адреса клиентов, купленные пакеты клиентов, пакеты, группы допов, допы, зоны, дома, переводы, баннеры, акции, content pages, настройки, заказы, выбранные допы заказов, платежи, предварительные записи, проверки площади, уведомления, жалобы, отзывы, чаты и сообщения.

Для фактического переноса файлов в MinIO сначала выгрузите Storage с файлами:

```bash
FIREBASE_EXPORT_STORAGE_DOWNLOAD=true npm run firebase:export
IMPORT_STORAGE_TO_MINIO=true npm run firebase:import
```

Для CI/VPS можно явно задать пути отчётов:

```bash
FIREBASE_EXPORT_DIR=/opt/domly/firebase-export \
MIGRATION_AUDIT_OUT=/opt/domly/reports/migration-audit.json \
npm run firebase:audit

FIREBASE_EXPORT_DIR=/opt/domly/firebase-export \
MIGRATION_VERIFY_OUT=/opt/domly/reports/migration-verify.json \
npm run firebase:verify
```

Полный перенос одной командой:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/secure/firebase-service-account.json
FIREBASE_EXPORT_DIR=/opt/domly/firebase-export \
MIGRATION_REPORT_DIR=/opt/domly/reports \
npm run migration:run
```
