import 'package:domly/screens/common/legal_document_screen.dart';
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
      });
    }
  }
}
