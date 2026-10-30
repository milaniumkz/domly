import 'package:domly/ui/customer_package_balances.dart';
import 'package:domly/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final amounts in [
    [20, 4],
    [2, 8]
  ]) {
    testWidgets('both paid packages remain visible: ${amounts.join('+')}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final opened = <String>[];
      var buys = 0;
      final packages = [
        for (var i = 0; i < 2; i++)
          {
            'id': 'package-$i',
            'status': 'active',
            'paymentStatus': 'paid',
            'packageName': 'Пакет ${amounts[i]}',
            'availableCleanings': amounts[i],
            'totalCleanings': amounts[i],
            'address': 'Астана, Тестовая улица, 10'
          }
      ];
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CustomerPackageBalances(
                      packages: packages,
                      onOpen: (package) => opened.add(package['id'] as String),
                      onBuy: () => buys++)))));
      await tester.pumpAndSettle();
      expect(find.text('Общий остаток: ${amounts[0] + amounts[1]} уборок'),
          findsOneWidget);
      for (var i = 0; i < 2; i++) {
        expect(find.text('Пакет ${amounts[i]}'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('package-balance-package-$i')));
      }
      expect(opened, ['package-0', 'package-1']);
      await tester.tap(find.text('Купить ещё пакет'));
      await tester.pump();
      expect(buys, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
