import 'dart:async';
import 'package:domly/screens/common/package_freeze_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('invalid days stay open; pending request cannot submit twice; success closes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final pending = Completer<void>();
    final calls = <int>[];
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showDialog<bool>(context: context,
        builder: (_) => PackageFreezeDialog(onSubmit: (days) {calls.add(days); return pending.future;})),
        child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('Заморозить'));
    await tester.pump();
    expect(calls, isEmpty);
    expect(find.text('Укажите срок заморозки.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.text('Заморозить'));
    await tester.pump();
    expect(calls, [7]);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(PackageFreezeDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed request keeps input and permits retry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: PackageFreezeDialog(onSubmit: (_) async {
      calls++;
      throw Exception('network unavailable');
    })));
    await tester.tap(find.text('Заморозить'));
    await tester.pumpAndSettle();
    expect(find.byType(PackageFreezeDialog), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '7');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    await tester.tap(find.text('Заморозить'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
