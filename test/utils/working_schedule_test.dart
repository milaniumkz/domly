import 'package:domly/utils/working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'week editor keeps exact dates and approved daily hours across month boundaries',
      () {
    final days = workScheduleDays('2026-10-26', [
      {
        'date': '2026-11-01',
        'working': true,
        'startTime': '12:00',
        'endTime': '20:00'
      }
    ]);
    expect(days.length, 7);
    expect(days.first['date'], '2026-10-26');
    expect(days.last['date'], '2026-11-01');
    expect(days.last['working'], isTrue);
    expect(days.last['startTime'], '12:00');
    expect(days.last['endTime'], '20:00');
    expect(days.first['working'], isFalse);
  });
  test(
      'wire dates and pending approval are displayed without losing the actual day',
      () {
    expect(workScheduleDay('2026-11-02T00:00:00.000Z'), '2026-11-02');
    expect(workScheduleDateLabel('2026-11-02'), contains('02.11.2026'));
    expect(workScheduleStatus('pending'), 'На одобрении');
    expect(workScheduleStatus('approved'), 'Одобрен');
  });
  test('pending submission is unchanged across ordering and days-off clocks',
      () {
    final saved = workScheduleDays('2026-10-26', []);
    final draft =
        saved.reversed.map((day) => {...day, 'startTime': '09:00'}).toList();
    expect(workScheduleMatches(draft, saved), isTrue);
    draft.first['working'] = true;
    expect(workScheduleMatches(draft, saved), isFalse);
    expect(workScheduleMatches(saved, saved), isTrue);
  });
}
