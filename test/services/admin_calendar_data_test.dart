import 'package:flutter_test/flutter_test.dart';
import 'package:domly/utils/admin_calendar_data.dart';
import '../fixtures/admin_calendar_fixture.dart';

void main() {
  test('monthly totals count the order once and each cleaner only their share',
      () {
    final data = AdminCalendarSnapshot(adminCalendarFixture());
    expect(data.ordersOn('2026-11-28').length, 3);
    expect(data.totalArea('2026-11-28'), 510);
    expect(data.dailyArea('a', '2026-11-28'), 230);
    expect(data.dailyArea('b', '2026-11-28'), 200);
    expect(data.unassignedOn('2026-11-28').map((o) => o['id']), ['waiting']);
    expect(
        data.forCleaner('a', '2026-11-28', includeCancelled: true).length, 3);
    expect(data.dailyArea('a', '2026-11-28'), 230,
        reason: 'cancelled area must never consume the daily cap');
  });
  test(
      'completed work consumes area but no longer blocks time; overlapping reservations merge',
      () {
    final data = AdminCalendarSnapshot(adminCalendarFixture()),
        day = '2026-11-28';
    final shift = data.workingDay('a', day)!;
    expect(calendarFreeIntervals(shift, data.forCleaner('a', day), day),
        [(start: 800, end: 1080)]);
    final busy = AdminCalendarVisit({
      'id': 'overlap',
      'service_date': day,
      'start_time': '12:00',
      'estimated_duration_minutes': 180,
      'status': 'assigned'
    }, {
      'cleaner_id': 'a',
      'allocated_area': 10
    });
    expect(
        calendarFreeIntervals(shift, [...data.forCleaner('a', day), busy], day),
        [(start: 900, end: 1080)]);
  });
  test('a previous-day visit remains busy without counting its area twice', () {
    final visit = AdminCalendarVisit({
      'id': 'night',
      'service_date': '2026-11-27',
      'start_time': '18:00',
      'estimated_duration_minutes': 1080,
      'status': 'in_progress',
      'area': 100
    }, {
      'cleaner_id': 'a',
      'allocated_area': 100
    });
    expect(visit.appearsOn('2026-11-28'), isTrue);
    expect(visit.startOn('2026-11-28'), -360);
    expect(visit.endOn('2026-11-28'), 720);
    expect(
        calendarFreeIntervals({'start_time': '08:00', 'end_time': '18:00'},
            [visit], '2026-11-28'),
        [(start: 720, end: 1080)]);
    expect(visit.appearsOn('2026-11-29'), isFalse);
  });
  test('day off and an unapproved week are different', () {
    final data = AdminCalendarSnapshot(adminCalendarFixture());
    expect(data.workingDay('a', '2026-11-29'), isNull);
    expect(data.approvedWeek('a', '2026-11-29'), isTrue);
    expect(data.approvedWeek('c', '2026-11-29'), isFalse);
  });
  test('December calendar keeps ninety minutes around each occupied visit', () {
    final visit = AdminCalendarVisit({
      'id': 'gap',
      'service_date': '2026-12-01',
      'start_time': '11:00',
      'estimated_duration_minutes': 120,
      'status': 'assigned'
    }, {
      'cleaner_id': 'a',
      'allocated_area': 80
    });
    expect(
        calendarFreeIntervals({'start_time': '08:00', 'end_time': '18:00'},
            [visit], '2026-12-01'),
        [(start: 480, end: 570), (start: 870, end: 1080)]);
  });
}
