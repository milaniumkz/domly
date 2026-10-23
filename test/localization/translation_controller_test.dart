import 'package:domly/localization/kazakh_translations.dart';
import 'package:domly/localization/default_translation_sources.dart';
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
        'Код алу',
      );
    });
  });
  test(
      'Kazakh catalog covers all default Russian labels and preserves parameters',
      () {
    for (final source in kDefaultTranslationSources) {
      final normalized = TranslationController.normalizeSource(source);
      if (!RegExp(r'[А-Яа-яЁё]').hasMatch(normalized)) continue;
      final translated = kKazakhTranslations[normalized];
      expect(translated, isNotNull, reason: normalized);
      expect(translated!.trim(), isNotEmpty, reason: normalized);
    }
    for (final entry in kKazakhTranslations.entries) {
      List<String> params(String text) => RegExp(r'\{[^{}]+\}')
          .allMatches(text)
          .map((m) => m.group(0)!)
          .toList()
        ..sort();
      expect(params(entry.value), params(entry.key), reason: entry.key);
    }
  });

  test('paragraphs survive Russian and localized document reads', () {
    final controller = TranslationController.forTesting();
    controller.debugSetTranslations({}, locale: 'ru');
    const body = '1. Оплата\nОплата заказа.\n\n2. Возврат\nУсловия возврата.';
    expect(controller.translate(body), body);
    controller.debugSetTranslations({}, locale: 'kk');
    const kk = '1. Төлем\nТапсырысты төлеу.\n\n2. Қайтару\nҚайтару шарттары.';
    expect(
        TranslationController.localizedValue({
          'bodyLocales': {'kk': kk}
        }, [
          'body'
        ]),
        kk);
    controller.dispose();
  });

  test(
      'catalog fallback translates Russian locale maps and dynamic notification amounts',
      () {
    final controller = TranslationController.forTesting();
    controller.debugSetTranslations({}, locale: 'kk');
    expect(
        TranslationController.localizedValue({
          'nameLocales': {'kk': 'Разовый пакет'}
        }, [
          'name'
        ]),
        'Бір реттік пакет');
    expect(controller.translate('Подтверждённая площадь квартиры: 110 м².'),
        isNot(contains('площадь')));
    expect(controller.translate('Подтверждённая площадь квартиры: 110 м².'),
        contains('110'));
    controller.dispose();
  });
  test('Kazakh values never silently fall back to English sentences', () {
    for (final entry in kKazakhTranslations.entries) {
      if (RegExp(r'[А-Яа-я]').hasMatch(entry.key) &&
          RegExp(r'[A-Za-z]{4}').hasMatch(entry.value)) {
        expect(
            RegExp(r'[А-Яа-яӘәІіҚқҒғҰұҮүӨөҢң]').hasMatch(entry.value), isTrue,
            reason: entry.key);
      }
    }
  });
}
