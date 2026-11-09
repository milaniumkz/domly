import 'package:domly/ui/package_consent_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const package = <String, dynamic>{
    'name': 'Уборка после ремонта',
    'importantInfo': 'Условия администратора: только указанный перечень работ.',
    'features': ['Мытьё пола', 'Удаление пыли'],
    'requiresConsent': true,
    'consentVersion': 'terms-version-1',
  };
  testWidgets('terms and scope are visible; only agreement enables checkout', (tester) async {
    String? accepted;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () async { accepted = await showPackageConsentDialog(context, package); }, child: const Text('Открыть')),
    ))));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(find.text(package['importantInfo'] as String), findsOneWidget);
    expect(find.text('• Мытьё пола'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Далее')).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    expect(accepted, 'terms-version-1');
  });
  testWidgets('cancel never approves terms', (tester) async {
    String? accepted = 'initial';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () async { accepted = await showPackageConsentDialog(context, package); }, child: const Text('Открыть')),
    ))));
    await tester.tap(find.text('Открыть'));await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));await tester.pumpAndSettle();
    expect(accepted, isNull);
  });
}
