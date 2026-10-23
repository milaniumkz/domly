import 'package:domly/ui/domly_ui.dart';
import 'package:domly/theme/app_theme.dart';
import 'package:domly/theme/domly_palette.dart';
import 'package:domly/services/ui_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    UiPreferences.instance.darkMode = false;
  });
  double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
  }

  test('light theme preserves screen colors and transparency', () {
    UiPreferences.instance.darkMode = false;
    for (final color in [
      Colors.white,
      const Color(0xFFF2FAF7),
      const Color(0xFF20382B),
      Colors.transparent
    ]) {
      expect(DomlyPalette.surface(color), color);
      expect(DomlyPalette.foreground(color), color);
      expect(DomlyPalette.border(color), color);
    }
  });
  test(
      'dark pages, cards and text stay consistent and readable across explicit colors',
      () {
    UiPreferences.instance.darkMode = true;
    expect(DomlyPalette.background(Colors.white), DomlyPalette.darkBackground);
    expect(DomlyPalette.surface(Colors.white), DomlyPalette.darkSurface);
    expect(DomlyPalette.surface(const Color(0xFFF2FAF7)).computeLuminance(),
        lessThan(0.06));
    for (final color in [
      const Color(0xFF20382B),
      const Color(0xFF2B4338),
      const Color(0xFF5E7B69)
    ]) {
      expect(contrast(DomlyPalette.foreground(color), DomlyPalette.darkSurface),
          greaterThan(7));
    }
    expect(DomlyPalette.surface(Colors.transparent), Colors.transparent);
    expect(
        DomlyPalette.surface(const Color(0xFFC56F4B)), const Color(0xFFC56F4B));
    expect(DomlyPalette.foreground(Colors.white), Colors.white);
  });
  testWidgets(
      'an already mounted card follows theme changes in both directions',
      (tester) async {
    final mode = ValueNotifier(false);
    await tester.pumpWidget(ValueListenableBuilder<bool>(
        valueListenable: mode,
        child: const DomlyCard(child: Text('DOMLY')),
        builder: (context, dark, child) => MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: Scaffold(body: child))));
    Color cardColor() {
      final container = tester.widget<Container>(find
          .descendant(
              of: find.byType(DomlyCard), matching: find.byType(Container))
          .first);
      return (container.decoration! as BoxDecoration).color!;
    }

    expect(cardColor(), Colors.white);
    UiPreferences.instance.darkMode = true;
    mode.value = true;
    await tester.pumpAndSettle();
    expect(cardColor(), DomlyPalette.darkSurface);
    UiPreferences.instance.darkMode = false;
    mode.value = false;
    await tester.pumpAndSettle();
    expect(cardColor(), Colors.white);
    await tester.pumpWidget(const SizedBox.shrink());
    mode.dispose();
  });
}
