import 'dart:async';
import 'dart:convert';
import 'package:domly/ui/cleaner_work_schedule.dart';
import 'package:domly/utils/working_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'submission disables immediately, survives reopening, and enables only after editing',
      (tester) async {
    final response = Completer<Map<String, dynamic>>();
    var sends = 0;
    Map<String, dynamic>? saved;
    Future<Map<String, dynamic>> load() async => {
          'today': '2026-10-30',
          'currentWeekStart': '2026-10-26',
          'nextWeekStart': '2026-11-02',
          'requests': [if (saved != null) saved],
        };
    Future<Map<String, dynamic>> send(Map<String, dynamic> body) {
      sends++;
      saved = {
        'id': 'request',
        'week_start': body['weekStart'],
        'status': 'pending',
        'days': jsonDecode(jsonEncode(body['days']))
      };
      return response.future;
    }

    Widget app(Key key) => MaterialApp(
        home: Scaffold(
            body: CleanerWorkScheduleSheet(
                key: key, loadSchedule: load, submitSchedule: send)));
    await tester.pumpWidget(app(const ValueKey(1)));
    await tester.pumpAndSettle();
    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNotNull);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(sends, 1);
    expect(button().onPressed, isNull);
    response.complete(saved!);
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);
    await tester.pumpWidget(app(const ValueKey(2)));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);
    expect(sends, 1);
    expect(workScheduleDays('2026-11-02', saved!['days']).first['working'],
        isFalse);
  });
}
