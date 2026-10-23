import 'package:domly/screens/cleaner/cleaner_checklist_screen.dart';
import 'package:domly/ui/domly_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('checklist has one back action and a direct-link fallback', (tester) async {
    await tester.pumpWidget(MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings.name == '/' ? const RouteSettings(name: '/cleaner/checklist') : settings,
        builder: (_) => settings.name == '/cleaner/orders'
          ? const Scaffold(body: Text('Orders destination'))
          : const DomlyShell(showBackButton: false, child: CleanerChecklistBackButton()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Orders destination'), findsOneWidget);
  });
}
