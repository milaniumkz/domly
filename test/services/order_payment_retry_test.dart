import 'package:domly/screens/common/order_payment_retry.dart';
import 'package:domly/services/firestore_data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(find.text('Оплатить бонусами'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
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
