import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domly/ui/admin_booking_calendar.dart';
import '../fixtures/admin_calendar_fixture.dart';

void main() {
  testWidgets(
      'calendar shows separate staff loads, opens the exact job and navigates empty months',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final opened = <String>[];
    final shown = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminBookingCalendar(
                initialDay: DateTime(2026, 11, 28),
                load: (from, to) async => from.startsWith('2026-11')
                    ? adminCalendarFixture()
                    : {
                        ...adminCalendarFixture(),
                        'orders': [],
                        'assignments': [],
                        'workingDays': [],
                        'approvedWeeks': []
                      },
                onShowInOrders: (order) => shown.add('${order['id']}'),
                onOpenOrder: (order) async => opened.add('${order['id']}')))));
    await tester.pumpAndSettle();
    expect(find.text('Ноябрь 2026'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('calendar-order-team-a')), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('230 м²'), findsOneWidget);
    expect(find.text('200 м²'), findsWidgets);
    await tester.ensureVisible(find.byKey(const ValueKey('calendar-order-team-a')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('calendar-order-team-a')), matching: find.byType(Text)).first);
    await tester.pumpAndSettle();
    expect(opened, ['team']);
    expect(find.byKey(const ValueKey('calendar-cleaner-c')), findsNothing);
    final row = find.byKey(const ValueKey('calendar-order-team-a'));
    await tester.ensureVisible(find.descendant(of: row, matching: find.text('Открыть в заказах')));
    await tester.tap(find.descendant(of: row, matching: find.text('Открыть в заказах')));
    await tester.pumpAndSettle();
    expect(shown, ['team']);
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Следующий месяц'));
    await tester.pumpAndSettle();
    expect(find.text('Декабрь 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Предыдущий месяц'));
    await tester.pumpAndSettle();
    expect(find.text('Ноябрь 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'mobile calendar fits a phone and hides optional filters initially',
      (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminBookingCalendar(
                initialDay: DateTime(2026, 11, 28),
                load: (_, __) async => adminCalendarFixture(),
                onOpenOrder: (_) async {}))));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Фильтры'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Мария');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('late month responses cannot overwrite the selected month',
      (tester) async {
    final delayed = <String, Completer<Map<String, dynamic>>>{};
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminBookingCalendar(
                initialDay: DateTime(2026, 11, 28),
                load: (from, to) {
                  if (from.startsWith('2026-11'))
                    return Future.value(adminCalendarFixture());
                  return (delayed[from] = Completer<Map<String, dynamic>>())
                      .future;
                },
                onOpenOrder: (_) async {}))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Следующий месяц'));
    await tester.pump();
    await tester.tap(find.byTooltip('Следующий месяц'));
    await tester.pump();
    delayed['2027-01-01']!.complete({
      ...adminCalendarFixture(),
      'orders': [],
      'assignments': [],
      'workingDays': [],
      'approvedWeeks': []
    });
    await tester.pumpAndSettle();
    delayed['2026-12-01']!.complete(adminCalendarFixture());
    await tester.pumpAndSettle();
    expect(find.text('Январь 2027'), findsOneWidget);
    expect(find.text('Декабрь 2026'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
