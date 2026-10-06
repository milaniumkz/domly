# DOMLY

Рабочая копия DOMLY для миграции на отдельный backend без Firebase. Текущий production Firebase-проект не трогаем: Firebase остается только для FCM push-уведомлений.

## Репозиторий

- GitHub: `https://github.com/milaniumkz/domly`
- Основная ветка: `main`
- VPS backend: `/opt/domly-backend`
- API: `https://api.89-126-200-97.sslip.io`
- Документация API: `https://api.89-126-200-97.sslip.io/api/docs/`

## Состав

- `backend/` — Express + TypeScript API, PostgreSQL, Redis, MinIO, FCM.
- `lib/` — Flutter приложения: клиент, уборщица, админка.
- `docs/` — инструкции по Codex Cloud, VPS и деплою.
- `.github/workflows/` — CI, deploy и server operations.
- `scripts/server/` — серверные deploy/ops скрипты.

## Локальная проверка

```bash
cd backend
npm ci
npm run build
npm test
```

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/localization test/models test/services
```

## Деплой

Деплой выполняется автоматически через GitHub Actions после push в `main`.

Ручной деплой:

```bash
gh workflow run deploy.yml --repo milaniumkz/domly --ref main
```

Проверка сервера:

```bash
curl -fsS https://api.89-126-200-97.sslip.io/health
curl -fsS https://api.89-126-200-97.sslip.io/ready
```

## Server Operations

Через GitHub Actions `Server operations` доступны:

- `status` — состояние Docker-сервисов.
- `logs` — последние логи API.
- `restart` — перезапуск backend.
- `redeploy` — повторный деплой `main`.
- `rollback` — откат на предыдущий релиз.

## Codex Cloud

Инструкция: `docs/CODEX_CLOUD.md`.

Минимальная команда проверки в cloud-среде:

```bash
cd backend && npm ci && npm test
```

## Безопасность

- `.env`, ключи, Firebase service accounts, keystore и build-артефакты не коммитятся.
- Production deploy идет только из `main`.
- Перед деплоем серверный скрипт делает backup env и PostgreSQL.

## Важно

Текущую рабочую Firebase-версию приложения не менять без отдельного согласия. Все изменения backend-migration идут через этот репозиторий и VPS.
