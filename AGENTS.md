# DOMLY Agent Instructions

отвечай коротко и понятно

Всегда применяй навык `limit-efficient-quality`: максимально экономь лимиты токенов, инструментов, времени и контекста, но не снижай качество результата.

## Структура проекта

- `lib/` — Flutter-приложения: клиент, уборщица, админка.
- `backend/` — новый backend без Firebase Auth/Firestore/Functions: Express + TypeScript + PostgreSQL + Redis + MinIO. Firebase используется только для FCM push.
- `functions/` — legacy Firebase Functions. Не развивать без отдельного решения.
- `scripts/` — сборки Flutter/web, Firebase hosting, служебные скрипты.
- `docs/` — инструкции эксплуатации, деплоя и облачной разработки.
- `android/`, `ios/`, `web/`, `assets/` — платформенные файлы и ресурсы Flutter.

## Команды проверки

Backend:

```bash
cd backend
npm ci
npm run build
npm test
```

Flutter:

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/localization test/models test/services
```

Web сборки:

```bash
./scripts/build_web_domly.sh
./scripts/build_web_domly_pro.sh
./scripts/build_web_admin.sh
```

## База данных и файлы

- Production данные живут на VPS в Docker volumes `postgres_data`, `redis_data`, `minio_data` и в `backend/.env`.
- Не коммитить `.env`, дампы базы, загруженные пользователями файлы, keystore, service account JSON.
- Миграции backend находятся в `backend/sql/schema.sql`. Несовместимые изменения схемы и удаление данных согласовывать отдельно.

## Деплой

- PR запускает проверки.
- Production деплой разрешён только из `main` после успешных проверок или вручную через GitHub Actions.
- Деплой делает backup PostgreSQL и конфигурации, синхронизирует проверенный commit на VPS, пересобирает Docker Compose и проверяет `/health`/`/ready`.
- Не отключать SSH host key verification.

## Codex Cloud

Использовать отдельные ветки. Для тестов использовать тестовую БД/конфигурацию, не production `.env`.
