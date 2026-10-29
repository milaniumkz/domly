import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domly/ui/cleaner_availability_switch.dart';

void main() {
  testWidgets('availability waits for server and blocks duplicate toggles', (tester) async {
    final response = Completer<void>();
    final values = <bool>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CleanerAvailabilitySwitch(
      online: true,
      onChanged: (value) { values.add(value); return response.future; },
    ))));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(values, [false]);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    response.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('Офлайн'), findsOneWidget);
  });
  testWidgets('failed save retains confirmed availability', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CleanerAvailabilitySwitch(
      online: false,
      onChanged: (_) async { throw Exception('offline'); },
    ))));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
