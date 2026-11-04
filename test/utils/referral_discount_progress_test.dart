import 'package:domly/utils/referral_discount_progress.dart';
import 'package:domly/ui/referral_discount_progress_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts paid invitations toward next and maximum discounts', () {
    final data = ReferralDiscountProgress(8, null);
    expect(data.currentDiscount, 3);
    expect(data.remainingNext, 2);
    expect(data.remainingMax, 12);
    expect(data.progress, 0.4);
    expect(ReferralDiscountProgress(0, null).progress, 0);
    for (final count in [20, 25]) {
      final done = ReferralDiscountProgress(count, null);
      expect(done.maxReached, true);
      expect(done.remainingNext, 0);
      expect(done.remainingMax, 0);
    }
  });
  test('configured, duplicate and non-monotonic thresholds remain consistent',
      () {
    final data = ReferralDiscountProgress(5, [
      {'count': 12, 'discount': 15},
      {'count': 3, 'discount': 2},
      {'count': 8, 'discount': 7},
      {'count': 8, 'discount': 10}
    ]);
    expect(data.nextDiscount, 10);
    expect(data.remainingNext, 3);
    expect(data.remainingMax, 7);
    expect(
        ReferralDiscountProgress(5, [
          {'count': 3, 'discount': 10},
          {'count': 20, 'discount': 10}
        ]).maxCount,
        3);
    expect(ReferralDiscountProgress(0, []).maxDiscount, 0);
  });
  testWidgets('both goals stay visible on a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
                body: SingleChildScrollView(
                    child: ReferralDiscountProgressCard(qualifiedCount: 8))))));
    expect(find.text('До следующего уровня (7%): ещё 2 чел.'), findsOneWidget);
    expect(
        find.text('До максимальной скидки (10%): ещё 12 чел.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('maximum replaces the next-level prompt', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home:
            Scaffold(body: ReferralDiscountProgressCard(qualifiedCount: 20))));
    expect(find.text('Максимальная скидка 10% уже получена'), findsOneWidget);
    expect(find.textContaining('До следующего уровня'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
