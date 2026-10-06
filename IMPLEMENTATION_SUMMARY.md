# DOMLY — Полная реализация исправлений

## Выполненные изменения

### 1. ✅ Исправлена оплата - WebView + Backend активация

#### Проблемы найдены:
1. **Оплата проходила, но пакет НЕ активировался** - после закрытия WebView не вызывалась функция подтверждения
2. **Нет loading состояния** - пользователь не понимал что происходит
3. **WebView открывается в браузере** - пользователь покидал приложение

#### Исправления:

**Backend (Cloud Functions):**
- Файл: `functions/index.js`
- Функции `confirmPayment`, `syncPaymentStatus`, `epayWebhook` уже существуют и работают корректно
- Все они вызывают `ensureSubscriptionForOrder()` который активирует пакет
- Проблемы на клиенте - не вызывалось подтверждение

**Flutter клиент:**
- Файл: `lib/services/payment_link_service.dart`
  - ✅ Добавлен WebView внутри приложения (не браузер)
  - ✅ Loading state при открытии оплаты
  - ✅ Обработка успешной оплаты по URL (success/completed/paid)
  - ✅ Callbacks `onPaymentSuccess` и `onPaymentCancelled`
  - ✅ Защита от закрытия во время обработки
  - ✅ WillPopScope для корректной обработки кнопки назад

- Файл: `lib/services/firestore_data_service.dart`
  - ✅ Добавлен метод `confirmPayment()` для вызова Cloud Function

- Файл: `lib/screens/client/calculator_screen.dart`
  - ✅ После WebView вызывается `confirmPayment()`
  - ✅ Показываются статусные сообщения
  - ✅ Обработка ошибок с fallback на webhook

- Файл: `lib/screens/client/package_selection_screen.dart`
  - ✅ После WebView вызывается `confirmPayment()`
  - ✅ Loading states и сообщения

**Результат:**
```
Пользователь нажимает "Оплатить"
  ↓
Показывается "Открываем страницу оплаты..."
  ↓
Открывается WebView внутри приложения
  ↓
Пользователь оплачивает
  ↓
WebView определяет успех по URL
  ↓
Показывается "Подтверждаем оплату..."
  ↓
Вызывается confirmPayment() → backend
  ↓
Backend: 
  - payments/{id}: status='paid'
  - customer_orders/{id}: paymentStatus='paid', orderStatus='pending_assignment'
  - ensureSubscriptionForOrder() → subscriptions/{id}: status='active'
  - applyPaidOrderUserMetrics() → обновляет таймер пользователя
  - applyReferralPaymentBonusInternal() → бонусы за рефералов
  ↓
Показывается "Оплата подтверждена! Пакет активирован."
```

**Idempotency защита:**
- `ensureSubscriptionForOrder()` использует `{merge: true}` - безопасно вызывать повторно
- `applyPaidOrderUserMetrics()` проверяет `monthlyMetricsApplied` - пропускает если уже
- `applyReferralPaymentBonusInternal()` проверяет `bonusStatus` - пропускает если уже
- Webhook может прийти дважды - всё безопасно

---

### 2. ✅ Исправлен Scheduler - формула 1.6 мин/м² + 30 мин

#### Проблемы найдены:
- Старая система использовала диапазоны (30-50м² = 2 часа, 50-75м² = 3 часа)
- Неточный расчёт времени
- Нет буфера

#### Исправления:

**Backend (Cloud Functions):**
- Файл: `functions/index.js`

**Старая функция:**
```javascript
function estimateCleaningDuration(area = 0) {
  if (size >= 30 && size < 50) return 2;
  if (size >= 50 && size < 75) return 3;
  // ... диапазоны
}
```

**Новая функция:**
```javascript
/**
 * Formula: durationMinutes = area * 1.6 + 30
 * Capped at 480 minutes (8 hours)
 */
function estimateCleaningDuration(area = 0) {
  const size = Number(area || 0);
  if (size <= 0) return 2;
  
  const durationMinutes = Math.round(size * 1.6 + 30);
  const cappedMinutes = Math.min(durationMinutes, 480);
  
  return Math.round((cappedMinutes / 60) * 10) / 10;
}

function estimateCleaningDurationMinutes(area = 0) {
  const size = Number(area || 0);
  if (size <= 0) return 120;
  
  const durationMinutes = Math.round(size * 1.6 + 30);
  return Math.min(durationMinutes, 480);
}
```

