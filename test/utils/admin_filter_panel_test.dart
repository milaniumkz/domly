import 'package:domly/ui/admin_filter_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness extends StatefulWidget {
  const _Harness({this.onBuild});
  final VoidCallback? onBuild;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final expanded = ValueNotifier<bool>(false);
  String status = 'Все';
  @override
  void dispose() {
    expanded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild?.call();
    return Scaffold(
        body: SingleChildScrollView(
            child: Column(children: [
      ValueListenableBuilder<bool>(
        valueListenable: expanded,
        child: const Text('Общие даты'),
        builder: (_, open, child) => AdminFilterPanel(
            expanded: open,
            activeCount: status == 'Все' ? 0 : 1,
            onChanged: (value) => expanded.value = value,
            child: child!),
      ),
      TextButton(onPressed: () {}, child: const Text('Добавить запись')),
      ValueListenableBuilder<bool>(
        valueListenable: expanded,
        child: DropdownButton<String>(
            value: status,
            items: const [
              DropdownMenuItem(value: 'Все', child: Text('Все')),
              DropdownMenuItem(value: 'Оплачено', child: Text('Оплачено')),
            ],
            onChanged: (value) => setState(() => status = value!)),
        builder: (_, open, child) =>
            AdminFilterContents(expanded: open, child: child!),
      ),
      const Text('Список записей'),
    ])));
  }
}

void main() {
  testWidgets(
      'one toggle hides all filter groups, retains selections and never hides actions',
      (tester) async {
    var builds = 0;
    await tester
        .pumpWidget(MaterialApp(home: _Harness(onBuild: () => builds++)));
    expect(find.text('Общие даты'), findsNothing);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('Добавить запись'), findsOneWidget);
    await tester.tap(find.text('Фильтры'));
    await tester.pumpAndSettle();
    expect(find.text('Общие даты'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(builds, 1,
        reason: 'Expanding filters must not rebuild the data screen');
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Оплачено').last);
    await tester.pumpAndSettle();
    expect(find.text('(1)'), findsOneWidget);
    final beforeToggle = builds;
    await tester.tap(find.text('Скрыть фильтры'));
    await tester.pumpAndSettle();
    expect(find.text('Оплачено'), findsNothing);
    expect(find.text('(1)'), findsOneWidget);
    expect(find.text('Добавить запись'), findsOneWidget);
    await tester.tap(find.text('Фильтры'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .value,
        'Оплачено');
    expect(builds, beforeToggle);
    expect(tester.takeException(), isNull);
  });
  testWidgets('hidden controls cannot receive keyboard focus', (tester) async {
    final node = FocusNode();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminFilterContents(
                expanded: false, child: TextField(focusNode: node)))));
    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isFalse);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminFilterContents(
                expanded: true, child: TextField(focusNode: node)))));
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    node.dispose();
  });
  testWidgets('panel fits a narrow screen and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 640), textScaler: TextScaler.linear(1.3)),
            child: child!),
        home: const _Harness()));
    await tester.tap(find.text('Фильтры'));
    await tester.pumpAndSettle();
    expect(find.text('Скрыть фильтры'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
