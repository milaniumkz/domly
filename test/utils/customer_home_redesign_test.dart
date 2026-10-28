import 'package:domly/ui/customer_home_card.dart';
import 'package:domly/utils/customer_home_state.dart';
import 'package:domly/localization/translation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payment state distinguishes invoice, failure and payment', () {
    expect(homePaymentTitle({'paymentStatus': 'pending_invoice'}),
        'Ожидание счёта');
    expect(homePaymentTitle({'paymentStatus': 'invoice_requested'}),
        'Ожидание оплаты');
    expect(homePaymentTitle({'paymentStatus': 'paid'}), 'Пакет оплачен');
    for (final value in ['failed', 'cancelled', 'rejected']) {
      expect(
          homePaymentTitle({
            'paymentStatus': 'pending_invoice',
            'latestPaymentStatus': value
          }),
          'Оплата не завершена');
    }
  });
  test('freeze ends at its actual deadline', () {
    final now = DateTime(2026, 10, 28);
    expect(
        isHomePackageFrozen({'freezeUntil': '2026-11-05'}, now: now), isTrue);
    expect(
        isHomePackageFrozen({'freezeUntil': '2026-10-27'}, now: now), isFalse);
    expect(isHomePackageFrozen({}, now: now), isFalse);
  });
  for (final width in [320.0, 393.0, 768.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('card fits $width at text scale $scale; actions retained',
          (tester) async {
        TranslationController.forTesting()
            .debugSetTranslations({}, locale: 'ru');
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <String>[];
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                    body: SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(15),
                            child: CustomerHomeCard(
                                title: 'Запланируйте уборку',
                                status: 'Пакет оплачен',
                                description:
                                    'Исполнителя назначим после выбора даты',
                                metadata: const ['100 м²', 'Осталось: 4'],
                                planName: 'Квартальный пакет',
                                total: 12,
                                used: 2,
                                primaryLabel: 'Выбрать дату и время',
                                onPrimary: () => calls.add('schedule'),
                                onDetails: () => calls.add('details'),
                                onCancel: () => calls.add('cancel'))))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in ['Выбрать дату и время', 'Детали', 'Отменить']) {
          await tester.ensureVisible(find.text(label));
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }
        expect(calls, ['schedule', 'details', 'cancel']);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
