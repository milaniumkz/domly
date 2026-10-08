import 'package:domly/utils/promotion_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('any package becomes null and fixed reward is transmitted correctly',
      () {
    final body = promotionRequestBody({
      'title': 'Акция',
      'packageId': '',
      'rewardType': 'bonus_points',
      'rewardMode': 'fixed',
      'rewardAmount': 15000,
      'isActive': false,
      'maxSpendPercent': 50,
      'fullInfo': 'Подробности',
      'homeBannerImageUrl': 'https://domly.kz/photo',
      'features': ['Окна']
    });
    expect(body['packageId'], isNull);
    expect(body['rewardType'], 'fixed');
    expect(body['rewardValue'], 15000);
    expect(body['active'], false);
    expect(body['maxBonusSpendPercent'], 50);
    expect((body['presentation'] as Map)['homeBannerImageUrl'],
        'https://domly.kz/photo');
    expect((body['presentation'] as Map)['features'], ['Окна']);
  });
  test(
      'percent promotion is restored for editing without losing display settings',
      () {
    final promo = mapBackendPromotion({
      'id': 'test',
      'title_ru': 'Процент',
      'reward_type': 'percent',
      'reward_value': '10.00',
      'max_bonus_spend_percent': '50.00',
      'active': false,
      'once_per_customer': true,
      'presentation': {
        'fullInfo': 'Подробно',
        'showBannerTitle': false,
        'rewardTarget': 'all'
      }
    });
    expect(promo['rewardPercent'], 10);
    expect(promo['isActive'], false);
    expect(promo['fullInfo'], 'Подробно');
    expect(promo['packageName'], 'Любой пакет');
    expect(promo['showBannerTitle'], false);
    final body = promotionRequestBody(promo);
    expect(body['rewardType'], 'percent');
    expect(body['rewardValue'], 10);
    expect(body['oncePerCustomer'], true);
  });
}
