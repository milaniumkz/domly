import 'package:domly/screens/common/kaspi_invoice_request_dialog.dart';
import 'package:domly/screens/common/order_payment_retry.dart';
import 'package:domly/services/firestore_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Kaspi preview shows zero after full bonus spend and restores balance on uncheck', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showKaspiInvoiceRequestOptionsDialog(context,
        bonusBalance: 65500, maxBonusToSpend: 65500, paymentAmount: 65500, initialUseBonus: true),
      child: const Text('Open'),
    )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Бонусов на балансе: 65500 ₸'), findsOneWidget);
    expect(find.text('Бонусов останется после оплаты: 0 ₸'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(find.text('Бонусов останется после оплаты: 65500 ₸'), findsOneWidget);
  });
  testWidgets('saved unpaid order without a created invoice can retry payment', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OrderPaymentRetry(
      data: FirestoreDataService.instance,
      loadBonusOptions: () async => {'balance': 4000, 'limit': 4000},
      order: {'id': 'order', 'orderStatus': 'pending_payment', 'payableAmount': 4000},
    ))));
    expect(find.text('Попробовать снова'), findsOneWidget);
    expect(find.text('Оплата не завершена. Выберите способ оплаты.'), findsOneWidget);
    await tester.tap(find.text('Попробовать снова'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Оплатить бонусами'), findsOneWidget);
    expect(find.text('Kaspi.kz'), findsOneWidget);
    expect(find.text('Онлайн-платёж'), findsOneWidget);
  });
  testWidgets('cancelled invoice offers online payment or a new Kaspi number',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OrderPaymentRetry(
      data: FirestoreDataService.instance,
      loadBonusOptions: () async => {'balance': 0, 'limit': 0},
      order: {
        'id': 'order',
        'orderStatus': 'pending_payment',
        'latestPaymentStatus': 'cancelled',
        'payableAmount': 43
      },
    ))));
    expect(find.text('Попробовать снова'), findsOneWidget);
    await tester.tap(find.text('Попробовать снова'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Онлайн-платёж'), findsOneWidget);
    expect(find.text('Kaspi.kz'), findsOneWidget);
    await tester.tap(find.text('Kaspi.kz'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField), findsOneWidget);
  });
  testWidgets('retry exposes full bonus payment when saved policy permits 100 percent', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OrderPaymentRetry(
      data: FirestoreDataService.instance,
      loadBonusOptions: () async => {'balance': 10000, 'limit': 4000},
      order: {'id': 'order', 'orderStatus': 'pending_payment', 'latestPaymentStatus': 'pending', 'payableAmount': 4000},
    ))));
    await tester.tap(find.text('Попробовать снова'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Оплатить бонусами: доступно 4000 ₸'), findsOneWidget);
    expect(find.text('Бонусов останется после оплаты: 10000 ₸'), findsOneWidget);
    expect(find.text('Оплатить бонусами'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(find.text('Бонусов на балансе: 10000 ₸'), findsOneWidget);
    expect(find.text('Бонусов останется после оплаты: 6000 ₸'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('retry shows retained bonuses and the exact new invoice amount', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: OrderPaymentRetry(
      data: FirestoreDataService.instance,
      loadBonusOptions: () async => {'balance': 1000, 'limit': 1000},
      order: {'id': 'order', 'orderStatus': 'pending_payment',
        'latestPaymentStatus': 'cancelled', 'payableAmount': 4000, 'bonusSpent': 2000},
    ))));
    await tester.tap(find.text('Попробовать снова'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Уже оплачено бонусами: 2000 ₸'), findsOneWidget);
    expect(find.text('Сумма нового счёта: 4000 ₸'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(find.text('Сумма нового счёта: 3000 ₸'), findsOneWidget);
    expect(find.text('Уже оплачено бонусами: 2000 ₸'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('active invoice and paid order do not offer duplicate payment',
      (tester) async {
    for (final status in ['invoice_requested', 'paid']) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: OrderPaymentRetry(
        data: FirestoreDataService.instance,
      loadBonusOptions: () async => {'balance': 0, 'limit': 0},
        order: {
          'id': 'order',
          'orderStatus': 'pending_payment',
          'latestPaymentStatus': status
        },
      ))));
      expect(find.text('Попробовать снова'), findsNothing);
    }
  });
}
