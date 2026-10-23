import 'package:domly/localization/translation_controller.dart';
import 'package:domly/screens/cleaner/cleaner_verification_screen.dart';
import 'package:domly/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ['ru', 'kk']) {
    testWidgets('upload action fits on one line at 320px: $locale',
        (tester) async {
      final loader = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/Roboto-Variable.ttf'));
      await loader.load();
      final translations = TranslationController.forTesting()
        ..debugSetTranslations({}, locale: locale);
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
              body: Padding(
                  padding: const EdgeInsets.all(20),
                  child: CleanerVerificationDocumentTile(
                      title: 'Шаг 2: Фото с удостоверением',
                      uploaded: false,
                      onUpload: () => tapped = true)))));
      await tester.pumpAndSettle();
      final label = find.text('Загрузить'.tr());
      final paragraph = tester.renderObject<RenderParagraph>(label);
      final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: 'Загрузить'.tr().length));
      // Fallback fonts can have different ascenders on the same visual line.
      final top = boxes.map((b) => b.top).reduce((a, b) => a > b ? a : b);
      final bottom = boxes.map((b) => b.bottom).reduce((a, b) => a < b ? a : b);
      expect(top, lessThan(bottom),
          reason: 'All glyphs occupy one visual line');
      expect(tester.takeException(), isNull);
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      translations.dispose();
    });
  }
}
