import 'package:domly/localization/translation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranslationController', () {
    test('normalizes source and generates stable keys', () {
      final keyA = TranslationController.translationKey('Заказать   уборку');
      final keyB = TranslationController.translationKey('Заказать уборку');

      expect(
        TranslationController.normalizeSource('  Заказать   уборку  '),
        'Заказать уборку',
      );
      expect(keyA, keyB);
    });

    test('uses locale translation, falls back to ru, and applies params', () {
      final controller = TranslationController.forTesting();
      controller.debugSetTranslations(
        {
          'Код отправлен на номер {phone}': {
            'ru': 'Код отправлен на номер {phone}',
            'kk': '{phone} нөміріне код жіберілді',
          },
          'Получить код': {
            'ru': 'Получить код',
            'en': 'Get code',
          },
        },
        locale: 'kk',
      );

      expect(
        controller.translate(
          'Код отправлен на номер {phone}',
          params: {'phone': '+7 700 000-00-00'},
        ),
        '+7 700 000-00-00 нөміріне код жіберілді',
      );
      expect(
        controller.translate('Получить код'),
        'Получить код',
      );
    });
  });
}
