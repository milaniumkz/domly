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
}
