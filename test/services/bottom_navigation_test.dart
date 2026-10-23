import 'package:domly/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:domly/localization/translation_controller.dart';
import 'package:flutter/rendering.dart';
import 'package:domly/ui/domly_ui.dart';
import 'package:domly/ui/tutorial_targets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final cleaner in [false, true]) {
    testWidgets('Kazakh navigation labels fit 320px: $cleaner', (tester) async {
      await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Variable.ttf'))).load();
      SharedPreferences.setMockInitialValues({});
      TranslationController.forTesting().debugSetTranslations({}, locale: 'kk');
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => TranslationController.forTesting().debugSetTranslations({}, locale: 'ru'));
      await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme,home: MediaQuery(
        data: const MediaQueryData(size: Size(320,900),textScaler: TextScaler.linear(1.3)),
        child: Scaffold(bottomNavigationBar: cleaner ? DomlyCleanerBottomNav(currentIndex: 0) : DomlyClientBottomNav(currentIndex: 0)),
      )));
      await tester.pumpAndSettle();
      for (final element in find.byType(RichText).evaluate()) {
        expect((element.renderObject! as RenderParagraph).didExceedMaxLines, isFalse,
            reason: (element.widget as RichText).text.toPlainText());
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final cleaner in [false, true]) {
    testWidgets('${cleaner ? 'Pro' : 'customer'} menu survives push and back',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final navigator = GlobalKey<NavigatorState>();
      Widget screen(int index) => DomlyShell(
            showBackButton: false,
            bottomNavigationBar: cleaner
                ? DomlyCleanerBottomNav(currentIndex: index)
                : DomlyClientBottomNav(currentIndex: index),
            child: const SizedBox.expand(),
          );
      await tester
          .pumpWidget(MaterialApp(navigatorKey: navigator, home: screen(0)));
      await tester.pumpAndSettle();
      final target = cleaner
          ? DomlyTutorialTargets.cleanerBottomNav[4]
          : DomlyTutorialTargets.clientBottomNav[4];
      final rootKey = DomlyTutorialTargets.resolveNavigationTarget(target, '/');
      expect(rootKey?.currentContext, isNotNull);
      for (var i = 0; i < 3; i++) {
        navigator.currentState!.push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/details'),
          builder: (_) => screen(2),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Главная'), findsOneWidget);
        expect(find.text('Профиль'), findsOneWidget);
        final detailKey =
            DomlyTutorialTargets.resolveNavigationTarget(target, '/details');
        expect(detailKey, isNot(same(rootKey)));
        expect(detailKey?.currentContext, isNotNull);
        showDialog<void>(
          context: detailKey!.currentContext!,
          builder: (_) => const AlertDialog(content: Text('Обучение')),
        );
        await tester.pumpAndSettle();
        expect(DomlyTutorialTargets.resolveNavigationTarget(target, '/details'),
            same(detailKey));
        expect(detailKey.currentContext, isNotNull);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Главная'), findsOneWidget);
        expect(find.text('Профиль'), findsOneWidget);
        expect(rootKey?.currentContext, isNotNull);
      }
      navigator.currentState!.pushReplacement(MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/replacement'),
        builder: (_) => screen(1),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Главная'), findsOneWidget);
      expect(find.text('Профиль'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
