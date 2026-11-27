import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domly/ui/admin_cleaner_workload.dart';
import 'package:domly/ui/admin_responsive_layout.dart';

void main() {
  testWidgets(
      'addon detail dialog shows quantity, historical amounts and closes on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CleanerAddonStatistics(row: {
      'addon_count': 5,
      'addon_amount': '1550.02',
      'period_from': '2026-12-01',
      'period_to': '2026-12-02',
      'addons': [
        {
          'title': 'Мытьё окон',
          'quantity': 2,
          'unit_price': 700,
          'amount': 1400,
          'order_number': 42,
          'completed_date': '2026-12-02',
          'team_size': 1
        },
        {
          'title': 'Духовка',
          'quantity': 3,
          'unit_price': 100.01,
          'amount': 150.02,
          'order_number': 43,
          'completed_date': '2026-12-02',
          'team_size': 2
        },
      ],
    }))));
    await tester.tap(find.text('Допуслуг за период: 5'));
    await tester.pumpAndSettle();
    expect(find.text('Выполненные допуслуги'), findsOneWidget);
    expect(find.text('Мытьё окон'), findsOneWidget);
    expect(find.text('Духовка'), findsOneWidget);
    expect(find.text('Заказ №42 · 2026-12-02'), findsOneWidget);
    expect(find.text('Сумма: 150.02 ₸ (доля в команде из 2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(find.text('Выполненные допуслуги'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty addon statistics show zero and no fabricated details',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: CleanerAddonStatistics(
                row: {'addon_count': 0, 'addon_amount': 0, 'addons': []}))));
    await tester.tap(find.text('Допуслуг за период: 0'));
    await tester.pumpAndSettle();
    expect(find.text('За выбранный период выполненных допуслуг нет.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'period statistics fit a phone and distinguish actual hours from missing timestamps',
      (tester) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminCleanerWorkload(
                load: (from, to) async => {
                      'cleaners': [
                        {
                          'id': 'a',
                          'cleaned_area': '389',
                          'actual_minutes': '270',
                          'scheduled_minutes': '305',
                          'missing_time_count': 1
                        }
                      ]
                    },
                builder: (context, totals, picker) => AdminSectionLayout(
                    toolbar: Wrap(children: [
                      SizedBox(width: double.infinity, child: picker)
                    ]),
                    child: Column(children: [
                      Text(actualWorkLabel(totals['a'])),
                      Text(scheduledWorkLabel(totals['a']))
                    ]))))));
    await tester.pumpAndSettle();
    expect(find.text('4 ч 30 мин'), findsOneWidget);
    expect(find.text('5 ч 5 мин'), findsOneWidget);
    expect(scheduledWorkLabel(null), '—');
    expect(scheduledWorkLabel({}), '—');
    expect(find.textContaining('Выполнено за период:'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(actualWorkLabel(null), '—');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
