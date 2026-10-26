import 'package:domly/utils/admin_addon_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy description does not populate the detailed editor', () {
    final fields = adminAddonTextFields({'description_ru': 'Состав услуги'});
    expect(fields['description'], 'Состав услуги');
    expect(fields['fullInfo'], '');
  });
  test('distinct multiline fields survive editing and can be cleared independently', () {
    final fields = adminAddonTextFields({
      'description_ru': 'Описание\nВторой абзац',
      'full_description_ru': 'Условия\n• Первый пункт',
      'description_kk': 'Сипаттама',
      'full_description_kk': 'Шарттар',
    });
    final payload = adminAddonTextPayload(fields);
    expect(payload['descriptionRu'], 'Описание\nВторой абзац');
    expect(payload['fullDescriptionRu'], 'Условия\n• Первый пункт');
    expect(payload['fullDescriptionKk'], 'Шарттар');
    fields['fullInfo'] = '';
    expect(adminAddonTextPayload(fields)['fullDescriptionRu'], '');
    expect(adminAddonTextPayload(fields)['descriptionRu'], payload['descriptionRu']);
    expect(adminAddonTextPayload({'price': 100}).containsKey('fullDescriptionRu'), false);
  });
}
