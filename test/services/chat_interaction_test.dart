import 'package:domly/ui/chat_interaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'composer keeps focus and sends by desktop Enter and mobile action',
      (tester) async {
    final controller = TextEditingController(), focus = FocusNode();
    var sent = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChatComposerField(
      controller: controller,
      focusNode: focus,
      onSend: () {
        sent++;
        controller.clear();
      },
    ))));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sent, 1);
    expect(controller.text, isEmpty);
    expect(focus.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), 'Another');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(sent, 2);
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    focus.dispose();
  });

  testWidgets(
      'new reply scrolls to latest and notifies once, initial history stays quiet',
      (tester) async {
    final interaction = ChatInteraction();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(
      reverse: true,
      controller: interaction.scroll,
      children: List.generate(
          30, (i) => SizedBox(height: 100, child: Text('Message $i'))),
    ))));
    final context = tester.element(find.byType(ListView));
    final messages = <Map<String, dynamic>>[
      {'id': 'old', 'text': 'old', 'incoming': true}
    ];
    interaction.update(context, messages,
        incoming: (m) => m['incoming'] == true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Новое сообщение в чате'), findsNothing);
    interaction.scroll.jumpTo(1000);
    messages.add({'id': 'new', 'text': 'reply', 'incoming': true});
    interaction.update(context, messages,
        incoming: (m) => m['incoming'] == true);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(interaction.scroll.offset, 0);
    expect(find.text('Новое сообщение в чате'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    interaction.scroll.jumpTo(500);
    interaction.update(context, messages,
        incoming: (m) => m['incoming'] == true);
    await tester.pump();
    expect(interaction.scroll.offset, 500);
    expect(find.text('Новое сообщение в чате'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    interaction.dispose();
  });
}
