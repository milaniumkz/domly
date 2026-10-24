import '../localization/translation_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChatInteraction {
  final scroll = ScrollController();
  final inputFocus = FocusNode();
  String? _signature;
  Set<String>? _incomingIds;
  bool _disposed = false;

  void update(BuildContext context, List<Map<String, dynamic>> messages,
      {required bool Function(Map<String, dynamic>) incoming}) {
    final signature = messages
        .map((m) => '${m['id']}:${m['text'] ?? m['message_ru']}')
        .join('|');
    if (_signature == signature) return;
    final ids = messages.where(incoming).map((m) => '${m['id']}').toSet();
    final notify =
        _incomingIds != null && ids.difference(_incomingIds!).isNotEmpty;
    _signature = signature;
    _incomingIds = ids;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !context.mounted) return;
      if (scroll.hasClients)
        scroll.animateTo(0,
            duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      if (notify)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Новое сообщение в чате'.tr()),
            duration: Duration(seconds: 2)));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void focusInput() {
    if (!_disposed) inputFocus.requestFocus();
  }

  void reset() {
    _signature = null;
    _incomingIds = null;
  }

  void dispose() {
    _disposed = true;
    scroll.dispose();
    inputFocus.dispose();
  }
}

class ChatComposerField extends StatelessWidget {
  const ChatComposerField(
      {super.key,
      required this.controller,
      required this.focusNode,
      required this.onSend,
      this.hint = 'Введите сообщение'});
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final String hint;

  @override
  Widget build(BuildContext context) {
    TranslationScope.watch(context);
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): onSend,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): onSend
        },
        child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            maxLength: 10000,
            textInputAction: TextInputAction.send,
            onEditingComplete: () {},
            onSubmitted: (_) => onSend(),
            decoration:
                InputDecoration(hintText: (hint).tr(), counterText: '')));
  }
}