**Примеры расчёта:**
- 45 м² → 45 * 1.6 + 30 = 102 мин (1.7 часа)
- 60 м² → 60 * 1.6 + 30 = 126 мин (2.1 часа)
- 75 м² → 75 * 1.6 + 30 = 150 мин (2.5 часа)
- 100 м² → 100 * 1.6 + 30 = 190 мин (3.2 часа)

**Обновления:**
- ✅ `buildCandidateTimeSlots()` теперь работает с минутами
- ✅ При создании subscription сохраняется `estimatedDurationMinutes`
- ✅ Обратная совместимость - `estimatedDurationHours` тоже сохраняется

---

### 3. ✅ Админка - управляемый контент

#### Создана система конфигурации:

**Файлы созданы:**
- `lib/services/app_config_service.dart` - сервис для чтения конфигов
- `lib/ui/info_dialog.dart` - универсальный диалог информации
- `functions/scripts/init_app_config.js` - скрипт инициализации

**Коллекции Firestore:**

1. **app_config/main** - общие настройки приложения
```json
{
  "version": "1.0.0",
  "cleaningFormula": {
    "minutesPerSqm": 1.6,
    "bufferMinutes": 30,
    "maxMinutes": 480
  },
  "featuresEnabled": {
    "packages": true,
    "calculator": true,
    "referrals": true
  }
}
```

2. **info_content/{key}** - информация для пакетов, допов, акций
```json
{
  "id": "2x_month",
  "key": "2x_month",
  "title": "2 раза в месяц",
  "shortInfo": "Уборка 2 раза в месяц",
  "fullInfo": "Полное описание...",
  "price": 24000,
  "isActive": true,
  "sortOrder": 1,
  "type": "package",
  "features": ["Мытье полов", "Протирка пыли"]
}
```

3. **referral_config/main** - настройки рефералки
```json
{
  "bonusPerReferral": 2000,
  "milestoneCount": 5,
  "milestoneBonus": 10000,
  "referralLinkGenerationRequiresPackage": false
}
```

4. **area_config/main** - подтверждение площади
```json
{
  "bonusAmount": 3000,
  "title": "Подтверждение площади",
  "buttonText": "Проверить / Подтвердить"
}
```

5. **worker_bonus_config/main** - бонусы работников
```json
{
  "bonusesVisible": true,
  "title": "Бонусы и достижения"
}
```

**Как использовать в коде:**
```dart
// Чтение конфига
final config = await AppConfigService.instance.getReferralConfig();
final bonus = config['bonusPerReferral'] ?? 2000;

// Показ инфо диалога
InfoDialog.showFromConfig(
  context,
  config: infoContentFromFirestore,
);
```

**Запуск инициализации:**
```bash
cd functions
node scripts/init_app_config.js
```

---

### 4. Что ещё нужно сделать (следующие шаги)

Для завершения всех 21 правок необходимо:

#### UI правки:
1. **Пакеты** - исправить названия на `2 раза в месяц`, `4 раза в месяц` и т.д.
2. **Калькулятор** - добавить info кнопки к каждому допу
3. **Профиль** - ФИО и Пол должны открывать "Данные аккаунта"
4. **Рефералка** - сделать все кнопки активными
5. **Удалить медсправку** из верификации
6. **Удалить дублирующую кнопку**
7. **Уменьшить header калькулятора**

#### Backend правки:
8. **order_adjustments** коллекция для допов во время уборки
9. **Проверка доступного времени** при добавлении допов

#### Firestore обновления:
10. Запустить `init_app_config.js`
11. Обновить существующие документы с новой формулой

---

## Полный flow оплаты (исправленный)

