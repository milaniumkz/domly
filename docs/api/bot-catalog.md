# DOMLY — API каталога для бота
Версия 1.0 • 19 октября 2026 • Валюта: KZT • Площадь: м²

## Назначение
Бот получает актуальные пакеты, цены, допуслуги и состав услуг из PostgreSQL. Firebase для этого не используется. Запросы только читают данные, не создают покупку и не выставляют счёт. Цены нельзя хранить в инструкциях бота как постоянные: запрашивайте каталог перед предложением клиенту.

## Подключение
Базовый адрес: https://domly.kz/api/v1
Авторизация каждого запроса: X-MoonAI-Token: <INTEGRATION_TOKEN>
Вместо этого допустим Authorization: Bearer <INTEGRATION_TOKEN>. Это отдельный входящий токен DOMLY, а не публичный ключ MooonAI. Настроен в защищённой конфигурации сервера. В документах ключи отсутствуют.
Ответы JSON: {"ok":true,"data":...}. Ошибки: {"ok":false,"code":"...","message":"..."}. Персональные ответы имеют Cache-Control: no-store.

## GET /integrations/moon-ai/catalog
Необязательный query area — положительная площадь до 10000 м². Без area возвращается каталог тарифов без рассчитанных предложений. Пример: /integrations/moon-ai/catalog?area=100

Ответ data:
• currency: KZT; generatedAt: момент формирования; area: переданная площадь или null.
• packages[]: активные пакеты, id, name_ru/name_kk, description_ru/description_kk, months, cleaning_count, base_price, price_per_m2, features, includedServices, quotes.
• includedServices: состав услуг из features.items. Пустое поле означает отсутствие заполненного состава. Не придумывайте услуги, которых нет в данных.
• addonGroups[]: группы допуслуг с названиями, сортировкой и active.
• addons[]: активные услуги, id, group_id, title_ru/title_kk, description_ru/description_kk, hint_ru/hint_kk, pricing_type, price, duration_minutes, paid_separately.
Идентификаторы UUID — внутренние ссылки для следующего запроса. Числа PostgreSQL NUMERIC в тарифах могут приходить строками; рассчитанные суммы quotes приходят числами.

## Стоимость и период
Каждый quotes[] содержит packageId, area, cleaningCount, cleaningsPerMonth, billingPeriodMonths, subtotal, discountRate, discountAmount, referralDiscountPercent, referralDiscountAmount, totalPrice, perCleaningAfterDiscount и addons.
totalPrice — итог за ВЕСЬ период пакета. Историческое поле monthlyPrice содержит ту же общую сумму, несмотря на название. perCleaningPrice — цена до скидки; клиенту для сравнения показывайте perCleaningAfterDiscount.
Для квартальных пакетов выдаются варианты 2, 4, 8 уборок в месяц, то есть 6, 12, 24 за квартал. Тариф берётся из соответствующего месячного пакета, скидка — из выбранного квартального. Ошибку недоступного месячного тарифа нельзя заменять приблизительной ценой.
Например: 12 уборок по 10000 ₸ до скидки, скидка 10% — totalPrice 108000 ₸, perCleaningAfterDiscount 9000 ₸. Пример объясняет формулу и не является действующим прайсом.

## POST /integrations/moon-ai/catalog/quote
Точный расчёт выбранного набора. Content-Type: application/json.
Обязательные поля: packageId (UUID активного пакета), area (число >0, ≤10000).
Необязательные: cleaningsPerMonth (для квартального: 2, 4 или 8), addonsDetailed (массив до 100 услуг: id и quantity, целое 1–100). Повторять одну услугу в массиве нельзя. Для MooonAI Custom API addonsDetailed также может быть строкой с JSON-массивом; при отсутствии услуг передавайте [].
Пример тела, замените UUID значениями из каталога:
{"packageId":"<PACKAGE_UUID>","area":100,"cleaningsPerMonth":4,"addonsDetailed":[{"id":"<ADDON_UUID>","quantity":2}]}
Ответ data содержит currency, totalPrice, perCleaningAfterDiscount и исходные поля расчёта. Это публичная тарифная оценка без персонального customerId и без расходования бонусов. Финальная покупка в приложении применяет персональные условия.

## Единицы допуслуг
per_m2 / per_sqm: price × area × quantity.
per_visit: price × quantity × общее количество уборок.
Остальные pricing_type: price × quantity один раз за пакет.
Итог каждой позиции округляется до целого тенге. Скидка пакета применяется к основной уборке, затем учитывается персональная скидка при реальной покупке. Поле paid_separately — метаданные каталога; для предложения используйте рассчитанные addons и totalPrice, а не собственную формулу бота.

## Ошибки и правила бота
401 unauthorized — неверный токен; 503 integration_not_configured — входящий токен не настроен. Не запрашивать ключ у клиента.
400 invalid_area / area_required — некорректная площадь; invalid_frequency — неверная частота; invalid_addons — неизвестная услуга, повтор или неверное количество; invalid_id — неправильный UUID.
404 package_not_found — пакет выключен либо удалён. Повторно запросить каталог, не использовать старую цену.
При сбое API бот сообщает о невозможности получить точную цену и предлагает приложение/оператора. Запрос каталога не означает выставление счёта или подтверждение оплаты. Интеграция Kaspi и ручное одобрение администратором сохраняются отдельно.
