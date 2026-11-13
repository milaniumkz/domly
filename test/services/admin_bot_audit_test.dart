import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domly/ui/admin_bot_audit.dart';

void main() {
  testWidgets('shows the bot, customer, failure and request identity',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AdminBotAudit(
                    loader: (_) async => [
                          {
                            'action': 'bot.moon-ai.order_create',
                            'entity_type': 'order',
                            'entity_id': 'fixture-order',
                            'created_at': '2026-11-13T08:00:00Z',
                            'payload': {
                              'actorKind': 'bot',
                              'customerId': 'fixture-client-id',
                              'result': 'error',
                              'code': 'slot_unavailable',
                              'requestId': 'fixture-request'
                            }
                          }
                        ])))));
    await tester.pumpAndSettle();
    expect(find.text('Бот MooonAI'), findsOneWidget);
    expect(find.textContaining('fixture-client-id'), findsOneWidget);
    expect(find.textContaining('slot_unavailable'), findsOneWidget);
    expect(find.textContaining('fixture-request'), findsOneWidget);
    expect(find.text('Ошибка'), findsOneWidget);
  });

  testWidgets('paginates instead of silently truncating the log',
      (tester) async {
    final queries = <Map<String, String?>>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: SingleChildScrollView(child: AdminBotAudit(loader: (query) async {
      queries.add(Map.of(query));
      if (query['offset'] == '0')
        return List.generate(
            30,
            (i) => {
                  'id': '$i',
                  'action': 'bot.moon-ai.customer',
                  'payload': <String, dynamic>{'actorKind': 'bot'}
                });
      return [
        {
          'action': 'bot.moon-ai.quote',
          'payload': <String, dynamic>{'actorKind': 'bot'}
        }
      ];
    })))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Далее'));
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(queries.last['offset'], '30');
    expect(queries.last['search'], 'MooonAI');
    expect(find.text('Расчёт стоимости'), findsOneWidget);
  });

  testWidgets('network failure remains visible and can be retried',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AdminBotAudit(loader: (_) async {
      if (calls++ == 0) throw StateError('fixture outage');
      return [];
    }))));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить журнал бота.'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Действий бота пока нет.'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('a late response cannot replace a newer search', (tester) async {
    final old = Completer<List<Map<String, dynamic>>>();
    final fresh = Completer<List<Map<String, dynamic>>>();
    Future<List<Map<String, dynamic>>> loader(Map<String, String?> query) =>
        query['search'] == 'new' ? fresh.future : old.future;
    Widget screen(String search) => MaterialApp(
        home: Scaffold(body: AdminBotAudit(search: search, loader: loader)));
    await tester.pumpWidget(screen('old'));
    await tester.pumpWidget(screen('new'));
    await tester.pump(const Duration(milliseconds: 300));
    fresh.complete([
      {
        'action': 'fresh-result',
        'payload': <String, dynamic>{'actorKind': 'bot'}
      }
    ]);
    await tester.pump();
    old.complete([
      {
        'action': 'stale-result',
        'payload': <String, dynamic>{'actorKind': 'bot'}
      }
    ]);
    await tester.pumpAndSettle();
    expect(find.text('fresh-result'), findsOneWidget);
    expect(find.text('stale-result'), findsNothing);
  });
}
