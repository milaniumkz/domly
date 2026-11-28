import 'dart:ui' show SemanticsAction;
import 'package:domly/ui/admin_dashboard_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'dashboard keeps three clickable columns at phone widths and larger text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var tapped = -1;
    final semantics = tester.ensureSemantics();

    for (final width in [320.0, 375.0, 430.0, 1200.0]) {
      for (final scale in [1.0, 1.8]) {
        tester.view.physicalSize = Size(width, 1000);
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(
                    size: Size(width, 1000),
                    textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                    body: SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: AdminDashboardMetrics(children: [
                              for (var i = 0; i < 6; i++)
                                AdminDashboardMetricCard(
                                    key: ValueKey(i),
                                    title: i == 0
                                        ? 'Без назначения'
                                        : 'Графики на одобрении',
                                    subtitle: 'Нужно подобрать исполнителя',
                                    value: i == 0 ? '1' : '1234567',
                                    icon: Icons.person_search_outlined,
                                    accent: Colors.orange,
                                    onTap: () => tapped = i),
                            ])))))));
        await tester.pumpAndSettle();
        final first = tester.getRect(find.byKey(const ValueKey(0)));
        final second = tester.getRect(find.byKey(const ValueKey(1)));
        final third = tester.getRect(find.byKey(const ValueKey(2)));
        final next = tester.getRect(find.byKey(const ValueKey(3)));
        expect(first.top, second.top);
        expect(second.top, third.top);
        expect(first.right, lessThan(second.left));
        expect(third.right, lessThanOrEqualTo(width - 19));
        expect(next.top, greaterThan(first.top));
        await tester.tap(find.descendant(
            of: find.byKey(const ValueKey(0)), matching: find.byType(InkWell)));
        expect(tapped, 0);
        expect(tester.getSemantics(find.bySemanticsLabel('Без назначения: 1. Нужно подобрать исполнителя')).getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(tester.takeException(), isNull);
        tapped = -1;
      }
    }
    semantics.dispose();
  });
}
