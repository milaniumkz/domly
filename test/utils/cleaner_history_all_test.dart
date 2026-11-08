import 'package:domly/utils/cleaner_order_history.dart';
import 'package:domly/utils/address_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'all history preserves old completed visits, missing dates and equal-date orders',
      () {
    final rows = [
      {'id': 'old', 'status': 'completed', 'completed_at': '2020-01-01'},
      {'id': 'new-a', 'status': 'COMPLETED', 'completedAt': '2026-11-08'},
      {'id': 'new-b', 'orderStatus': 'completed', 'date': '2026-11-08'},
      {'id': 'undated', 'status': 'completed'},
      {'id': 'active', 'status': 'assigned', 'date': '2026-11-08'},
    ];
    expect(cleanerOrderHistory(rows).map((r) => r['id']),
        ['new-b', 'new-a', 'old', 'undated']);
    expect(
        cleanerOrderHistory(rows,
                period: CleanerHistoryPeriod.month, now: DateTime(2026, 11, 9))
            .map((r) => r['id']),
        ['new-b', 'new-a']);
  });
  test('display does not repeat a building address stored as the complex label',
      () {
    expect(
        addressSummary({
          'city': 'Астана',
          'street': 'Тауелсиздик',
          'house': '43',
          'apartment': '103',
          'residentialComplex': " 'Тауелсиздик 43' "
        }),
        'Астана, Тауелсиздик, 43, кв. 103');
    expect(
        addressSummary({
          'city': 'Астана',
          'street': 'Тест',
          'house': '29/2',
          'apartment': '1003',
          'residentialComplex': 'ЖК Парк'
        }),
        'ЖК Парк, Астана, Тест, 29/2, кв. 1003');
  });
}
