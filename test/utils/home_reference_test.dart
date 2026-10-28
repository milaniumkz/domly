import 'package:domly/ui/customer_home_reference.dart';
import 'package:domly/localization/translation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scene in HomeScene.values) {
    for (final width in [320.0, 393.0]) {
      testWidgets(
          '${scene.name} fits $width with enlarged text and live actions',
          (tester) async {
        TranslationController.forTesting()
            .debugSetTranslations({}, locale: 'ru');
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final actions = <HomeAction>[];
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: MediaQuery(
                    data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.3)),
                    child: SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: CustomerHomeReference(
                                scene: scene,
                                onAction: actions.add,
                                area: '100',
                                amount: '10 000 ₸',
                                total: 4,
                                used: 2,
                                remaining: 2,
                                date: '30 октября, пятница',
                                time: '10:00–14:00',
                                cleanerName: 'Алия',
                                freezeDate: '5 ноября',
                                startedAt: '10:00')))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final buttons = find.byType(OutlinedButton);
        final hasExtra = [HomeScene.searching, HomeScene.assigned, HomeScene.cleaning].contains(scene);
        expect(buttons, findsNWidgets(hasExtra ? 2 : 1));
        await tester.ensureVisible(buttons.first);
        await tester.tap(buttons.first);
        if (hasExtra) {
          await tester.ensureVisible(find.text('Заказать уборку'));
          await tester.tap(find.text('Заказать уборку'));
          expect(actions.last, HomeAction.schedule);
          expect(find.text('Осталось 2 уборки'), findsOneWidget);
        }
        await tester.pumpAndSettle();
        expect(actions, isNotEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('no remaining visits offers a new package instead of scheduling', (tester) async {
    final actions = <HomeAction>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: CustomerHomeReference(scene: HomeScene.searching, total: 4,
        remaining: 0, primaryKey: GlobalKey(), onAction: actions.add)))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Заказать уборку'), findsNothing);
    await tester.ensureVisible(find.text('Выбрать новый пакет'));
    await tester.tap(find.text('Выбрать новый пакет'));
    expect(actions, [HomeAction.packages]);
  });
  testWidgets('progress visibly fills 1,2,4 of 4 segments', (tester) async {
    for (final count in [1, 2, 4]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: HomeVisitProgress(total: 4, value: count))));
      final segments = tester
          .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator))
          .toList();
      expect(segments.length, 4);
      expect(segments.where((s) => s.value == 1).length, count);
      expect(segments.every((s) => s.minHeight == 10), isTrue);
    }
  });
}
