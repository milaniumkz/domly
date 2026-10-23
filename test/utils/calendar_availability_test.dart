import 'dart:async';
import 'package:domly/utils/calendar_availability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calendar loads four days concurrently, preserves order and excludes failures', () async {
    final pending = List.generate(8, (_) => Completer<List<Map<String, dynamic>>>());
    var started = 0;
    var active = 0;
    var peak = 0;
    final result = loadAvailableCalendarDays(List.generate(8, (i) => '2026-12-0${i + 1}'), loadSlots: (date) async {
      final index = int.parse(date.substring(8)) - 1;
      started++;
      active++;
      if (active > peak) peak = active;
      try { return await pending[index].future; } finally { active--; }
    });
    await Future<void>.delayed(Duration.zero);
    expect(started, 4);
    pending[3].complete([{}]);
    pending[2].completeError(StateError('Backend unavailable'));
    pending[1].complete([]);
    pending[0].complete([{}]);
    await Future<void>.delayed(Duration.zero);
    expect(started, 8);
    for (var i = 7; i >= 4; i--) pending[i].complete([{}]);
    final days = await result;
    expect(peak, 4);
    expect(days.map((d) => d['date']), ['2026-12-01','2026-12-04','2026-12-05','2026-12-06','2026-12-07','2026-12-08']);
  });
  test('booked day matches both PostgreSQL date encodings', () {
    expect(calendarDateKey('2026-12-10T00:00:00.000Z'), '2026-12-10');
    expect(calendarDateKey('2026-12-10'), '2026-12-10');
    expect(calendarDateKey(null), '');
    expect(calendarDateKey('invalid'), '');
  });
}
