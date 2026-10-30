import 'package:flutter_test/flutter_test.dart';
import 'package:domly/utils/booking_addon_data.dart';

void main() {
  test('specialist services never require invoice or bonus spending', () {
    final specialist = {
      'id': 'sofa',
      'price': 50000,
      'quantity': 2,
      'separatePayment': true
    };
    expect(billableBookingAddonsAmount([specialist]), 0);
    expect(
        billableBookingAddonsAmount([
          specialist,
          {'id': 'oven', 'price': 3000, 'quantity': 2}
        ]),
        6000);
    expect(
        bookingAddonIds({
          'newAddonsDetailed': [specialist]
        }),
        ['sofa']);
    for (final alias in ['separate', 'paidSeparately', 'paid_separately']) {
      expect(
          billableBookingAddonsAmount([
            {'price': 50000, alias: true}
          ]),
          0);
    }
  });
}
