import 'package:domly/services/address_search_service.dart';
import 'package:domly/utils/address_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('complex selection saves the building address, not the complex name',
      () {
    for (final complex in ['ЖК Тестовый', 'Тексеру тұрғын үй кешені']) {
      final suggestion = AddressSuggestion.fromBackend({
        'id': 'building-id',
        'city': 'Астана',
        'residentialComplex': complex,
        'street': 'Тәуелсіздік',
        'house': '29/2'
      });
      expect(suggestion.title, complex);
      expect(suggestion.fullText, contains('29/2'));
      expect(suggestion.selectionText, complex);
      expect(
          streetAndHouse({
            'street': suggestion.street,
            'house': suggestion.house,
            'address': suggestion.addressText
          }),
          {'street': 'Тәуелсіздік', 'house': '29/2'});
      expect(suggestion.placeId, 'building-id');
    }
  });
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
