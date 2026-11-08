import 'package:domly/screens/cleaner/cleaner_order_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'profile history opens with all time and exposes an old completed visit',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CleanerOrderHistoryScreen(
            ordersStream: Stream.value([
      {
        'id': 'old-visit',
        'status': 'completed',
        'date': '2020-01-01',
        'address': 'Старый адрес',
        'area': 50,
        'totalDurationMinutes': 80,
        'addonCount': 0
      },
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('Все'), findsOneWidget);
    expect(find.text('Старый адрес'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
