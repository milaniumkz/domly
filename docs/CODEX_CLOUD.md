# Codex Cloud для DOMLY

1. Открой Codex Cloud.
2. Подключи GitHub repository `milaniumkz/domly`.
3. Рабочая ветка по умолчанию: `main`; задачи делать в отдельных ветках.
4. Команды проверки:
   - backend: `cd backend && npm ci && npm test`
   - Flutter: `flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/localization test/models test/services`
5. Для разработки backend используй `.env.example` и отдельную тестовую PostgreSQL/Redis/MinIO, не production `.env`.
6. Production деплой выполняется только GitHub Actions workflow `Deploy backend to VPS`.

Firebase в новой backend-test архитектуре используется только для FCM push.
