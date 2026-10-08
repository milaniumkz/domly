import 'dart:async';
import 'package:domly/app/app_flavor.dart';
import 'package:domly/ui/first_run_tutorial.dart';
import 'package:domly/ui/tutorial_targets.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:domly/ui/domly_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Pro tutorial shows route-owned menu targets without skipping',
      (tester) async {
    bool? shown;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
              onPressed: () async {
                shown = await DomlyFirstRunTutorial.show(context,
                    flavor: AppFlavor.pro);
              },
              child: const Text('Start'))),
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const DomlyShell(
              bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 0),
              child: SizedBox.expand())),
    ));
    await tester.tap(find.text('Start'));
    for (final title in ['Главная', 'Новые заказы', 'Календарь']) {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(title), findsWidgets);
      expect(find.byKey(const ValueKey('tutorial-highlight')), findsOneWidget);
      if (title == 'Календарь') {
        await tester.tap(find.text('Пропустить'));
      } else {
        await tester.tap(find.text('Далее'));
      }
    }
    await tester.pumpAndSettle();
    expect(shown, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('Version 6 retries old completion flags and stays user-specific',
      () async {
    SharedPreferences.setMockInitialValues({
      'domly_first_run_tutorial_customer_user-a_v5': true,
    });
    expect(
        await DomlyFirstRunTutorial.wasShown(
            flavor: AppFlavor.customer, userId: 'user-a'),
        isFalse);
    await DomlyFirstRunTutorial.markShown(
        flavor: AppFlavor.customer, userId: 'user-a');
    expect(
        await DomlyFirstRunTutorial.wasShown(
            flavor: AppFlavor.customer, userId: 'user-a'),
        isTrue);
    expect(
        await DomlyFirstRunTutorial.wasShown(
            flavor: AppFlavor.customer, userId: 'user-b'),
        isFalse);
    expect(
        await DomlyFirstRunTutorial.wasShown(
            flavor: AppFlavor.pro, userId: 'user-a'),
        isFalse);
  });

  testWidgets(
      'banner tutorial follows the visible banner inside a narrow web frame',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var homeBuilds = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
              onPressed: () {
                unawaited(DomlyFirstRunTutorial.show(context,
                    flavor: AppFlavor.customer));
              },
              child: const Text('Start'))),
      onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (context) {
            if (settings.name == '/client/training-order') {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => Navigator.of(context).pop());
              return const SizedBox();
            }
            homeBuilds++;
            return Scaffold(
                body: Center(
                    child: SizedBox(
                        width: 400,
                        child: Column(children: [
                          const SizedBox(height: 100),
                          SizedBox(
                              key: DomlyTutorialTargets.clientInfoBanner,
                              height: 130,
                              width: 400),
                          SizedBox(
                              key: DomlyTutorialTargets.clientOrderButton,
                              height: 45,
                              width: 400),
                          SizedBox(
                              key: DomlyTutorialTargets.clientPrelaunchButton,
                              height: 45,
                              width: 400),
                        ]))));
          }),
    ));
    await tester.tap(find.text('Start'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Далее'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Далее'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Важная информация'), findsOneWidget);
    final banner =
        tester.getRect(find.byKey(DomlyTutorialTargets.clientInfoBanner));
    final highlight =
        tester.getRect(find.byKey(const ValueKey('tutorial-highlight')));
    expect(highlight, banner.inflate(6));
    expect(homeBuilds, 1);
    await tester.tap(find.text('Пропустить'));
    await tester.pumpAndSettle();
  });
}
