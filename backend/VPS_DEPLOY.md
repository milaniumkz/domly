# DOMLY Backend VPS Deploy

Текущий production Firebase не трогать. Эта папка предназначена для нового backend на VPS.

## 1. Подготовка

```bash
cd /opt/domly/DOMLY_backend_migration/backend
cp .env.example .env
nano .env
```

`docker-compose.yml` читает этот файл напрямую для `api`, `worker`, `postgres`, `minio` и `backup`.

Обязательно поменять:

- `DATABASE_URL`
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- `JWT_ACCESS_SECRET`
- `JWT_REFRESH_SECRET`
- `ADMIN_BOOTSTRAP_PASSWORD`
- `MINIO_ROOT_PASSWORD`, `MINIO_SECRET_KEY`
- `WAPI_TOKEN`, `WAPI_PROFILE_ID`
- Kaspi/BCC параметры
- FCM service account поля

Важно: пароль в `DATABASE_URL` должен совпадать с `POSTGRES_PASSWORD`.

FCM можно заполнить одним из способов:

- `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`;
- `FCM_SERVICE_ACCOUNT_JSON` — полный JSON service account в одну строку;
- `FCM_SERVICE_ACCOUNT_BASE64` — base64 от JSON-файла;
- `FCM_SERVICE_ACCOUNT_FILE` — путь к JSON-файлу на VPS.

`api` и `worker` проверяют `.env` при старте. В `production` или при `STRICT_ENV=true`
запуск остановится, если оставлены dev/placeholder-секреты или не заполнены базовые
параметры PostgreSQL, Redis, JWT и MinIO.

Внешние интеграции можно сделать обязательными отдельными флагами:

- `REQUIRE_WAPI=true` — SMS/OTP через WAPI;
- `REQUIRE_FCM=true` — push-уведомления;
- `REQUIRE_PAYMENTS=true` — минимум один платёжный провайдер Kaspi или BCC;
- `REQUIRE_ADDRESS_FALLBACK=true` — Yandex fallback для адресов;
- `REQUIRE_EXTERNAL_INTEGRATIONS=true` — требовать всё сразу.

Для BCC/ePay `BCC_NOTIFY_URL` обязательно указывать с явным портом, как требует
TRTYPE=1, например:

```env
BCC_NOTIFY_URL=https://api.domly.kz:443/api/v1/payments/bcc/webhook
```

## 2. Запуск

```bash
cd /opt/domly/DOMLY_backend_migration
docker compose up -d --build
```

Для обновлений используйте безопасный deploy-скрипт из локальной копии. Он не затирает
`backend/.env`, backup-файлы и локальные build-каталоги:

```bash
cd backend
chmod +x deploy-vps-safe.sh
./deploy-vps-safe.sh
```

Если на VPS HTTPS уже обслуживает Caddy, оставьте `USE_CADDY=true` по умолчанию.
Тогда скрипт не запускает compose-сервис `nginx`, чтобы не конфликтовать с портами
80/443. Если Caddy не используется:

```bash
USE_CADDY=false ./deploy-vps-safe.sh
```

При старте `api` и `worker` ждут PostgreSQL и применяют `backend/sql/schema.sql`.
Схема идемпотентная, а `docker-entrypoint.sh` берёт PostgreSQL advisory lock, поэтому
параллельный старт `api` и `worker` не запускает миграцию одновременно.

Проверка:

```bash
curl http://localhost/health
curl http://localhost/ready
curl http://localhost/api/docs
docker compose ps
```

Автоматический smoke-test API:

```bash
docker compose exec api npm run smoke:vps
```

Smoke-test может проверить реальную отправку OTP через WAPI, но только если явно
передать телефон и admin token:

```bash
docker compose exec \
  -e SMOKE_ADMIN_TOKEN=... \
  -e SMOKE_TEST_PHONE=+77052597368 \
  api npm run smoke:vps
```

