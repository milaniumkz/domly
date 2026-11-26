import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domly/ui/admin_cleaner_workload.dart';
import 'package:domly/ui/admin_responsive_layout.dart';

void main() {
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
