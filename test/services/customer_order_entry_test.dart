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
}
