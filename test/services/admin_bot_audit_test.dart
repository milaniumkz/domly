import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domly/ui/admin_bot_audit.dart';

Map<String, dynamic> row({String title = 'Расчёт стоимости пакета'}) => {
      'id': 'fixture-event',
      'title': title,
      'createdAt': '2026-11-13T08:00:00Z',
      'resultLabel': 'Выполнено',
      'customer': {
        'id': 'fixture-client',
        'name': 'Клиент теста',
        'phone': 'fixture-phone'
      },
      'amount': '777'
    };
Widget screen(BotAuditLoader loader,
        {String search = '', BotAuditDetailsLoader? details}) =>
    MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AdminBotAudit(
                    search: search, loader: loader, detailsLoader: details))));
void main() {
  testWidgets('Russian action, client and amount replace internal action codes',
      (tester) async {
    await tester.pumpWidget(screen((_) async => [row()]));
    await tester.pumpAndSettle();
    expect(find.text('Расчёт стоимости пакета'), findsOneWidget);
    expect(find.textContaining('Клиент теста'), findsOneWidget);
    expect(find.textContaining('777'), findsOneWidget);
    expect(find.text('Открыть'), findsOneWidget);
    expect(find.textContaining('catalog.quote'), findsNothing);
  });
  testWidgets('opens client, payment, order and cleaner details',
      (tester) async {
    await tester.pumpWidget(screen((_) async => [row()],
        details: (id) async => {
              'event': row(),
              'customer': {
                'name': 'Клиент теста',
                'phone': 'fixture-phone',
                'id': 'fixture-client'
              },
              'payment': {
                'id': 'payment-fixture',
                'amount': 777,
                'bonus_amount': 0,
                'status': 'paid',
                'provider': 'kaspi'
              },
              'order': {
                'id': 'order-fixture',
                'numeric_id': 42,
                'status': 'assigned',
                'start_time': '12:00',
                'end_time': '14:00'
              },
              'cleaner': {'name': 'Исполнитель теста'},
              'detailsAvailable': true
            }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.textContaining('payment-fixture'), findsOneWidget);
    expect(find.textContaining('Исполнитель теста'), findsOneWidget);
    expect(find.textContaining('Оплачен'), findsOneWidget);
    expect(find.textContaining('777'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pagination keeps later records accessible', (tester) async {
    final queries = <Map<String, String?>>[];
    await tester.pumpWidget(screen((query) async {
      queries.add(Map.of(query));
      return query['offset'] == '0'
          ? List.generate(30, (_) => row())
          : [row(title: 'Проверка оплаты')];
    }));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Далее'));
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(queries.last['offset'], '30');
    expect(find.text('Проверка оплаты'), findsOneWidget);
  });
  testWidgets('failed load offers retry', (tester) async {
    var count = 0;
    await tester.pumpWidget(screen((_) async {
      if (count++ == 0) throw StateError('fixture');
      return [];
    }));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить журнал бота.'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Действий бота пока нет.'), findsOneWidget);
  });
  testWidgets('late search response cannot replace the newest query',
      (tester) async {
    final old = Completer<List<Map<String, dynamic>>>(),
        fresh = Completer<List<Map<String, dynamic>>>();
    Future<List<Map<String, dynamic>>> loader(Map<String, String?> query) =>
        query['search'] == 'new' ? fresh.future : old.future;
    await tester.pumpWidget(screen(loader, search: 'old'));
    await tester.pumpWidget(screen(loader, search: 'new'));
    await tester.pump(const Duration(milliseconds: 300));
    fresh.complete([row(title: 'Свежий результат')]);
    await tester.pump();
    old.complete([row(title: 'Старый результат')]);
    await tester.pumpAndSettle();
    expect(find.text('Свежий результат'), findsOneWidget);
    expect(find.text('Старый результат'), findsNothing);
  });
  testWidgets('unbound historical quote does not invent a customer or amount',
      (tester) async {
    final item = {
      'id': 'legacy',
      'title': 'Расчёт стоимости пакета',
      'resultLabel': 'Выполнено'
    };
    await tester.pumpWidget(screen((_) async => [item],
        details: (_) async => {
              'event': item,
              'detailsAvailable': false,
              'note': 'Параметры запроса не сохранялись.'
            }));
    await tester.pumpAndSettle();
    expect(
        find.text('Общее действие, без привязки к клиенту.'), findsOneWidget);
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('восстановить достоверно нельзя'), findsOneWidget);
  });
}
