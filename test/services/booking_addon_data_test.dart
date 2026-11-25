import 'package:domly/utils/booking_addon_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new paid extras from home reach order creation', () {
    expect(
        bookingAddonIds({
          'newAddonsDetailed': [
            {'id': 'extra'}
          ]
        }),
        ['extra']);
  });
  test('calendar includes both sets without charging duplicate selections', () {
    expect(
        bookingAddonIds({
          'addonsDetailed': [
            {'id': 'prepaid'},
            {'id': 'extra'}
          ],
          'newAddonsDetailed': [
            {'addonId': 'extra'},
            {'id': 'new'}
          ],
        }),
        ['prepaid', 'extra', 'new']);
    expect(bookingAddonIds({}), isEmpty);
  });

  group('unfinished calendar booking', () {
    late Map<String, String> times;
    late Map<String, List<Map<String, dynamic>>> paid;
    late Map<String, List<Map<String, dynamic>>> fresh;
    bool move(String from, String to) => movePendingBookingAddons(
          fromDateKey: from,
          toDateKey: to,
          selectedTimes: times,
          paidByDate: paid,
          newByDate: fresh,
        );
    setUp(() {
      times = {};
      paid = {
        '2026-12-01': [
          {'id': 'prepaid', 'key': 'oven', 'quantity': 2}
        ]
      };
      fresh = {
        '2026-12-01': [
          {'id': 'window', 'key': 'window', 'quantity': 3, 'price': 2000},
          {'id': 'sofa', 'quantity': 1, 'price': 50000, 'separatePayment': true}
        ]
      };
    });
    test('no slots: next date keeps quantities and charges extras only once',
        () {
      final original = fresh['2026-12-01']!.first;
      expect(move('2026-12-01', '2026-12-02'), isTrue);
      expect(paid.keys, ['2026-12-02']);
      expect(fresh.keys, ['2026-12-02']);
      expect(paid['2026-12-02']!.single['quantity'], 2);
      expect(fresh['2026-12-02']!.first['quantity'], 3);
      expect(billableBookingAddonsAmount(fresh.values.expand((rows) => rows)),
          6000);
      expect(
          bookingAddonIds({
            'addonsDetailed': paid['2026-12-02'],
            'newAddonsDetailed': fresh['2026-12-02'],
          }),
          ['prepaid', 'window', 'sofa']);
      fresh['2026-12-02']!.first['quantity'] = 4;
      expect(original['quantity'], 3);
      expect(times, isEmpty);
    });
    test('a scheduled visit is never moved to an additional date', () {
      times['2026-12-01'] = '18:00';
      expect(move('2026-12-01', '2026-12-02'), isFalse);
      expect(paid.keys, ['2026-12-01']);
      expect(fresh.keys, ['2026-12-01']);
      expect(times, {'2026-12-01': '18:00'});
    });
    test('another scheduled date retains its own selections and time', () {
      times['2026-12-02'] = '12:00';
      expect(move('2026-12-01', '2026-12-02'), isFalse);
      expect(fresh.containsKey('2026-12-02'), isFalse);
      expect(times, {'2026-12-02': '12:00'});
    });
    test('an existing date draft is not overwritten by another date', () {
      fresh['2026-12-02'] = [
        {'id': 'fridge', 'quantity': 1}
      ];
      expect(move('2026-12-01', '2026-12-02'), isFalse);
      expect(fresh['2026-12-02']!.single['id'], 'fridge');
      expect(fresh['2026-12-01']!.first['quantity'], 3);
    });
    test('repeated date changes retain extras until a time is chosen', () {
      expect(move('2026-12-01', '2026-12-02'), isTrue);
      expect(move('2026-12-02', '2026-12-03'), isTrue);
      expect(move('2026-12-03', '2026-12-03'), isFalse);
      expect(fresh.keys, ['2026-12-03']);
      expect(fresh['2026-12-03']!.first['quantity'], 3);
      times['2026-12-03'] = '12:00';
      expect(move('2026-12-03', '2026-12-04'), isFalse);
      expect(fresh.containsKey('2026-12-04'), isFalse);
    });
    test('cleared extras do not reappear on the next date', () {
      paid.clear();
      fresh.clear();
      expect(move('2026-12-01', '2026-12-02'), isTrue);
      expect(paid, isEmpty);
      expect(fresh, isEmpty);
    });
  });
}
