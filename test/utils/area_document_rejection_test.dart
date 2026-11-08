import 'package:domly/ui/area_document_rejection.dart';
import 'package:domly/utils/notification_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejected-plan push opens document upload for the request address', () {
    final route = notificationDestination(
        {'targetType': 'area_verification', 'targetId': 'address-2'},
        cleaner: false)!;
    expect(route.route, '/client/area-confirmation');
    expect(route.arguments,
        {'addressId': 'address-2', 'forceTechPlanPrompt': true});
  });
  testWidgets(
      'rejection requires a reason and returns it without controller lifecycle errors',
      (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showAreaDocumentRejection(context);
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), '  План нечитаемый  ');
    await tester.pump();
    await tester.tap(find.text('Отклонить и уведомить'));
    await tester.pumpAndSettle();
    expect(result, 'План нечитаемый');
    expect(tester.takeException(), isNull);
  });
}
