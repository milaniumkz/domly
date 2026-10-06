# DOMLY deployment

## Основной поток

1. Создать ветку от `main`.
2. Внести изменения.
3. Открыть Pull Request.
4. Дождаться GitHub Actions `CI`.
5. После merge в `main` workflow `Deploy backend to VPS` обновляет сервер.

## Ручной деплой

GitHub → Actions → `Deploy backend to VPS` → `Run workflow`.

## Ручные операции сервера

GitHub → Actions → `Server operations`:

- `status` — состояние Docker services и API.
- `logs` — последние диагностические логи api/worker без `.env`.
- `restart` — перезапуск api/worker.
- `redeploy` — повторный деплой текущего commit.
- `rollback` — откат к последнему совместимому release snapshot.

## Где данные

- PostgreSQL: Docker volume `postgres_data`.
- Redis: Docker volume `redis_data`.
- MinIO файлы: Docker volume `minio_data`.
- Production env: `/opt/domly-backend/backend/.env` на VPS.
- Backups: `/opt/domly-backend/backups` и `backend/backups` сервиса backup.

## Синхронизация локальной копии

```bash
git pull origin main
cd backend && npm ci
flutter pub get
```

## iOS/Android

CI проверяет Flutter код. Подписанные IPA/AAB требуют macOS и закрытые signing credentials, они не хранятся в GitHub репозитории.
