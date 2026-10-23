import 'dart:async';
import 'package:domly/ui/domly_ui.dart';
import 'package:domly/screens/cleaner/cleaner_calendar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'primary action exposes its state and runs only once while pending',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    final done = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DomlyPrimaryButton(
                label: 'Далее',
                onPressed: () async {
                  calls++;
                  await done.future;
                }))));
    final button = find.bySemanticsLabel('Далее');
    expect(
        tester.getSemantics(button),
        matchesSemantics(
            label: 'Далее',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true));
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(calls, 1);
    done.complete();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets(
      'enabled primary button gradient is not masked by transparent paint',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DomlyPrimaryButton(label: 'Продолжить', onPressed: () {}))));
    final decorations = tester
        .widgetList<Ink>(find.byType(Ink))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.gradient != null);
    expect(decorations, isNotEmpty);
    expect(decorations.every((d) => d.color == null), isTrue);
  });
  testWidgets('selected calendar day has a visible gradient', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CleanerCalendarScreen()));
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<Container>(find.byType(Container))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .where((d) =>
            d.gradient != null && d.borderRadius == BorderRadius.circular(14));
    expect(selected, isNotEmpty);
    expect(selected.every((d) => d.color == null), isTrue);
    expect(find.text('${DateTime.now().day}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
