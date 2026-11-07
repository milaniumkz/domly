import 'package:domly/ui/admin_area_plan.dart';
import 'package:domly/utils/admin_area_check_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('approved bot evidence is a document even without a local file ID', () {
    final row = mapAdminAreaCheck({
      'id': 'q',
      'status': 'approved',
      'bot_document_url': 'https://example.com/bot.jpg',
      'areaTechnicalPlanUrl': 'https://example.com/bot.jpg',
      'uploaded_document_url': 'https://example.com/uploaded.jpg'
    });
    expect(row['status'], 'resolved');
    expect(row['type'], 'area_mismatch');
    expect(areaPlanUrls(row),
        ['https://example.com/bot.jpg', 'https://example.com/uploaded.jpg']);
    expect(
        areaPlanUrls({
          'documentUrl': 'javascript:alert(1)',
          'photoUrls': [
            'storage-error://test',
            'https://user:pass@example.com/a'
          ]
        }),
        isEmpty);
  });
  testWidgets(
      'approved request displays a plan and viewer controls at phone width',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<String>? viewed;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AdminAreaPlan(report: {
      'status': 'approved',
      'bot_document_url': 'https://example.com/bot.jpg'
    }, onView: (urls) => viewed = urls)))));
    await tester.pump();
    expect(find.text('Техплан квартиры'), findsOneWidget);
    expect(find.text('Техплан, проверенный ботом'), findsOneWidget);
    expect(find.text('Открыть оригинал'), findsOneWidget);
    await tester.tap(find.text('Увеличить'));
    expect(viewed, ['https://example.com/bot.jpg']);
    expect(tester.takeException(), isNull);
  });
}
