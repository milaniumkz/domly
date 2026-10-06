# DOMLY Ecosystem (Flutter + Firebase)

Реализовано 3 приложения:

- `DOMLY` (заказчики): `lib/main_customer.dart`
- `Domly Pro` (уборщицы): `lib/main_pro.dart`
- `Domly Admin Web`: `lib/main_admin_web.dart`

## Что сделано по ТЗ

1. Авторизация: Firebase Phone Auth с реальным OTP.
2. Платежи: интеграция ePay (`epayment.kz`) через Cloud Functions (token/invoice/status/webhook).
3. Веб-админка: отдельный web entrypoint + экран управления заказами/жалобами/выплатами.
4. Чат, жалобы, фотоотчеты: Firestore + Firebase Storage.
5. Push-уведомления: Firebase Messaging + локальные уведомления на устройстве.
6. Геолокация/карта кластеров: Google Maps (`/map/clusters`).
7. Выплаты уборщиц: weekly payout через ePay с удержанием 4% налога.
8. Доп. функции: способ доступа, доп. услуги, заморозка подписки, реферал.

## Backend (Cloud Functions)

Файл: `functions/index.js`

Ключевые функции:

- `createOrderFromRequest`
- `createPaymentInvoice`
- `createOrderAndInvoice`
- `syncPaymentStatus`
- `confirmPayment`
- `assignCleaner`
- `advanceOrderStatus`
- `generateSubscriptionSlots`
- `subscriptionSlotScheduler`
- `processAdminAction`
- `requestWeeklyPayout`
- `weeklyPayoutScheduler`
- `epayWebhook`

## Firebase Rules/Indexes

- `firestore.rules`
- `firestore.indexes.json`
- `firebase.json`
- `.firebaserc` (`domly-d0f91`)

## Переменные окружения (Cloud Functions)

- `EPAY_TOKEN_URL` (по умолчанию тестовый OAuth URL)
- `EPAY_INVOICE_URL`
- `EPAY_STATUS_URL`
- `EPAY_PAYOUT_URL`
- `EPAY_INVOICE_CLIENT_ID`
- `EPAY_INVOICE_CLIENT_SECRET`
- `EPAY_PAYOUT_CLIENT_ID`
- `EPAY_PAYOUT_CLIENT_SECRET`
- `EPAY_SHOP_ID`
- `EPAY_TERMINAL_ID`
- `EPAY_PAYOUT_TERMINAL_ID`
- `EPAY_WEBHOOK_TOKEN`
- `SUBSCRIPTION_WINDOW_DAYS`

## Переменные запуска Flutter (`--dart-define`)

- `FIREBASE_API_KEY`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_APP_ID_ANDROID`
- `FIREBASE_APP_ID_IOS`
- `FIREBASE_APP_ID_WEB`
- `SEED_FIRESTORE_ON_START=false`

## Установка

```bash
flutter pub get
```

## Запуск приложений

### DOMLY

```bash
flutter run \
  --target lib/main_customer.dart \
  --flavor domly
```

### Domly Pro

```bash
flutter run \
  --target lib/main_pro.dart \
  --flavor domlyPro
```

### Admin Web

```bash
flutter run \
  -d chrome \
  --target lib/main_admin_web.dart
```

## Сборка

```bash
./scripts/build_android_domly.sh
./scripts/build_android_domly_pro.sh
./scripts/build_ios_domly.sh
./scripts/build_ios_domly_pro.sh
./scripts/build_web_domly.sh
./scripts/build_web_domly_pro.sh
./scripts/build_web_admin.sh
./scripts/check_web_config_consistency.sh
./scripts/verify_release_readiness.sh
./scripts/post_deploy_web_smoke.sh
```

## Firebase deploy

```bash
./scripts/prepare_backend_deploy.sh     # backend preflight + functions upload access probe
./scripts/deploy_all.sh                 # rules, indexes, storage, functions
./scripts/deploy_functions.sh           # signInWithOtp only
./scripts/deploy_web_all.sh             # build and deploy customer/pro/admin hosting
./scripts/check_web_config_consistency.sh # release config + entrypoint consistency
./scripts/verify_release_readiness.sh   # backend runtime/access + web readiness
./scripts/post_deploy_web_smoke.sh      # live customer/pro/admin URL/title smoke
```

Для backend scripts требуется тот же major Node.js, что указан в `functions/package.json` (`engines.node`).
Проверка выполняется автоматически через `./scripts/check_functions_node_version.sh`.
Если в системе уже установлен Homebrew `node@22`, scripts автоматически подхватывают его через `./scripts/use_functions_node_env.sh`.
Если `node@22` не установлен, preflight подскажет прямую команду: `brew install node@22`.
Доступ к `functions upload` проверяется заранее через `./scripts/check_functions_deploy_access.sh`.
Установка dependencies для `functions` идет через `./scripts/install_functions_dependencies.sh` и использует `npm ci`, если есть `package-lock.json`.

`./scripts/verify_release_readiness.sh` теперь включает и backend preflight:

- проверку Node major version для `functions`
- `node --check functions/index.js`
- probe на `functions:generateUploadUrl`

## Web deploy

Для web используется раздельная выкладка:

- customer site: `build/web-domly`
- pro site: `build/web-pro`
- admin build: `build/web-admin`

Скрипты:

```bash
./scripts/build_web_domly.sh
./scripts/build_web_domly_pro.sh
./scripts/build_web_admin.sh
./scripts/deploy_web_all.sh
```

`deploy_web_all.sh` перед выкладкой дополнительно проверяет, что:

- `build/web-domly/index.html` содержит `DOMLY`
- `build/web-pro/index.html` содержит `Domly Pro`
- `build/web-admin/index.html` содержит `Domly Admin Web`

Перед релизом можно отдельно прогнать:

```bash
./scripts/check_web_config_consistency.sh
```

Этот скрипт теперь проверяет не только hosting/build config, но и согласованность backend/web release entrypoint’ов.

После сборки проверьте, что заголовки в артефактах корректные:

- `build/web-domly/index.html` -> `DOMLY`
- `build/web-pro/index.html` -> `Domly Pro`
- `build/web-admin/index.html` -> `Domly Admin Web`

## Production checklist

Перед выпуском:

```bash
flutter analyze
flutter test
./scripts/verify_release_readiness.sh
```

После выкладки:

- открыть `https://domly-d0f91.web.app`
- открыть `https://domly-pro.web.app`
- открыть `https://domly-admin-web.web.app`
- убедиться, что customer site не уходит на `#/admin/web`
- убедиться, что `domly-pro.web.app` не отдаёт `Site Not Found`
- убедиться, что `domly-admin-web.web.app` не отдаёт `Site Not Found`
- проверить калькулятор пакета и расчёт стоимости
- проверить вход по реальному номеру

Быстрый smoke после выкладки:

```bash
./scripts/post_deploy_web_smoke.sh
```

Скрипт проверяет:

- что `customer`, `pro` и `admin` отвечают без `Site Not Found`
- что каждый домен отдает свой ожидаемый `<title>`
- что customer/pro не подмешали admin build markers

## Firestore seed

```bash
node functions/scripts/seed_firestore.js
```

## Production контур

- backend: только Firebase
- auth: только Firebase Auth
- роли админки: `admin` / `superAdmin` через custom claims
- seed/demo данные используются только при явном `SEED_FIRESTORE_ON_START=true`
- `WappiService`, `SessionStore` и локальные demo UID не участвуют в production auth flow