Для внешней проверки домена:

```bash
SMOKE_BASE_URL=https://api.domly.kz npm run smoke:vps
```

`/health` проверяет быстрый статус API и PostgreSQL. `/ready` дополнительно проверяет Redis и MinIO, а также показывает, настроены ли WAPI и FCM.

Worker запускается отдельным сервисом `worker` и обрабатывает:

- push-уведомления;
- тревожный звук уборщицы по заказам;
- фоновые платежные события.

`api` и `worker` обрабатывают `SIGTERM/SIGINT`: закрывают HTTP/SSE, PostgreSQL, Redis pub/sub и BullMQ-соединения перед остановкой контейнера.

Backup-сервис сохраняет PostgreSQL и MinIO:

- база: `backend/backups/postgres/*.sql.gz`;
- файлы/фото/документы/баннеры: `backend/backups/minio/*.tar.gz`;
- manifest с размером и `sha256`: `backend/backups/manifest.jsonl`;
- периодичность и срок хранения задаются через `BACKUP_INTERVAL_SECONDS` и `BACKUP_KEEP_DAYS`.

Разовый backup:

```bash
docker compose run --rm -e BACKUP_ONCE=true backup
```

Восстановление последнего backup требует явного подтверждения:

```bash
docker compose run --rm -e RESTORE_CONFIRM=YES backup domly-restore
```

Восстановление конкретных файлов:

```bash
docker compose run --rm \
  -e RESTORE_CONFIRM=YES \
  -e POSTGRES_BACKUP=/backups/postgres/domly_YYYYMMDDTHHMMSSZ.sql.gz \
  -e MINIO_BACKUP=/backups/minio/domly_minio_YYYYMMDDTHHMMSSZ.tar.gz \
  backup domly-restore
```

Если нужно проверить целостность перед восстановлением, возьмите `sha256` из
`backend/backups/manifest.jsonl` и передайте:

```bash
docker compose run --rm \
  -e RESTORE_CONFIRM=YES \
  -e POSTGRES_BACKUP_SHA256=... \
  -e MINIO_BACKUP_SHA256=... \
  backup domly-restore
```

Первичный superadmin:

```bash
docker compose exec api npm run bootstrap:admin
```

Повторный запуск не перезаписывает существующий пароль. Чтобы намеренно сменить пароль
superadmin, выставьте в `.env`:

```bash
ADMIN_BOOTSTRAP_RESET_PASSWORD=true
ADMIN_BOOTSTRAP_PASSWORD=новый_сложный_пароль
```

Затем снова выполните `docker compose exec api npm run bootstrap:admin` и верните
`ADMIN_BOOTSTRAP_RESET_PASSWORD=false`.

## 3. Миграция Firestore

Скрипты только читают Firebase и ничего там не меняют.

```bash
cd backend
export GOOGLE_APPLICATION_CREDENTIALS=/secure/firebase-service-account.json
FIREBASE_EXPORT_DIR=/opt/domly/firebase-export \
MIGRATION_REPORT_DIR=/opt/domly/reports \
npm run migration:run
```

`firebase:audit` ничего не пишет в PostgreSQL и Firebase. Он читает JSON-выгрузку,
создаёт `firebase-export/migration-audit.json` и показывает проблемы до импорта:
пользователи без телефона, платежи без суммы, заказы без клиента/даты/времени,
дома без улицы/номера и коллекции без маппинга.

## 4. API

- Base URL: `/api/v1`
- Docs: `/api/docs`
- Realtime SSE: `/api/v1/realtime`
- Backend config: `/api/v1/app/config`
- Success response: `{ "ok": true, "data": ... }`
- Error response: `{ "ok": false, "code": "...", "message": "понятный текст" }`

## 5. Что остаётся от Firebase

После переключения приложения Firebase используется только для FCM push-уведомлений.
Firestore/Auth/Functions заменяются этим backend только после отдельного разрешения.
