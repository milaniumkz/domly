import 'package:domly/utils/admin_addon_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editing preserves UUID identity and uses edited active flag', () {
    const id = 'acf78d09-2821-597d-ae83-ac99010c0586';
    expect(adminAddonIdentity({'id': id, 'key': id, 'label': 'Новое название'}),
        id);
    expect(adminAddonIdentity({'key': id}), id);
    expect(adminCatalogActive({'active': true, 'isActive': false}), false);
    expect(adminCatalogActive({'active': false, 'isActive': true}), true);
    expect(adminCatalogActive({'active': false}), false);
  });
  test('legacy description does not populate the detailed editor', () {
    final fields = adminAddonTextFields({'description_ru': 'Состав услуги'});
    expect(fields['description'], 'Состав услуги');
    expect(fields['fullInfo'], '');
  });
  test(
      'distinct multiline fields survive editing and can be cleared independently',
      () {
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
    expect(adminAddonTextPayload(fields)['descriptionRu'],
        payload['descriptionRu']);
    expect(
        adminAddonTextPayload({'price': 100}).containsKey('fullDescriptionRu'),
        false);
  });
  test(
      'quantity and specialist payment use edited flags, independently of pricing',
      () {
    final item = <String, dynamic>{
      'pricingType': 'per_m2',
      'supports_quantity': true,
      'supportsQuantity': false,
      'paidSeparately': true,
      'separatePayment': false,
      'features': ['Пол', 'Пыль']
    };
    final payload = adminAddonOptionPayload(item);
    expect(payload['supportsQuantity'], false);
    expect(payload['paidSeparately'], false);
    expect(payload['features'], ['Пол', 'Пыль']);
    expect(item['pricingType'], 'per_m2');
    expect(
        adminAddonSupportsQuantity({'pricing_type': 'fixed_per_order'}), false);
    expect(adminAddonSupportsQuantity({'pricing_type': 'fixed'}), true);
    expect(
        adminAddonSupportsQuantity(
            {'pricing_type': 'fixed_per_order', 'supports_quantity': true}),
        true);
    expect(adminAddonOptionPayload({'features': []})['features'], isEmpty);
  });
}
