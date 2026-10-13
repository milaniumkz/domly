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
  testWidgets('active invoice and paid order do not offer duplicate payment',
      (tester) async {
    for (final status in ['invoice_requested', 'paid']) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: OrderPaymentRetry(
        data: FirestoreDataService.instance,
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
