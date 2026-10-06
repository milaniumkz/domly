import 'package:flutter/material.dart';
import '../../utils/backend_compat.dart';

import '../../localization/translation_controller.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../utils/order_display.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.orderId,
    required this.senderId,
    required this.senderRole,
    this.readOnly = false,
  });

  final String orderId;
  final String senderId;
  final String senderRole;
  final bool readOnly;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _data = FirestoreDataService.instance;
  bool _markingRead = false;
  bool _initializing = true;
  bool _sending = false;
  String? _chatError;
  late String _activeOrderId;
  String? _lastReadSignature;
  Stream<Map<String, dynamic>?>? _summaryStream;
  Stream<List<Map<String, dynamic>>>? _messagesStream;
  final List<Map<String, dynamic>> _pendingMessages = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _activeOrderId = widget.orderId;
    _configureStreams(_activeOrderId);
    _initChat();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _switchChat(widget.orderId, clearPending: true);
      _initChat();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _summaryStream,
      builder: (context, summarySnap) {
        final unreadCount = widget.readOnly
            ? 0
            : (summarySnap.data?['unreadCount'] as num?)?.toInt() ?? 0;
        final chatClosed =
            widget.readOnly ||
            (summarySnap.data?['status'] ?? '').toString() == 'closed';
        return DomlyShell(
          child: SafeArea(
            child: Column(
              children: [
                DomlyHeader(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      domlyTopIconButton(
                        icon: Icons.arrow_back,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        unreadCount > 0
                            ? 'Чат заказа ({count})'.tr(
                                params: {'count': unreadCount.toString()},
                              )
                            : 'Чат заказа'.tr(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _chatSubtitle(summarySnap.data),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xCCFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildMessagesPane()),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: DomlyCard(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: chatClosed
                          ? Text(
                              'Заказ закрыт. Чат доступен только для чтения.'
                                  .tr(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: DomlyColors.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _textController,
                                    minLines: 1,
                                    maxLines: 4,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _send(),
                                    decoration: InputDecoration(
                                      hintText: 'Введите сообщение'.tr(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: _sending ? null : _send,
                                  style: IconButton.styleFrom(
                                    backgroundColor: DomlyColors.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: _sending
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                      : const Icon(Icons.send),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _chatSubtitle(Map<String, dynamic>? summary) {
    final displayId = orderDisplayId(summary);
    final peerName = _chatPeerName(summary);
    if (peerName.isEmpty) {
      return 'Заказ №$displayId';
    }
    return 'Заказ №$displayId · $peerName';
  }

  String _chatPeerName(Map<String, dynamic>? summary) {
    final data = summary ?? const <String, dynamic>{};
    final participantName = (data['participantName'] ?? '').toString().trim();
    if (participantName.isNotEmpty) {
      return participantName;
    }
    if (widget.senderRole == 'cleaner') {
      return (data['customerName'] ??
              data['clientName'] ??
              data['client'] ??
              '')
          .toString()
          .trim();
    }
    return (data['cleanerName'] ?? data['cleaner'] ?? '').toString().trim();
  }

  Widget _buildMessagesPane() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(DomlyColors.buttonPrimary),
        ),
      );
    }
    if (_chatError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DomlyEmptyStateCard(
                title: 'Чат пока недоступен',
                subtitle: _chatError!,
                icon: Icons.chat_bubble_outline,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 220,
                child: DomlyPrimaryButton(
                  label: 'Попробовать снова',
                  onPressed: _initChat,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError && _pendingMessages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: DomlyEmptyStateCard(
                title: 'Не удалось загрузить сообщения',
                subtitle: _chatErrorText(snapshot.error!),
                icon: Icons.chat_bubble_outline,
              ),
            ),
          );
        }
        final remoteMessages = snapshot.data ?? <Map<String, dynamic>>[];
        final messages = _mergeMessages(remoteMessages);
        _markAsReadIfNeeded(messages);
        if (messages.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: DomlyEmptyStateCard(
                title: 'Пока нет сообщений',
                subtitle: 'Первое сообщение по заказу появится здесь.',
                icon: Icons.chat_bubble_outline,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final m = messages[index];
            final isMine = m['senderId'] == widget.senderId;
            final isSystem = (m['type'] ?? 'text') == 'system';
            final isPending = m['pending'] == true;
            final readBy = ((m['readBy'] ?? const []) as List)
                .map((e) => e.toString())
                .toList();
            final isReadByOther =
                isMine && readBy.any((id) => id != widget.senderId);
            final createdAt = (m['createdAt'] as dynamic);
            final timeText = createdAt is Timestamp
                ? '${createdAt.toDate().hour.toString().padLeft(2, '0')}:${createdAt.toDate().minute.toString().padLeft(2, '0')}'
                : '';
            if (isSystem) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: DomlyColors.backgroundSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      (m['text'] ?? '').toString(),
                      style: const TextStyle(
                        color: DomlyColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
            return Align(
              alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMine
                      ? DomlyColors.primary
                      : DomlyColors.backgroundSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: isMine ? null : Border.all(color: DomlyColors.border),
                ),
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      (m['text'] ?? '').toString(),
                      style: TextStyle(
                        color: isMine ? Colors.white : DomlyColors.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeText,
                          style: TextStyle(
                            fontSize: 12,
                            color: isMine ? Colors.white70 : DomlyColors.muted,
                          ),
                        ),
                        if (isMine) ...[
                          const SizedBox(width: 8),
                          Text(
                            isPending
                                ? 'Отправляем...'.tr()
                                : isReadByOther
                                ? 'Прочитано'.tr()
                                : 'Доставлено'.tr(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _sending = true;
      _chatError = null;
      final pendingId = 'pending_${DateTime.now().microsecondsSinceEpoch}';
      _pendingMessages.add({
        'id': pendingId,
        'senderId': widget.senderId,
        'senderRole': widget.senderRole,
        'text': text,
        'type': 'text',
        'createdAt': Timestamp.now(),
        'readBy': [widget.senderId],
        'pending': true,
      });
    });
    _textController.clear();
    try {
      final pendingId = _pendingMessages.isNotEmpty
          ? (_pendingMessages.last['id'] ?? '').toString()
          : '';
      final canonicalOrderId = await _data.sendChatMessage(
        orderId: _activeOrderId,
        senderId: widget.senderId,
        senderRole: widget.senderRole,
        text: text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sending = false;
        if (canonicalOrderId != _activeOrderId) {
          _switchChat(canonicalOrderId);
        }
        for (var i = 0; i < _pendingMessages.length; i++) {
          if ((_pendingMessages[i]['id'] ?? '').toString() == pendingId) {
            _pendingMessages[i] = {..._pendingMessages[i], 'pending': false};
            break;
          }
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _textController.text = text;
      setState(() {
        _sending = false;
        _pendingMessages.removeWhere(
          (message) =>
              message['pending'] == true &&
              (message['text'] ?? '').toString() == text,
        );
        _chatError = _chatErrorText(error);
      });
    }
  }

  List<Map<String, dynamic>> _mergeMessages(
    List<Map<String, dynamic>> remoteMessages,
  ) {
    if (_pendingMessages.isEmpty) {
      return remoteMessages;
    }
    final pending = _pendingMessages.where((pendingMessage) {
      final pendingText = (pendingMessage['text'] ?? '').toString();
      final pendingSender = (pendingMessage['senderId'] ?? '').toString();
      final hasRemoteMatch = remoteMessages.any(
        (remoteMessage) =>
            (remoteMessage['senderId'] ?? '').toString() == pendingSender &&
            (remoteMessage['text'] ?? '').toString() == pendingText &&
            (remoteMessage['type'] ?? 'text').toString() == 'text',
      );
      return !hasRemoteMatch;
    }).toList();

    if (pending.length != _pendingMessages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _pendingMessages
            ..clear()
            ..addAll(pending);
        });
      });
    }

    return <Map<String, dynamic>>[...remoteMessages, ...pending];
  }

  Future<void> _initChat() async {
    setState(() {
      _initializing = true;
      _chatError = null;
    });
    try {
      if (widget.readOnly) {
        if (!mounted) {
          return;
        }
        setState(() => _initializing = false);
        return;
      }
      final canonicalOrderId = await _data.createOrOpenOrderChat(
        orderId: _activeOrderId,
      );
      if (!mounted) {
        return;
      }
      if (canonicalOrderId != _activeOrderId) {
        setState(() {
          _switchChat(canonicalOrderId);
        });
      }
      final readOrderId = await _data.markChatAsRead(orderId: canonicalOrderId);
      if (!mounted) {
        return;
      }
      setState(() {
        _initializing = false;
        if (readOrderId != _activeOrderId) {
          _switchChat(readOrderId);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _initializing = false;
        _chatError = _chatErrorText(error);
      });
    }
  }

  void _markAsReadIfNeeded(List<Map<String, dynamic>> messages) {
    if (widget.readOnly) {
      return;
    }
    if (_markingRead) {
      return;
    }
    final unreadMessages = messages.where((message) {
      if ((message['senderId'] ?? '').toString() == widget.senderId) {
        return false;
      }
      final readBy = ((message['readBy'] ?? const []) as List)
          .map((e) => e.toString())
          .toList();
      return !readBy.contains(widget.senderId);
    }).toList();
    if (unreadMessages.isEmpty) {
      return;
    }
    final signature = unreadMessages
        .map((message) => (message['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .join('|');
    if (signature.isNotEmpty && signature == _lastReadSignature) {
      return;
    }
    _lastReadSignature = signature;
    _markingRead = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final canonicalOrderId = await _data.markChatAsRead(
          orderId: _activeOrderId,
        );
        if (mounted && canonicalOrderId != _activeOrderId) {
          setState(() {
            _switchChat(canonicalOrderId);
          });
        }
      } finally {
        _markingRead = false;
      }
    });
  }

  void _switchChat(String orderId, {bool clearPending = false}) {
    final normalized = orderId.trim();
    if (normalized.isEmpty || normalized == _activeOrderId) {
      return;
    }
    _activeOrderId = normalized;
    _lastReadSignature = null;
    if (clearPending) {
      _pendingMessages.clear();
    }
    _configureStreams(normalized);
  }

  void _configureStreams(String orderId) {
    _summaryStream = _data
        .chatSummaryStream(orderId)
        .asBroadcastStream(onCancel: (subscription) => subscription.cancel());
    _messagesStream = _data
        .chatMessagesStream(orderId)
        .asBroadcastStream(onCancel: (subscription) => subscription.cancel());
  }

  String _chatErrorText(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('failed-precondition')) {
      if (text.contains('closed')) {
        return 'Заказ закрыт. Новые сообщения отправлять нельзя.';
      }
      return 'Чат станет доступен после назначения уборщицы на заказ.';
    }
    if (text.contains('permission-denied')) {
      return 'У вас нет доступа к этому чату.';
    }
    if (text.contains('not-found')) {
      return 'Чат или заказ не найдены.';
    }
    return 'Не удалось открыть чат. Попробуйте снова.';
  }
}
