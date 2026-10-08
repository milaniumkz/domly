import 'package:domly/utils/banner_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('banner editor preserves image, metadata, target and inactive state',
      () {
    final body = bannerRequestBody({
      'title': 'Акция',
      'subtitle': 'Кратко',
      'description': 'Подробно',
      'imageUrl': 'https://domly.kz/photo',
      'ctaLabel': 'Пакеты',
      'route': '/client/package-selection',
      'isActive': false
    });
    expect(body['placement'], 'home_top');
    expect(body['imageUrl'], 'https://domly.kz/photo');
    expect(body['subtitleRu'], 'Кратко');
    expect(body['ctaLabelRu'], 'Пакеты');
    expect(body['targetType'], 'route');
    expect(body['targetValue'], '/client/package-selection');
    expect(body['active'], false);
  });
  test('backend banners restore editor fields and customer destinations', () {
    final banner = mapBackendBanner({
      'title_ru': 'Акция',
      'subtitle_ru': 'Кратко',
      'image_url': 'https://domly.kz/photo',
      'cta_label_ru': 'Сайт',
      'target_type': 'external',
      'target_value': 'https://domly.kz',
      'active': false,
      'sort_order': 2
    });
    expect(banner['title'], 'Акция');
    expect(banner['externalUrl'], 'https://domly.kz');
    expect(banner['isActive'], false);
    expect(banner['sortOrder'], 2);
    final body = bannerRequestBody(banner);
    expect(body['imageUrl'], 'https://domly.kz/photo');
    expect(body['targetType'], 'external');
    expect(body['active'], false);
  });
}
