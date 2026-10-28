import 'backend_compat.dart';
import '../localization/translation_controller.dart';
import '../ui/domly_ui.dart' show domlyDateText;

DateTime? scheduledCleaningDate(Map<String, dynamic> order) {
  for (final key in ['scheduledFor', 'date', 'scheduledDateKey']) {
    final value = order[key];
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value is Map) {
      final seconds = value['seconds'] ?? value['_seconds'];
      if (seconds is num)
        return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());
    }
  }
  return null;
}

String cleaningDateLabel(Map<String, dynamic> order) {
  final date = scheduledCleaningDate(order);
  return date == null ? 'Дата не выбрана'.tr() : domlyDateText(date);
}

String areaConfirmationStatus(Map<String, dynamic> profile) {
  if (profile['areaVerified'] == true) return 'Подтверждено'.tr();
  if (profile['areaProofSubmitted'] == true) return 'На проверке'.tr();
  return 'Не подтверждена'.tr();
}

/// A paid historical visit must not become a new pending cleaning on the home.
bool isFinishedCleaning(Map<String, dynamic> order) => {
      'completed',
      'cancelled',
      'canceled',
      'rejected'
    }.contains((order['orderStatus'] ?? order['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase());

bool isHomePackageFrozen(Map<String, dynamic> item, {DateTime? now}) {
  final until = DateTime.tryParse((item['freezeUntil'] ?? '').toString());
  return item['status'] == 'frozen' ||
      (until != null && until.isAfter(now ?? DateTime.now()));
}

String homePaymentTitle(Map<String, dynamic> order) {
  final payment = order['latestPaymentStatus'] ?? order['paymentStatus'];
  if (['cancelled', 'rejected', 'failed'].contains(payment))
    return 'Оплата не завершена';
  if (payment == 'paid') return 'Пакет оплачен';
  if (payment == 'invoice_requested') return 'Ожидание оплаты';
  return 'Ожидание счёта';
}

String homePaymentDescription(Map<String, dynamic> order) {
  switch (homePaymentTitle(order)) {
    case 'Оплата не завершена':
      return 'Заказ сохранён. Вы можете выбрать другой способ оплаты.';
    case 'Пакет оплачен':
      return 'Оплата подтверждена';
    case 'Ожидание оплаты':
      return 'Счёт уже выставлен. Статус обновится после оплаты.';
    default:
      return 'Заявка отправлена. Дождитесь выставления счёта.';
  }
}

String homeAmountLabel(int amount) =>
    '${amount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (match) => '${match[1]} ')} ₸';
