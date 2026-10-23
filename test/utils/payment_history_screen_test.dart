import 'dart:async';
import 'package:domly/screens/client/payment_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'rejected Kaspi invoice stays in history with all other payment states',
      (tester) async {
    const statuses = [
      'rejected',
      'failed',
      'pending',
      'cancelled',
      'paid',
      'refunded'
    ];
    final rows = [
      for (final status in statuses)
        {
          'id': status,
          'paymentId': status,
          'paymentStatus': status,
          'amount': 22000,
          'createdAt': '2026-10-23T06:00:00Z'
        }
    ];
    final controller = StreamController<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
        MaterialApp(home: PaymentHistoryScreen(payments: controller.stream)));
    controller.add(rows);
    await tester.pumpAndSettle();
    expect(find.text('История платежей'), findsOneWidget);
    expect(find.text('История пока пуста'), findsNothing);
    expect(find.text('Отклонено'), findsNWidgets(2));
    expect(find.text('Отменено'), findsOneWidget);
    expect(find.text('Оплачено'), findsOneWidget);
    expect(find.text('Возврат'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(controller.close());
    await tester.pump();
  });
}
