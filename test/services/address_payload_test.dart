import 'package:domly/utils/address_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('structured suggestions preserve street and compound house', () {
    expect(
        streetAndHouse({
          'street': 'Кабанбай Батыра',
          'house': '29/2',
          'address': 'ЖК, Астана'
        }),
        {'street': 'Кабанбай Батыра', 'house': '29/2'});
  });
  test('manual address and slash comma variant remain saveable', () {
    expect(streetAndHouse({'address': 'Қабанбай Батыр даңғылы 29/, 2, Астана'}),
        {'street': 'Қабанбай Батыр даңғылы', 'house': '29/2'});
    expect(streetAndHouse({'address': 'Тауелсиздык 38'}),
        {'street': 'Тауелсиздык', 'house': '38'});
  });
}
