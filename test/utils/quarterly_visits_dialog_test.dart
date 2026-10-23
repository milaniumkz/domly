import 'package:domly/localization/translation_controller.dart';
import 'package:domly/theme/app_theme.dart';
import 'package:domly/ui/quarterly_visits_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final locale in ['ru', 'kk']) {
      testWidgets(
          'quarterly menu readable and selectable: $locale ${dark ? 'dark' : 'light'}',
          (tester) async {
        final translations = TranslationController.forTesting()
          ..debugSetTranslations({}, locale: locale);
        int? result;
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showQuarterlyVisitsDialog(context,
                          selectedVisits: 4);
                    },
                    child: const Text('open')))));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        final texts = tester.widgetList<Text>(find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(Text)));
        for (final text in texts) {
          final foreground = text.style!.color!,
              background = dialog.backgroundColor!;
          final a = foreground.computeLuminance(),
              b = background.computeLuminance();
          final contrast = ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
          expect(contrast, greaterThan(7), reason: text.data);
          if (locale == 'kk') expect(text.data, isNot(contains('убор')));
        }
        expect(find.byIcon(Icons.check), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('quarterly_visits_2')));
        await tester.pumpAndSettle();
        expect(result, 2);
        await tester.pumpWidget(const SizedBox.shrink());
        translations.dispose();
      });
    }
  }
}
