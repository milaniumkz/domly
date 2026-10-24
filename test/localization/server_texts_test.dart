import 'package:flutter/material.dart';
import 'package:domly/theme/domly_palette.dart';
import 'package:domly/localization/translation_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'live catalogue changes once, preserves amounts and retains last good texts offline',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const source = 'Сумма нового счёта: {amount} ₸';
    var value = 'К оплате сейчас: {amount} ₸';
    var offline = false;
    Future<List<Map<String, dynamic>>> load() async {
      if (offline) throw Exception('offline');
      return [
        {
          'key': TranslationController.translationKey(source),
          'source': source,
          'ru': value
        }
      ];
    }

    final c = TranslationController(preferences: prefs, loadRows: load);
    await c.init();
    var events = 0;
    c.addListener(() => events++);
    expect(c.translate(source, params: {'amount': '4000'}),
        'К оплате сейчас: 4000 ₸');
    await c.refresh();
    expect(events, 0);
    value = 'Новый счёт: {amount} ₸';
    await c.refresh();
    expect(events, 1);
    offline = true;
    await c.refresh();
    expect(events, 1);
    c.dispose();
    final restored = TranslationController(preferences: prefs, loadRows: load);
    await restored.init();
    expect(restored.translate(source, params: {'amount': '5500'}),
        'Новый счёт: 5500 ₸');
    restored.dispose();
  });
  testWidgets(
      'same-locale edit updates customer and Pro labels without losing form state',
      (tester) async {
    final c = TranslationController.forTesting();
    c.debugSetTranslations({
      'Заказать уборку': {'ru': 'Заказать уборку'},
      'Принять': {'ru': 'Принять'}
    });
    await tester.pumpWidget(MaterialApp(
        home: TranslationScope(controller: c, child: const _OpenForm())));
    await tester.enterText(find.byType(TextField), 'Сохранить мои данные');
    c.debugSetTranslations({
      'Заказать уборку': {'ru': 'Оформить уборку'},
      'Принять': {'ru': 'Взять заказ'}
    });
    await tester.pump();
    expect(find.text('Оформить уборку'), findsOneWidget);
    expect(find.text('Взять заказ'), findsOneWidget);
    expect(find.text('Сохранить мои данные'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  test('rejects removed, renamed or extra parameters; allows reordering', () {
    expect(
        TranslationController.validParameters(
            '{amount} ₸ за {count}', '{count}: {amount} ₸'),
        isTrue);
    for (final text in [
      'Оплатить',
      '{total} ₸ за {count}',
      '{amount} {count} {other}'
    ]) {
      expect(
          TranslationController.validParameters('{amount} ₸ за {count}', text),
          isFalse);
    }
  });
}

class _OpenForm extends StatefulWidget {
  const _OpenForm();
  @override
  State<_OpenForm> createState() => _OpenFormState();
}

class _OpenFormState extends State<_OpenForm> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    DomlyPalette.watch(context);
    return Scaffold(
        body: Column(children: [
      Text('Заказать уборку'.tr()),
      Text('Принять'.tr()),
      TextField(controller: input)
    ]));
  }
}
