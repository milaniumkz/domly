import 'dart:async';
import 'package:domly/screens/common/customer_rating_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'customer rating submits once while pending and closes on success',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    bool? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      saved = await showCustomerRatingDialog(context,
                          submit: (rating, note) async {
                        calls++;
                        expect(rating, 5);
                        expect(note, 'Комментарий');
                        await pending.future;
                      });
                    },
                    child: const Text('Открыть'))))));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Комментарий');
    await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
    await tester.pump();
    expect(calls, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(saved, true);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets(
      'customer rating can be postponed and completed order remains accessible',
      (tester) async {
    var calls = 0;
    bool? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      saved = await showCustomerRatingDialog(context,
                          submit: (rating, note) async {
                        calls++;
                      });
                    },
                    child: const Text('Открыть'))))));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Позже'));
    await tester.pumpAndSettle();
    expect(saved, false);
    expect(calls, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
