import 'package:flutter_test/flutter_test.dart';
import 'package:domly/utils/cleaning_time_range.dart';

void main() {
  test('late finish retains time and overnight finish includes its date', () {
    expect(
        cleaningTimeRange('18:00', '22:00',
            date: '2039-02-03', durationMinutes: 240),
        '18:00 - 22:00');
    expect(
        cleaningTimeRange('18:00', '00:41',
            date: '2039-02-03', durationMinutes: 401),
        '18:00 - 00:41 (2039-02-04)');
    expect(cleaningTimeRange('18:00:00', '00:41:00', date: '2039-02-03'),
        '18:00:00 - 00:41:00 (2039-02-04)');
  });
}
