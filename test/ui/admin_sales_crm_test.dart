import 'package:domly/ui/admin_customer_crm.dart';
import 'package:domly/ui/admin_cancelled_sales.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'CRM stages and private notes save through administrative requests',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final row = <String, dynamic>{
      'id': 'customer-fixture',
      'full_name': 'Клиент CRM',
      'phone': '+77000000000',
      'crm_stage': 'new',
      'crm_revision': 0,
      'notes_count': 1,
      'latest_note': 'Первая заметка'
    };
    var note = <String, dynamic>{
      'id': 'note-fixture',
      'body': 'Первая заметка',
      'revision': 1,
      'author_name': 'Администратор',
      'created_at': '2026-11-17T10:00:00Z'
    };
    final writes = <Map<String, dynamic>>[];
    Future<Map<String, dynamic>> request(String method, String path,
        Map<String, dynamic>? body, Map<String, String?>? query) async {
      if (path.endsWith('/notes') && method == 'GET')
        return {
          'items': [note],
          'total': 1
        };
      if (path.endsWith('/notes/note-fixture') && method == 'PATCH') {
        writes.add(body!);
        note = {...note, 'body': body['body'], 'revision': 2};
        row['latest_note'] = body['body'];
        return note;
      }
      if (method == 'PATCH') {
        writes.add(body!);
        row['crm_stage'] = body['stage'];
        row['crm_revision'] = 1;
        return {'stage': body['stage'], 'revision': 1};
      }
      return {
        'items': [row],
        'total': 1
      };
    }

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AdminCustomerCrm(request: request))));
    await tester.pumpAndSettle();
    expect(find.text('Клиент CRM'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отказался').last);
    await tester.pumpAndSettle();
    expect(writes.first['stage'], 'refused');
    expect(writes.first['revision'], 0);
    await tester.tap(find.text('Заметки (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Видны только администраторам'), findsOneWidget);
    await tester.tap(find.text('Редактировать'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).last, 'Клиент отказался, перезвонить позже');
    await tester.tap(find.text('Сохранить правку'));
    await tester.pumpAndSettle();
    expect(writes.last['revision'], 1);
    expect(writes.last['body'], 'Клиент отказался, перезвонить позже');
    expect(find.text('Клиент отказался, перезвонить позже'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'CRM filters are server-side and date-to includes the full selected day',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final queries = <Map<String, String?>>[];
    Future<Map<String, dynamic>> request(String method, String path,
        Map<String, dynamic>? body, Map<String, String?>? query) async {
      queries.add({...query!});
      return {'items': <dynamic>[], 'total': 0};
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminCustomerCrm(
                request: request,
                filtersExpanded: true,
                dateTo: DateTime(2026, 11, 17)))));
    await tester.pumpAndSettle();
    final end = DateTime.parse(queries.last['dateTo']!).toLocal();
    expect(end.day, 17);
    expect(end.hour, 23);
    expect(end.minute, 59);
    final city = find.widgetWithText(TextField, 'Город');
    await tester.enterText(city, 'Астана');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(queries.last['city'], 'Астана');
    expect(queries.last['offset'], '0');
    await tester.tap(find.text('Сбросить фильтры'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(queries.last['city'], '');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'cancelled sales show bot origin and copy the customer phone, not payer phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final row = <String, dynamic>{
      'id': 'payment-fixture',
      'kind': 'payment',
      'payment_number': 17,
      'customer_name': 'Клиент отмены',
      'customer_phone': '+77001112233',
      'invoice_phone': '+77009998877',
      'created_by': 'bot',
      'amount': 1000,
      'bonus_amount': 50,
      'package_name': 'Квартальный пакет',
      'cancelled_at': '2026-11-17T10:00:00Z',
      'address': {
        'city': 'Астана',
        'street': 'Тестовая',
        'house': '43',
        'apartment': '103',
        'area': 67
      },
      'effects': {'scope': 'addons'},
      'addons': <dynamic>[],
      'payments': <dynamic>[]
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminCancelledSales(
                loader: (_) async => {
                      'items': [row],
                      'total': 1
                    }))));
    await tester.pumpAndSettle();
    expect(find.text('Оформил бот MonAI'), findsOneWidget);
    expect(find.textContaining('103'), findsWidgets);
    expect(find.text('Отменены допуслуги. Оплаченная уборка сохранена.'),
        findsOneWidget);
    await tester.tap(find.text('Скопировать телефон'));
    await tester.pumpAndSettle();
    expect(copied, '+77001112233');
    await tester.tap(find.text('Вся информация'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Номер плательщика Kaspi: +77009998877'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
