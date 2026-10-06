String orderDisplayId(Map<String, dynamic>? data, {String fallback = '—'}) {
  String safeFallback() {
    final raw = fallback.trim();
    if (RegExp(r'^\d+$').hasMatch(raw)) {
      return raw;
    }
    return '—';
  }

  if (data == null) {
    return safeFallback();
  }

  String? fromValue(dynamic value) {
    if (value is num && value > 0) {
      return value.toInt().toString();
    }
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) {
      return null;
    }
    if (RegExp(r'^\d+$').hasMatch(raw)) {
      return raw;
    }
    return null;
  }

  for (final key in const [
    'displayOrderId',
    'orderDisplayId',
    'orderNumber',
    'customerOrderNumber',
    'sourceOrderNumber',
  ]) {
    final resolved = fromValue(data[key]);
    if (resolved != null) {
      return resolved;
    }
  }

  for (final key in const [
    'id',
    'orderId',
    'customerOrderId',
    'sourceOrderId',
  ]) {
    final resolved = fromValue(data[key]);
    if (resolved != null) {
      return resolved;
    }
  }

  return safeFallback();
}

String orderStatusLabel(String status, {String fallback = 'Ожидание'}) {
  switch (status.trim().toLowerCase()) {
    case 'created':
      return 'Создан';
    case 'pending':
    case 'pending_assignment':
      return 'Ожидание назначения';
    case 'pending_payment':
      return 'Ожидает оплату';
    case 'assigned':
      return 'Назначен';
    case 'confirmed':
    case 'accepted':
    case 'scheduled_confirmed':
      return 'Подтверждено';
    case 'start_pending':
      return 'Ожидает старт';
    case 'in_progress':
    case 'started':
    case 'cleaning':
      return 'В процессе';
    case 'completed':
      return 'Завершено';
    case 'canceled':
    case 'cancelled':
      return 'Отменено';
    case 'offer_pending':
    case 'scheduled_pending_confirmation':
      return 'Предложение активно';
    case 'reassignment_needed':
      return 'Нужно переназначение';
    case 'invoice_requested':
      return 'Счёт на KASPI.KZ';
    case 'pending_invoice':
      return 'Ожидает счёт';
    case 'initiated':
      return 'Нужен номер KASPI.KZ';
    case 'paid':
    case 'success':
      return 'Оплачено';
    case 'failed':
      return 'Ошибка оплаты';
    case 'refunded':
      return 'Возврат';
    default:
      return status.trim().isEmpty ? fallback : status;
  }
}

String paymentStatusLabel(String status, {String fallback = 'Ожидание'}) {
  switch (status.trim().toLowerCase()) {
    case 'paid':
    case 'success':
      return 'Оплачено';
    case 'initiated':
      return 'Нужен номер KASPI.KZ';
    case 'invoice_requested':
      return 'Счёт на KASPI.KZ';
    case 'pending_invoice':
      return 'Ожидает счёт';
    case 'pending':
      return 'Ожидание оплаты';
    case 'failed':
      return 'Ошибка оплаты';
    case 'canceled':
    case 'cancelled':
      return 'Отменено';
    case 'refunded':
      return 'Возврат';
    default:
      return status.trim().isEmpty ? fallback : status;
  }
}
