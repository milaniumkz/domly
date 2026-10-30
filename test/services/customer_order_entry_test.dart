import 'dart:async';
import 'package:domly/screens/client/orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final focused in [false, true]) {
    testWidgets('order list stays open until cleaning tap, focus=$focused',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final slots = StreamController<List<Map<String, dynamic>>>.broadcast();
      final orders = Stream<List<Map<String, dynamic>>>.value([]);
      final slot = <String, dynamic>{
        'id': 'cleaning-1',
        'orderId': 'cleaning-1',
        'status': 'assigned',
        'scheduledFor': '2039-04-02',
        'time': '18:00 - 20:00',
        'address': 'Тестовый адрес',
        'area': 100
      };
      await tester.pumpWidget(MaterialApp(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
                settings: RouteSettings(
                    arguments: focused ? {'focusOrderId': 'cleaning-1'} : null),
                builder: (_) => OrdersScreen(
                    scheduleSlots: slots.stream,
                    orders: orders,
                    addonGroups: Stream.value([])),
              )));
      await tester.pumpAndSettle();
      slots.add([slot]);
      await tester.pumpAndSettle();
      expect(find.text('Действия по уборке'), findsNothing);
      slots.add([slot]);
      await tester.pumpAndSettle();
      expect(find.text('Действия по уборке'), findsNothing);
      expect(find.text('Тестовый адрес'), findsOneWidget);
      await tester.tap(find.text('Тестовый адрес'));
      await tester.pumpAndSettle();
      expect(find.text('Действия по уборке'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await slots.close();
    });
  }
  testWidgets(
      'proposal notification opens offered services and approval instead of the editor',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final proposal = <String, dynamic>{
      'id': 'cleaning-1',
      'orderId': 'cleaning-1',
      'status': 'pending_customer',
      'cleanerName': 'Анара',
      'amount': 6000,
      'addonsDetailed': [
        {'label': 'Духовка', 'quantity': 2, 'price': 3000}
      ]
    };
    await tester.pumpWidget(MaterialApp(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
              settings: const RouteSettings(
                  arguments: {'focusAddonRequestId': 'cleaning-1'}),
              builder: (_) => OrdersScreen(
                  scheduleSlots: Stream.value([]),
                  orders: Stream.value([]),
                  addonGroups: Stream.value([]),
                  addonRequests: Stream.value([proposal])),
            )));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(
        find.descendant(
            of: sheet, matching: find.text('Согласование доп. услуг')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sheet, matching: find.textContaining('Духовка × 2')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('6000 ₸')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Согласовать')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Отклонить')),
        findsOneWidget);
    expect(find.text('Действия по уборке'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
