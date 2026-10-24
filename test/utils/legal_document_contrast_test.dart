import 'package:domly/screens/common/legal_document_screen.dart';
import 'package:domly/screens/client/payment_terms_screen.dart';
import 'package:domly/localization/translation_controller.dart';
import 'package:domly/services/auth_service.dart';
import 'package:domly/services/ui_preferences.dart';
import 'package:domly/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
}

void main() {
  testWidgets('payment terms translate paragraphs and retain dark contrast', (tester) async {
    TranslationController.forTesting().debugSetTranslations({}, locale: 'kk');
    UiPreferences.instance.darkMode = true;
    addTearDown(() { UiPreferences.instance.darkMode = false; TranslationController.forTesting().debugSetTranslations({}, locale: 'ru'); });
    await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: const PaymentTermsScreen()));
    await tester.pumpAndSettle();
    const source = 'После успешной оплаты пользователь возвращается в раздел заказов приложения.';
    expect(find.text(source.tr()), findsOneWidget);
    expect(find.text(source), findsNothing);
    final card = tester.widgetList<Container>(find.byType(Container)).firstWhere((w) => w.decoration is BoxDecoration);
    final background = (card.decoration! as BoxDecoration).color!;
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      if (text.style?.color != null) expect(contrast(text.style!.color!, background), greaterThanOrEqualTo(4.5), reason: text.data);
    }
  });
  for (final dark in [false, true]) {
    for (final privacy in [false, true]) {
      testWidgets(
          '${privacy ? 'privacy' : 'offer'} readable in ${dark ? 'dark' : 'light'} theme',
          (tester) async {
        AuthService.temporarySessionUidListenable.value = 'legal-test';
        UiPreferences.instance.darkMode = dark;
        addTearDown(() {
          AuthService.temporarySessionUidListenable.value = null;
          UiPreferences.instance.darkMode = false;
        });
        tester.view.physicalSize = const Size(320, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          home: privacy
              ? LegalDocumentScreen.privacy()
              : LegalDocumentScreen.offer(),
        ));
        await tester.pumpAndSettle();
        final card = tester
            .widgetList<Container>(find.byType(Container))
            .firstWhere((widget) => widget.decoration is BoxDecoration);
        final background = (card.decoration! as BoxDecoration).color!;
        final textColors = [
          ...tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.style?.color),
          ...tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .map((w) => w.style?.color),
        ].whereType<Color>().toList();
        expect(textColors.length, greaterThanOrEqualTo(10));
        for (final color in textColors) {
          expect(contrast(color, background), greaterThanOrEqualTo(4.5));
        }
        expect(tester.takeException(), isNull);
        await tester.drag(
            find.byType(SingleChildScrollView), const Offset(0, -1600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scroll = tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
        scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final lastParagraph = find.byWidgetPredicate((widget) => widget is SelectableText && (widget.data ?? '').contains('Email:'));
        expect(lastParagraph, findsOneWidget);
        expect(tester.getBottomRight(lastParagraph).dy, lessThanOrEqualTo(852));
        final offset = scroll.controller!.offset;
        await tester.pump(const Duration(seconds: 31));
        expect(scroll.controller!.offset, offset, reason: 'background updates must not reset document reading');
      });
    }
  }
}
