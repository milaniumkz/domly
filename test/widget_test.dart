import 'dart:async';

import 'package:domly/ui/domly_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'DomlyPrimaryButton blocks double tap while async action is pending',
      (tester) async {
    var callCount = 0;
    final completer = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DomlyPrimaryButton(
            label: 'Отправить',
            onPressed: () async {
              callCount += 1;
              await completer.future;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Отправить'));
    await tester.pump();
    await tester.tap(find.text('Отправить'));
    await tester.pump();

    expect(callCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Отправить'));
    await tester.pump();
    expect(callCount, 2);
  });

  testWidgets('DomlySecondaryButton shows loading and blocks re-entry',
      (tester) async {
    var callCount = 0;
    final completer = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DomlySecondaryButton(
            label: 'Загрузить',
            onPressed: () async {
              callCount += 1;
              await completer.future;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Загрузить'));
    await tester.pump();
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();

    expect(callCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Загрузить'));
    await tester.pump();
    expect(callCount, 2);
  });
}
