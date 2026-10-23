import 'package:domly/screens/client/client_home_screen.dart';
import 'package:domly/localization/translation_controller.dart';
import 'package:domly/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ['ru', 'kk']) {
    testWidgets('home instructions fit 320px with enlarged text: $locale', (tester) async {
      await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Variable.ttf'))).load();
      TranslationController.forTesting().debugSetTranslations({}, locale: locale);
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(15), child: CustomerNextCleaningCard(
          onTap: () {}, timeText: 'Выберите дату и время', areaText: '100 м²',
          cleanerName: 'Исполнитель после выбора даты', planName: 'Разовая уборка',
          totalVisits: 4, availableSelections: 4, used: 0, showUsageStats: true,
          onSelectDates: () {}, onDetails: () {}, onCancel: null,
        )))),
      )));
      await tester.pumpAndSettle();
      for (final source in ['Выберите дату и время', 'Исполнитель после выбора даты', 'Разовая уборка']) {
        final text = find.text(source.tr());
        expect(text, findsOneWidget);
        expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse);
      }
      if (locale == 'kk') {
        expect(find.text('Қал.: 4'), findsOneWidget);
        expect(find.text('Пайд.: 0'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  test('Pro summary quantities translate without losing their values', () {
    final controller = TranslationController.forTesting()..debugSetTranslations({}, locale: 'kk');
    expect(controller.translate('Потрачено в этом месяце: 1000 / 20000 ₸'), 'Осы айда жұмсалды: 1000 / 20000 ₸');
    expect(controller.translate('Выбрано 3. После сохранения останется: 9'), 'Таңдалды: 3. Сақтағаннан кейін қалады: 9');
    expect(controller.translate('Восемь раз в месяц'), 'Айына сегіз рет');
    expect(controller.translate('12 на неделе'), '12 апта ішінде');
    expect(controller.translate('25000 ₸/мес'), '25000 ₸/ай');
    expect(controller.translate('От 12000 м² • карьерный бонус 100000 ₸'), '12000 м² бастап • мансаптық бонус 100000 ₸');
    expect(controller.translate('Продажи доп. услуг от 30000 ₸ за неделю • +4000 ₸'), 'Аптасына қосымша қызметтер сатылымы 30000 ₸ бастап • +4000 ₸');
    expect(controller.translate('Заказ №781. Уборка завершена.'), '№781 тапсырыс. Тазалау аяқталды.');
  });
}
