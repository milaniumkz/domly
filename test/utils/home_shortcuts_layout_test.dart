import 'package:domly/ui/customer_home_reference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [320.0, 430.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
          'home shortcuts share height at width $width and text scale $scale',
          (tester) async {
        final tapped = <HomeAction>[];
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Center(
          child: SizedBox(
              width: width,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: HomeReferenceShortcuts(onAction: tapped.add),
              )),
        ))));
        final addons = find.ancestor(
            of: find.text('Калькулятор'),
            matching: find.byType(InkWell));
        final referral = find.ancestor(
            of: find.text('Пригласить друга'), matching: find.byType(InkWell));
        expect(tester.getSize(addons).height, tester.getSize(referral).height);
        await tester.tap(addons);
        await tester.tap(referral);
        expect(tapped, [HomeAction.calculator, HomeAction.referral]);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
