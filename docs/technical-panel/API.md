# API технического центра

База — `/api/tech/api`. Не принимает JWT приложений. Все ответы JSON `{ok:true,data:...}` либо `{ok:false,code,message,...}`. Изменения требуют `X-Tech-CSRF` из `/me`, отдельную cookie сеанса и допустимый Origin. Cookie не передаётся через query string. Доступ дополнительно ограничен правами и `user_scope`.

| Метод и путь | Назначение / право |
|---|---|
| POST /login | login, password; отдельный вход с ограничением попыток |
| GET /me | Текущий технический оператор, CSRF и публичный VAPID |
| POST /password | currentPassword/newPassword; обязательная смена временного |
| POST /logout | Отзыв текущего технического сеанса |
| GET /overview | Реальные источники, ресурсы, heartbeat, аудит; events.read |
| GET /events | Хронология и фильтры; events.read |
| GET /events/:id | Одно событие, подпись, точные загрузки и явно переданные файлы |
| GET /problems | q/status/kind/severity, пагинация |
| GET /problems/:id | Рекомендации, версии, комментарии и точные пользователи |
| PATCH /problems/:id | problems.manage; статус, ответственный, причина, комментарии |
| GET /users | Поиск, роль, состояние, последние входы и число сеансов |
| GET /users/:id | Роль/состояние/сеансы; персональные поля отдельно |
| POST /users/:id/operation | users.manage + dangerous; block/unblock/revoke_sessions/temporary_password |
| GET /files | Метаданные, user/event/decision; files.preview |
| GET /files/:id | Метаданные и качество; без bucket/object_key URL |
| GET /files/:id/preview | files.preview + pii.read; JPEG вписанный до 1800 px |
| GET /files/:id/original | files.original + pii.read; авторизация, SHA-256, аудит, attachment |
| POST /files/:id/review | problems.manage + files.preview; техническая оценка, не бизнес-утверждение |
| GET /objects/:type/:id/materials | Отдельные текущие материалы orders/quality-checks/users/cleaners |
| GET /notifications | Только свои уведомления; пагинация |
| POST /notifications/:id/ack | Подтверждение своего уведомления |
| POST /notifications/mute | minutes 0–1440; критические обходят паузу |
| POST /push | subscription из PushManager; разрешены известные push-провайдеры |
| DELETE /push | Отключение подписок своего технического аккаунта |
| GET /operators | Список технических ответственных |
| GET /access | access.manage; права/области/состояния без хешей паролей |
| POST /access | Только владелец: отдельный сотрудник с временным паролем |
| PATCH /access/:id | Только владелец: права/область/отзыв доступа/новый временный пароль |
| GET /rules | rules.manage; текущая версия порогов/хранения |
| PATCH /rules | rules.manage; новая версия, проверка допустимых диапазонов |
| GET /audit | access.manage; записи, граница проверки цепочки, архивы |
| GET /audit/archives/:id | access.manage + files.original + pii.read и полная область; checksum и аудит скачивания |
| POST /maintenance/retention | dangerous; только ограниченная очистка по политике |

Общие списки: `page` 1–10000, `limit` 1–100. История: `q, user, from, to, request, session, operation, object, result, version, organization, order=asc`. Организации в Domly отсутствуют; несуществующая организация даёт пустой результат. Сеанс без user возвращает только события без установленного пользователя.

Поддержка, доступ и изменение правил требуют `reason` от 8 символов, `confirm:true`, `operatorPassword`. Для закрытия проблемы дополнительно `fixedVersion`, `verificationNote` от 12 символов и `verificationPassed:true`. Это подтверждение проверки оператором, не автоматически выполненный тест.

Пароли клиента/уборщицы не сбрасываются как обычные пароли: основной вход по коду. Временный пароль применяется к admin/superadmin; после его выдачи старые JWT отзываются через auth_version, а до смены доступны только me/logout/password-change. `POST /api/v1/auth/password/change` после успешной смены завершает сеансы и требует повторный вход.

`POST /api/v1/telemetry/client-events` — отдельный обычный API приложения с его JWT, не технической cookie. Принимает максимум 20 ограниченных сообщений с разрешёнными именами. Параметры экрана/устройства считаются сообщёнными клиентом. Произвольные тела форм, коды, пароли и тексты чатов не сохраняются. Не вставляйте секреты в свободные комментарии: маскирование известных полей и шаблонов не может распознать произвольную неснабжённую подписью строку как пароль.

При недоступной авторизации данные не выдаются. При недоступном источнике состояние не подменяется успешным. Служебных endpoint для произвольных команд, SQL или чтения серверных файлов нет.
