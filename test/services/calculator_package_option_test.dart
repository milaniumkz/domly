import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domly/ui/calculator_package_option.dart';

Widget option(
        {required CalculatorPackageQuote load,
        double area = 100,
        int visits = 2,
        VoidCallback? select,
        void Function(Map<String, dynamic>?)? info}) =>
    MaterialApp(
        home: Scaffold(
            body: CalculatorPackageOption(
                package: const {'id': 'basic', 'name': 'Два раза в месяц'},
                area: area,
                visits: visits,
                selected: false,
                loadQuote: load,
                onSelected: select ?? () {},
                onInfo: info ?? (_) {})));

void main() {
  testWidgets(
      'shows authoritative package price and average per visit for profile area',
      (t) async {
    await t.pumpWidget(option(load: (p, a, v) async {
      expect(p['id'], 'basic');
      expect(a, 100);
      expect(v, 2);
      return {'monthlyPrice': 11700, 'cleaningCount': 2};
    }));
    await t.pumpAndSettle();
    expect(find.textContaining('11700 ₸'), findsOneWidget);
    expect(find.textContaining('5850 ₸'), findsOneWidget);
    expect(find.text('Без дополнительных услуг'), findsOneWidget);
    expect(find.textContaining('Стоимость ='), findsNothing);
  });
  testWidgets(
      'information button opens detail action without selecting or purchasing',
      (t) async {
    var selected = 0, opened = 0;
    await t.pumpWidget(option(
        load: (_, a, v) async => {'monthlyPrice': 85000, 'cleaningCount': 1},
        select: () => selected++,
        info: (q) {
          opened++;
          expect(q?['monthlyPrice'], 85000);
        }));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.info_outline));
    expect(opened, 1);
    expect(selected, 0);
    await t.tap(find.text('Два раза в месяц'));
    expect(selected, 1);
  });
  testWidgets(
      'missing profile area does not request a quote or show a fake zero price',
      (t) async {
    var calls = 0;
    await t.pumpWidget(option(
        area: 0,
        load: (_, a, v) async {
          calls++;
          return {};
        }));
    await t.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Укажите площадь в профиле'), findsOneWidget);
    expect(find.textContaining('0 ₸'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });
  testWidgets(
      'area and quarterly visit changes ignore an older in-flight quote',
      (t) async {
    final old = Completer<Map<String, dynamic>>();
    Future<Map<String, dynamic>> load(
            Map<String, dynamic> p, double a, int v) async =>
        a == 100
            ? await old.future
            : {'monthlyPrice': 24000, 'cleaningCount': 12};
    await t.pumpWidget(option(load: load));
    await t.pumpWidget(option(load: load, area: 120, visits: 4));
    await t.pumpAndSettle();
    expect(find.textContaining('24000 ₸'), findsOneWidget);
    old.complete({'monthlyPrice': 999, 'cleaningCount': 2});
    await t.pumpAndSettle();
    expect(find.textContaining('999 ₸'), findsNothing);
    expect(find.textContaining('24000 ₸'), findsOneWidget);
  });
  testWidgets(
      'failed price request can retry without presenting zero as a real price',
      (t) async {
    var attempts = 0;
    await t.pumpWidget(option(load: (_, a, v) async {
      if (++attempts == 1) throw Exception('offline');
      return {'monthlyPrice': 7000, 'cleaningCount': 1};
    }));
    await t.pumpAndSettle();
    expect(find.text('Повторить расчёт'), findsOneWidget);
    expect(find.textContaining('0 ₸'), findsNothing);
    await t.tap(find.text('Повторить расчёт'));
    await t.pumpAndSettle();
    expect(find.text('7000 ₸ — за пакет'), findsOneWidget);
  });
}
