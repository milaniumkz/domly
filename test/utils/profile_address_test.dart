import 'package:domly/utils/profile_address.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reopening a saved complex retains the full building address', () {
    expect(profileAddressText({'residentialComplex': 'Центр Астаны', 'address': 'Кабанбай батыра 29/2'}),
        'Центр Астаны, Кабанбай батыра 29/2');
    expect(profileAddressText({'residentialComplex': 'Центр Астаны', 'address': 'Центр Астаны', 'street': 'Кабанбай батыра', 'house': '29/2'}),
        'Центр Астаны, Кабанбай батыра 29/2');
  });
  test('plain addresses and already combined addresses are not duplicated', () {
    expect(profileAddressText({'address': 'Тауелсиздик 10'}), 'Тауелсиздик 10');
    expect(profileAddressText({'residentialComplex': 'ЖК А', 'address': 'ЖК А, Тауелсиздик 10'}), 'ЖК А, Тауелсиздик 10');
    expect(profileAddressText({}), '');
  });
}
