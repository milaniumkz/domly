# Маршруты помощника Domly

С 19.10.2026 автоматические обращения после регистрации или незавершённой оплаты направляются в WhatsApp/WABA через REST API MooonAI. Срок — 30 минут, как в существующих правилах. Сообщения не дублируются в два мессенджера и не попадают в чат приложения.

Подключённый агент: организация `4649`, агент `6875`; WhatsApp — канал `7813`, WABA — канал `7787`. Одобренный WABA-шаблон для начала диалога: `215` (`moonai_universal_ru`, язык `ru`). Актуальность подключения и модерации проверена чтением API 19.10.2026 без отправки тестовых сообщений клиентам.

Для существующего активного диалога выбирается последний WhatsApp/WABA-диалог именно этого номера. В WhatsApp и открытом 24-часовом окне WABA отправляется приветственное сообщение через native `/threads/{id}/messages`. За пределами окна WABA отправляется одобренный шаблон; для нового клиента шаблон начинает диалог в WABA. MooonAI ставит агента на паузу после системного сообщения от менеджера, поэтому после нашей отправки ранее активный агент включается через `/status`. После ответа клиента агент общается в этом мессенджере. Диалоги с заранее установленной паузой менеджера и `settings.whatsappOptOut` не обходятся.

Настройки сервера:

- `MOON_AI_REST_API_KEY` — общий REST API-ключ, хранится в защищённой конфигурации, не в репозитории.
- `MOON_AI_ORGANIZATION_ID`, `MOON_AI_AGENT_ID` — организация и агент.
- `MOON_AI_WABA_CHANNEL_ID`, `MOON_AI_WABA_TEMPLATE_ID` — канал и одобренный шаблон.

Существующие `MOON_AI_CHANNEL_URL`, `MOON_AI_CHANNEL_API_KEY` и `MOON_AI_WEBHOOK_TOKEN` продолжают обслуживать помощника приложения и служебное выставление счетов Kaspi. REST-ключ и ключ API-канала различаются. Изменения конфигурации передаются RSA-OAEP/AES-GCM через workflow Configure Moon AI; частичное обновление сохраняет остальные ключи.

В приложении помощник отвечает только на сообщение пользователя. Для этого используются отдельные внешние треды `assistant:<chat UUID>` и одно ожидаемое обращение из очереди. Повторные callback-события дедуплицируются. Незапрошенные сообщения, старые proactive API-треды и ответы без ожидаемого запроса не сохраняются и не создают push. Установки без номера телефона не запускают автоматическое приветствие: WhatsApp не позволяет определить контакт по факту установки приложения. Гость может сам написать помощнику внутри приложения.

Ошибка подготовки внешнего сообщения не переключает доставку обратно в приложение. Безопасные ошибки чтения повторяются с задержкой; неопределённая отправка не повторяется автоматически во избежание дублей. Технические результаты доступны в `moon_ai_outbox` (`state`, `failure_code`, `provider_thread_id`, `payload.messengerDelivery`), без публикации текста и телефона в логах.

Документация: приложенный владельцем MoonAI API.pdf, методы 1.2/1.3 и 2.1/2.3/2.4; [API-канал](https://docs.mooonai.com/channels/api_channel/) и [WhatsApp Business](https://docs.mooonai.com/channels/whatsapp_business/). Метод 4.1 `/triggers` 19.10.2026 возвращает ошибку сериализации ObjectId (422) после создания объекта; поэтому он не используется. Созданные технические напоминания удалены из отдельного тестового чата. Метод 2.1 проверен там же: HTTP 200, без сообщений реальным клиентам.

## Authentication codes

`OTP_PROVIDER=greenapi` sends only fixed six-digit login-code messages through Green API. Configure `GREEN_API_INSTANCE_ID` and `GREEN_API_TOKEN` securely on the server. Bot followups select only `whatsapp_business` (WABA) threads; grey `whatsapp` threads are ignored. Green API credentials are never used by the bot or invoice integration. An `idMessage` receipt confirms API acceptance, not delivery to the recipient. Existing on-screen OTP display remains enabled until explicitly disabled.
