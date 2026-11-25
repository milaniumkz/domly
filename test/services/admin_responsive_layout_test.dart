import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domly/ui/admin_responsive_layout.dart';
import 'package:domly/ui/admin_customer_crm.dart';

void main() {
  testWidgets('wide groups stack on phones and preserve desktop flex',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [320.0, 375.0, 768.0, 1200.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Padding(
        padding: const EdgeInsets.all(20),
        child: AdminAdaptiveRow(children: [
          const Expanded(
              child: Text('Клиент с длинным именем и подробным адресом')),
          const SizedBox(width: 12),
          const Spacer(),
          FilledButton(
              onPressed: () {}, child: const Text('Открыть подробности')),
        ]),
      ))));
      await tester.pump();
      final text = tester
          .getRect(find.text('Клиент с длинным именем и подробным адресом'));
      final button = tester.getRect(find.byType(FilledButton));
      if (width < 600) {
        expect(button.top, greaterThan(text.bottom));
        expect(button.right, lessThanOrEqualTo(width));
      } else {
        expect(button.left, greaterThan(text.right));
      }
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('expanded toolbar cannot hide the list on a short phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminSectionLayout(
      toolbar: Column(
          children: List.generate(
              20,
              (i) => TextField(
                  decoration: InputDecoration(labelText: 'Фильтр $i')))),
      child:
          ListView(children: const [ListTile(title: Text('Заказ доступен'))]),
    ))));
    await tester.pump();
    expect(tester.getRect(find.text('Заказ доступен')).bottom, lessThan(480));
    expect(tester.takeException(), isNull);
  });
  testWidgets('form fields and save remain reachable above phone keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(375, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    var saved = false;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => AdminFormDialog(
                                title: const Text('Редактирование'),
                                content: SizedBox(
                                    width: 520,
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: List.generate(
                                            15,
                                            (i) => TextField(
                                                decoration: InputDecoration(
                                                    labelText: 'Поле $i'))))),
                                actions: [
                                  FilledButton(
                                      onPressed: () => saved = true,
                                      child: const Text('Сохранить'))
                                ],
                              )),
                      child: const Text('Открыть')),
                ))));
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Сохранить')).bottom, lessThan(400));
    await tester.tap(find.text('Сохранить'));
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'CRM filters scroll without hiding clients and notes fit the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      height: 440,
      child: AdminCustomerCrm(
        filtersExpanded: true,
        request: (method, path, body, query) async => path.endsWith('/notes')
            ? {'items': [], 'total': 0}
            : {
                'items': [
                  {
                    'id': 'fixture',
                    'full_name': 'Тестовая Клиентка Длинная Фамилия',
                    'phone': '+77000000000'
                  }
                ],
                'total': 1
              },
        cardBuilder: (_, row, index) => const Text('Карточка клиента'),
      ),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Карточка клиента'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Hide the expanded filters before opening a record, as a person would.
    final crm = tester.widget<AdminCustomerCrm>(find.byType(AdminCustomerCrm));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminCustomerCrm(
      request: crm.request,
      cardBuilder: crm.cardBuilder,
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Заметки (0)'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Добавить заметку')).bottom, lessThan(400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
