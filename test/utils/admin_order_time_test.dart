import 'package:domly/utils/admin_order_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Postgres seconds never become a midnight start', () {
    expect(
        adminOrderTimeText({'time': '10:00:00 - 12:54:00'}), '10:00 - 12:54');
    final row =
        mapAdminOrder({'start_time': '10:00:00', 'end_time': '12:54:00'});
    expect(adminOrderTimeText(row), '10:00 - 12:54');
    expect(row['startTime'], '10:00');
  });
  test('plain clocks, missing clocks and overnight end date', () {
    expect(adminOrderTimeText({'time': '9:05 - 11:30'}), '09:05 - 11:30');
    expect(adminOrderTimeText({}), '—');
    expect(adminClockTime('25:00:00'), '');
    expect(
        adminOrderTimeText({
          'start_time': '18:00:00',
          'end_time': '01:00:00',
          'scheduled_date': '2026-11-08',
          'estimated_duration_minutes': 420
        }),
        '18:00 - 01:00 (2026-11-09)');
  });
}
