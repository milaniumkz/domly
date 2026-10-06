# Moon AI -> DOMLY: статус счета Kaspi

## Endpoint

Тестовый backend:

```http
POST https://api.89-126-200-97.sslip.io/api/v1/payments/moon-ai/kaspi-status
```

Боевой backend после подключения домена:

```http
POST https://api.domly.kz/api/v1/payments/moon-ai/kaspi-status
```

## Авторизация

Один из вариантов:

```http
Authorization: Bearer <MOON_AI_WEBHOOK_TOKEN>
```

или:

```http
X-MoonAI-Token: <MOON_AI_WEBHOOK_TOKEN>
```

## Headers

```http
Content-Type: application/json
Authorization: Bearer <MOON_AI_WEBHOOK_TOKEN>
```

## Body

Обязательные поля:

| Поле | Тип | Описание |
| --- | --- | --- |
| `paymentId` | string | ID платежа DOMLY, который мы передали Moon AI при запросе счета |
| `status` | string | Статус счета |
| `amount` | number | Сумма счета в тенге |
| `phone` | string | Номер телефона Kaspi, на который выставлен счет |
| `dateTime` | string | Дата и время события в ISO 8601 |

Дополнительные поля:

| Поле | Тип | Описание |
| --- | --- | --- |
| `invoiceId` | string | ID счета на стороне Moon AI/Kaspi |
| `eventId` | string | Уникальный ID события для дедупликации |
| `message` | string | Дополнительный комментарий |

Допустимые статусы:

| Moon AI | DOMLY |
| --- | --- |
| `created`, `sent`, `issued`, `invoice_requested`, `invoice_sent` | `invoice_requested` |
| `pending` | `pending` |
| `paid`, `approved`, `success`, `completed`, `confirmed` | `paid` |
| `rejected`, `declined`, `failed`, `error` | `rejected` |
| `cancelled`, `canceled`, `expired` | `cancelled` |

## Пример запроса

```bash
curl -X POST "https://api.89-126-200-97.sslip.io/api/v1/payments/moon-ai/kaspi-status" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <MOON_AI_WEBHOOK_TOKEN>" \
  -d '{
    "paymentId": "12345678-1234-1234-1234-123456789012",
    "invoiceId": "moon-kaspi-000001",
    "eventId": "moon-event-000001",
    "status": "paid",
    "amount": 11500,
    "phone": "+77052597368",
    "dateTime": "2026-09-29T12:30:00+05:00"
  }'
```

## Успешный ответ

```json
{
  "ok": true,
  "data": {
    "accepted": true,
    "paymentId": "12345678-1234-1234-1234-123456789012",
    "status": "paid",
    "amount": 11500,
    "invoicePhone": "+77052597368"
  }
}
```

## Ошибки

```json
{
  "ok": false,
  "code": "payment_not_found",
  "message": "Платёж не найден."
}
```

Возможные ошибки:

| HTTP | Code | Что делать |
| --- | --- | --- |
| 400 | `payment_id_required` | Передать `paymentId` или `invoiceId` |
| 400 | `invalid_amount` | Передать сумму числом |
| 400 | `invalid_datetime` | Передать дату в ISO 8601 |
| 401 | `unauthorized` | Проверить webhook token |
| 404 | `payment_not_found` | Проверить `paymentId` |
| 503 | `integration_not_configured` | На backend не задан `MOON_AI_WEBHOOK_TOKEN` |

