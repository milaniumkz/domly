import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domly/ui/admin_weekly_workload.dart';
import '../fixtures/admin_calendar_fixture.dart';

void main() {
  testWidgets(
      'weekly schedule fits phone, includes day off and navigates both directions',
      (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AdminWeeklyWorkload(
                    initialDay: DateTime(2026, 11, 28),
                    load: (from, to) async {
                      requests.add('$from/$to');
                      return adminCalendarFixture();
                    })))));
    await tester.pumpAndSettle();
    expect(find.text('График и занятость на неделю'), findsOneWidget);
    expect(find.text('Выходной'), findsWidgets);
    expect(find.textContaining('Смена:'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Следующая неделя'));
    await tester.pumpAndSettle();
    expect(requests.last, '2026-11-30/2026-12-06');
    await tester.tap(find.byTooltip('Предыдущая неделя'));
    await tester.pumpAndSettle();
    expect(requests.last, '2026-11-23/2026-11-29');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
