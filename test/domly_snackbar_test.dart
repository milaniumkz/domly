import 'package:domly/ui/domly_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showError(
      WidgetTester tester, String title, String? subtitle) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDomlySnackBar(context,
            title: title, subtitle: subtitle, type: DomlySnackBarType.error),
        child: const Text('Show error'),
      ),
    ))));
    await tester.tap(find.text('Show error'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('payment error shows heading once and keeps actionable detail',
      (tester) async {
    await showError(tester, 'Не удалось повторить оплату',
        'Произошла ошибка. Попробуйте позже.');
    expect(find.text('Не удалось повторить оплату'), findsOneWidget);
    expect(find.text('Произошла ошибка. Попробуйте позже.'), findsOneWidget);
    expect(find.textContaining('Не удалось повторить оплату'), findsOneWidget);
  });

  testWidgets(
      'error without detail uses retry guidance instead of repeating heading',
      (tester) async {
    await showError(tester, 'Не удалось выполнить', null);
    expect(find.textContaining('Не удалось выполнить'), findsOneWidget);
    expect(find.text('Попробуйте ещё раз.'), findsOneWidget);
  });

  testWidgets('auth error keeps session guidance and hides technical detail',
      (tester) async {
    await showError(tester, 'Не удалось выполнить', '401 unauthorized');
    expect(find.text('Нужно войти заново'), findsOneWidget);
    expect(find.text('Сессия истекла. Войдите в приложение заново.'),
        findsOneWidget);
    expect(find.textContaining('401'), findsNothing);
  });
}
