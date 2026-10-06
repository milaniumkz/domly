import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';
import '../../utils/order_display.dart';
import '../../localization/translation_controller.dart';

class CleanerMessagesScreen extends StatelessWidget {
  const CleanerMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = FirestoreDataService.instance;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: data.userChatSummariesStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const DomlyShell(
            bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 3),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: DomlyEmptyStateCard(
                    title: 'Не удалось загрузить сообщения',
                    subtitle: 'Обновите экран и попробуйте снова.',
                    icon: Icons.error_outline,
                  ),
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const DomlyShell(
            bottomNavigationBar: DomlyCleanerBottomNav(currentIndex: 3),
            child: SafeArea(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    DomlyColors.buttonPrimary,
                  ),
                ),
              ),
            ),
          );
        }
        final summaries = snapshot.data ?? const <Map<String, dynamic>>[];
        return DomlyShell(
          bottomNavigationBar: const DomlyCleanerBottomNav(currentIndex: 3),
          child: SafeArea(
            child: Column(
              children: [
                DomlyHeader(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      domlyTopIconButton(
                        icon: Icons.arrow_back,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Сообщения'.tr(),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Диалоги с клиентами по заказам.'.tr(),
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xCCFFFFFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: summaries.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: DomlyEmptyStateCard(
                              title: 'Пока нет сообщений',
                              subtitle: 'Диалоги с клиентами появятся здесь.',
                              icon: Icons.chat_bubble_outline,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
                          itemCount: summaries.length,
                          itemBuilder: (context, index) {
                            final item = summaries[index];
                            final unread =
                                (item['unreadCount'] as num?)?.toInt() ?? 0;
                            final updatedAt = _timestamp(
                              item['updatedAt'] ?? item['lastMessageAt'],
                            );
                            final participantName =
                                (item['participantName'] ?? '')
                                    .toString()
                                    .trim();
                            final displayId = orderDisplayId(item);
                            final title = participantName.isNotEmpty
                                ? 'Заказ №$displayId · $participantName'
                                : 'Заказ №$displayId';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DomlyCard(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(22),
                                  onTap: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/chat',
                                      arguments: {
                                        'orderId': (item['orderId'] ?? '')
                                            .toString(),
                                      },
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: DomlyColors.backgroundSoft,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.chat_bubble_outline,
                                            color: DomlyColors.buttonPrimary,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                title,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: DomlyColors.foreground,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                (item['lastMessage'] ??
                                                        'Сообщений пока нет')
                                                    .toString(),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  color: DomlyColors.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              updatedAt == null
                                                  ? '—'
                                                  : domlyDateText(updatedAt),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: DomlyColors.muted,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            if (unread > 0)
                                              DomlyStatusChip(
                                                label: '$unread новых',
                                                color:
                                                    DomlyColors.buttonPrimary,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  DateTime? _timestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
