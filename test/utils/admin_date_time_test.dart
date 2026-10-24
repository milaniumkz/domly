import 'package:domly/utils/admin_date_time.dart';
import 'package:domly/utils/backend_compat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('REST timestamps display the same date as legacy timestamps', () {
    final date = DateTime.utc(2026, 10, 24, 10, 5);
    final expected = formatAdminDateTime(Timestamp.fromDate(date));
    expect(expected, isNot('—'));
    expect(formatAdminDateTime('2026-10-24T10:05:00.000Z'), expected);
    expect(formatAdminDateTime(date), expected);
  });
  test('missing or invalid dates stay absent instead of becoming January 1', () {
    for (final value in [null, '', 'invalid', 0]) {
      expect(formatAdminDateTime(value), '—');
    }
  });
}
