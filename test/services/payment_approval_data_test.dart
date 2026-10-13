import 'package:flutter_test/flutter_test.dart';
import 'package:domly/utils/payment_approval_data.dart';

void main() {
  test('payment confirmation labels distinguish manual and integration', () {
    expect(paymentApprovalLabel({'approvalSource': 'manual', 'status': 'paid'}),
        'Платёж одобрен вручную');
    expect(
        paymentApprovalLabel({'approvalSource': 'moon_ai', 'status': 'paid'}),
        'Платёж проведён через интеграцию MooonAI / Kaspi');
    expect(
        paymentApprovalLabel(
            {'status': 'invoice_requested', 'invoiceIntegration': true}),
        'Счёт через интеграцию MooonAI / Kaspi');
    expect(paymentApprovalLabel({'status': 'paid'}),
        'Источник подтверждения не указан');
    expect(
        paymentApprovalLabel({'status': 'pending'}), 'Ожидает подтверждения');
  });
  test('invoice and matching review statuses are explicit', () {
    expect(paymentApprovalLabel({'integrationStatus': 'invoice_sent'}),
        'Счёт выставлен через интеграцию MooonAI / Kaspi');
    expect(paymentApprovalLabel({'integrationStatus': 'rejected'}),
        'Интеграция: отказ или ошибка');
    expect(paymentApprovalLabel({'integrationStatus': 'cancelled'}),
        'Интеграция: счёт отменён или истёк');
    expect(
        paymentApprovalLabel({
          'integrationReview': {'reason': 'ambiguous'}
        }),
        'Интеграция: нужна ручная проверка');
  });
  test('manual confirmation remains available after integration errors', () {
    for (final status in [
      'pending',
      'invoice_requested',
      'rejected',
      'failed'
    ]) {
      expect(paymentNeedsManualReview({'status': status}), isTrue);
    }
    for (final status in ['paid', 'cancelled', 'refunded']) {
      expect(paymentNeedsManualReview({'status': status}), isFalse);
    }
  });
}
