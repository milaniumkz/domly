import '../../theme/domly_palette.dart';
import '../../localization/translation_controller.dart';
import '../../ui/chat_interaction.dart';
import 'package:flutter/material.dart';
import '../../app/app_scope.dart';
import '../../services/assistant_guest_service.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';

class AssistantGuestScreen extends StatefulWidget {
  const AssistantGuestScreen({super.key});
  @override
  State<AssistantGuestScreen> createState() => _AssistantGuestScreenState();
}

class _AssistantGuestScreenState extends State<AssistantGuestScreen> {
  final _text = TextEditingController();
  final _interaction = ChatInteraction();
  Stream<List<Map<String, dynamic>>>? _messages;
  String? _error;
  bool _sending = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    try {
      if (AppScope.of(context).authController.isAuthenticated) {
        final id =
            await FirestoreDataService.instance.createOrOpenAssistantChat();
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/chat',
              arguments: {'chatId': id});
        }
        return;
      }
      await AssistantGuestService.instance.initialize();
      if (mounted) {
        setState(() {
          _messages = AssistantGuestService.instance.messages();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _interaction.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (_messages == null || _sending || text.isEmpty) return;
    setState(() => _sending = true);
    _interaction.focusInput();
    try {
      await AssistantGuestService.instance.send(text);
      if (_text.text.trim() == text) _text.clear();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _interaction.focusInput();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    DomlyPalette.watch(context);
    return DomlyShell(
        child: SafeArea(
            child: Column(children: [
      Padding(
          padding: EdgeInsets.all(20),
          child: Text('Помощник DomLY'.tr(),
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
      TextButton(
          onPressed: () async {
            try {
              await AssistantGuestService.instance.enablePush();
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error.toString())));
              }
            }
          },
          child: Text('Включить уведомления о новых сообщениях'.tr())),
      Expanded(
          child: _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text((_error!).tr()),
                  TextButton(
                      onPressed: _initialize, child: Text('Повторить'.tr()))
                ]))
              : _messages == null
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _messages,
                      builder: (context, snapshot) {
                        TranslationScope.watch(context);
                        if (snapshot.hasError) {
                          return Center(
                              child: Text(
                                  'Не удалось загрузить сообщения. Попробуйте позже.'
                                      .tr()));
                        }
                        final messages = snapshot.data ?? [];
                        if (snapshot.hasData)
                          _interaction.update(context, messages,
                              incoming: (m) => m['sender_kind'] != 'guest');
                        if (messages.isEmpty) {
                          return Center(
                              child: Text(
                                  'Задайте вопрос о заказе или уборке.'.tr()));
                        }
                        return ListView.builder(
                            controller: _interaction.scroll,
                            reverse: true,
                            padding: const EdgeInsets.all(16),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              TranslationScope.watch(context);
                              final message =
                                      messages[messages.length - 1 - index],
                                  mine = message['sender_kind'] == 'guest';
                              return Align(
                                  alignment: mine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                          color: DomlyPalette.surface(mine
                                              ? DomlyColors.backgroundSoft
                                              : Colors.white),
                                          borderRadius:
                                              BorderRadius.circular(18)),
                                      child: Text((message['message_ru'] ?? '')
                                          .toString())));
                            });
                      })),
      Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
                child: ChatComposerField(
                    controller: _text,
                    focusNode: _interaction.inputFocus,
                    onSend: _send,
                    hint: 'Сообщение'.tr())),
            IconButton(
                onPressed: _messages == null || _sending ? null : _send,
                icon: const Icon(Icons.send))
          ]))
    ])));
  }
}