```
1. Пользователь выбирает пакет/калькулятор
   ↓
2. Нажимает "Оплатить"
   ↓
3. Показывается PurchaseTermsDialog
   ↓
4. Вызывается createOrderAndInvoice()
   - Создаётся customer_orders/{id} со статусом pending_payment
   - Создаётся payments/{id} со статусом initiated
   - ePay создаёт invoice
   - Возвращается invoiceUrl и orderId
   ↓
5. Показывается "Открываем страницу оплаты..."
   ↓
6. Открывается _PaymentWebView (внутри приложения!)
   - Показывается loader
   - Мониторится URL на success/fail
   - Обрабатываются deep links (domly://)
   ↓
7. Пользователь оплачивает через ePay
   ↓
8. ePay редиректит на success URL
   ↓
9. WebView определяет успех
   - Показывается "Оплата прошла успешно!"
   - Закрывается с result=true
   ↓
10. Вызывается confirmPayment(orderId)
    - Cloud Function: confirmPayment()
    - В транзакции:
      * payments/{id}: status='paid', paidAt, transactionId
      * customer_orders/{id}: paymentStatus='paid', orderStatus='pending_assignment'
    ↓
11. Post-transaction (последовательно):
    a. ensureSubscriptionForOrder()
       - Создаёт/обновляет subscriptions/{id}
       - status: 'active'
       - validFrom, validUntil
       - includedVisits, remainingVisits
    b. applyPaidOrderUserMetrics()
       - Обновляет monthly_spent, tier и т.д.
    c. applyReferralPaymentBonusInternal()
       - Начисляет бонусы рефералам
    ↓
12. Возвращается {ok: true}
    ↓
13. Показывается "Оплата подтверждена! Пакет активирован."
```

**Fallback механизмы:**
- Если WebView закрылся до подтверждения → можно вызвать syncPaymentStatus из Orders
- Если клиент упал → epayWebhook обработает асинхронно
- Если webhook не пришёл → можно вызвать confirmPayment повторно (идемпотентно)

---

## Edge Cases покрыты

✅ **Повторная оплата** - confirmPayment проверяет orderStatus !== 'pending_payment'  
✅ **Двойной webhook** - все функции идемпотентны  
✅ **WebView закрыт до оплаты** - orderId сохраняется, можно продолжить  
✅ **Сеть упала во время оплаты** - webhook придет позже  
✅ **Пользователь убил приложение** - данные в Firestore, webhook обработает  
✅ **Пакет уже активирован** - ensureSubscriptionForOrder с {merge: true}  
✅ **Бонусы начислены дважды** - проверка bonusStatus перед начислением  

---

## Что тестировать вручную

### Payment Flow:
- [ ] Оплатить пакет → проверить что пакет активировался
- [ ] Проверить что subscription создан со status='active'
- [ ] Проверить что validFrom/validUntil выставлены
- [ ] Закрыть WebView до оплаты → попробовать снова
- [ ] Оплатить и сразу закрыть → проверить что webhook сработал
- [ ] Проверить orders_screen → "Check Payment" работает

### Scheduler:
- [ ] Создать заказ 45м² → проверить duration ~102 мин
- [ ] Создать заказ 75м² → проверить duration ~150 мин
- [ ] Проверить что слоты генерируются с новым временем

### Admin Config:
- [ ] Запустить init_app_config.js
- [ ] Проверить что все коллекции созданы
- [ ] Изменить цену в info_content → проверить что обновилось в UI

---

## Известные ограничения

1. **WebView не может гарантированно определить успех оплаты** - ePay не всегда редиректит на понятный URL
   - **Решение:** Есть fallback на webhook + syncPaymentStatus

2. **confirmPayment может вызвать гонку с webhook** - оба обновляют одновременно
   - **Решение:** Firestore transactions + идемпотентность

3. **Старые подписки могут не иметь estimatedDurationMinutes**
   - **Решение:** Fallback на расчёт из area при чтении

---

## Следующие шаги для полной реализации

Осталось реализовать из оригинального запроса:

1. ⏳ Исправить названия пакетов в UI
2. ⏳ Добавить info кнопки к пакетам и допам
3. ⏳ Удалить медсправку (Step 5)
4. ⏳ Удалить дублирующую кнопку
5. ⏳ Исправить рефералку - кнопка генерации сразу
6. ⏳ Исправить профиль - сохранение адреса
7. ⏳ Подтверждение площади с бонусом
8. ⏳ Бонусы работников видны
9. ⏳ Убрать пакеты с главной

Все эти изменения требуют правки UI компонентов и могут быть сделаны после тестирования payment/scheduler fixes.
