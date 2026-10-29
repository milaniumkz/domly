import 'package:domly/ui/customer_progress_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rules = [
    {
      'tier': 'A',
      'labelRu': 'Начальный',
      'minMonthlySpent': 0,
      'maxMonthlySpent': 250000,
      'discountPercent': 0
    },
    {
      'tier': 'B',
      'labelRu': 'Постоянный',
      'minMonthlySpent': 250000,
      'maxMonthlySpent': 600000,
      'discountPercent': 7
    },
    {
      'tier': 'C',
      'labelRu': 'Высший',
      'minMonthlySpent': 600000,
      'maxMonthlySpent': null,
      'discountPercent': 12
    },
  ];
  testWidgets(
      'info lists configured statuses and thresholds rather than fixed defaults',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: CustomerProgressInfo(profile: {
      'tier': 'A',
      'monthly_spent': 100000,
      'customer_tier_rules': rules,
    })))));
    expect(find.text('Начальный'), findsOneWidget);
    expect(find.text('Постоянный'), findsOneWidget);
    expect(find.text('Высший'), findsOneWidget);
    expect(find.text('Расходы за месяц: от 250 000 ₸'), findsOneWidget);
    expect(find.text('Скидка: 7%'), findsOneWidget);
    expect(
        find.text('До следующего статуса осталось: 150 000 ₸'), findsOneWidget);
    expect(find.text('Ваш текущий статус'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('top tier shows maximum status with no misleading next target',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: CustomerProgressInfo(profile: {
      'tier': 'C',
      'monthly_spent': 700000,
      'customer_tier_rules': rules,
    })))));
    expect(find.text('Вы достигли максимального статуса.'), findsOneWidget);
    expect(
        find.textContaining('До следующего статуса осталось:'), findsNothing);
  });
}
