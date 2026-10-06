import '../../utils/backend_compat.dart';
import 'package:flutter/material.dart';

import '../../localization/translation_controller.dart';
import '../../services/firestore_data_service.dart';
import '../../ui/domly_ui.dart';

enum NotificationSurface { client, cleaner }

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.surface});

  final NotificationSurface surface;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _data = FirestoreDataService.instance;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _data.userNotificationsStream(),
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? const <Map<String, dynamic>>[];
        final sortedNotifications = [...notifications]
          ..sort((a, b) {
            final aRead = a['read'] == true;
            final bRead = b['read'] == true;
            if (aRead != bRead) {
              return aRead ? 1 : -1;
            }
            return _timestampMillis(
              b['createdAt'],
            ).compareTo(_timestampMillis(a['createdAt']));
          });
        final hasError = snapshot.hasError;
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        return DomlyShell(
          bottomNavigationBar: widget.surface == NotificationSurface.client
              ? const DomlyClientBottomNav(currentIndex: 3)
              : null,
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
                              'Уведомления'.tr(),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              notifications.isEmpty
                                  ? 'Здесь появятся важные события по заказам и сервису.'
                                        .tr()
                                  : 'Всего уведомлений: {count}'.tr(
                                      params: {
                                        'count': notifications.length
                                            .toString(),
                                      },
                                    ),
                              style: const TextStyle(
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
                  child: isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              DomlyColors.buttonPrimary,
                            ),
                          ),
                        )
                      : hasError
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: DomlyEmptyStateCard(
                              title: 'Не удалось загрузить уведомления',
                              subtitle: 'Обновите экран и попробуйте снова.',
                              icon: Icons.error_outline,
                            ),
                          ),
                        )
                      : sortedNotifications.isEmpty
                      ? _emptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
                          itemCount: sortedNotifications.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = sortedNotifications[index];
                            final previous = index == 0
                                ? null
                                : sortedNotifications[index - 1];
                            final showHeader =
                                index == 0 || previous?['read'] != item['read'];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showHeader) ...[
                                  Padding(
                                    padding: EdgeInsets.only(
                                      top: index == 0 ? 0 : 8,
                                      bottom: 10,
                                    ),
                                    child: Text(
                                      item['read'] == true
                                          ? 'Прочитанные'.tr()
                                          : 'Непрочитанные'.tr(),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: DomlyColors.foreground,
                                      ),
                                    ),
                                  ),
                                ],
                                _notificationCard(context, item),
                              ],
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

  Widget _emptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: DomlyEmptyStateCard(
          title: 'Пока нет уведомлений',
          subtitle: 'Новые события появятся здесь и в push-уведомлениях.',
          icon: Icons.notifications_none,
        ),
      ),
    );
  }

  Widget _notificationCard(BuildContext context, Map<String, dynamic> item) {
    final isRead = item['read'] == true;
    final payload = Map<String, dynamic>.from(
      (item['payload'] ?? const {}) as Map,
    );
    final type = (item['type'] ?? payload['type'] ?? '').toString();
    final orderId = (payload['slotId'] ?? payload['orderId'] ?? '')
        .toString()
        .trim();
    return InkWell(
      onTap: () => _handleNotificationTap(context, item, payload),
      borderRadius: BorderRadius.circular(22),
      child: DomlyCard(
        color: isRead ? Colors.white : const Color(0xFFFFF5EF),
        border: Border.all(
          color: isRead
              ? DomlyColors.border
              : DomlyColors.buttonPrimary.withValues(alpha: 0.45),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isRead
                    ? DomlyColors.backgroundSoft
                    : DomlyColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(
                _iconForType((item['type'] ?? '').toString()),
                color: DomlyColors.buttonPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          (item['title'] ?? '').toString(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isRead
                                ? FontWeight.w700
                                : FontWeight.w900,
                            color: DomlyColors.foreground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!isRead)
                        Container(
                          margin: const EdgeInsets.only(top: 1),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: DomlyColors.buttonPrimary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Новое'.tr(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (item['body'] ?? '').toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: DomlyColors.muted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _timestampLabel(item['createdAt']),
                    style: const TextStyle(
                      fontSize: 12,
                      color: DomlyColors.muted,
                    ),
                  ),
                  if (type == 'cleaning_start_confirmation' &&
                      widget.surface == NotificationSurface.client &&
                      orderId.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DomlyPrimaryButton(
                            label: 'Да',
                            onPressed: () => _confirmCleaningStartFromInbox(
                              context,
                              orderId,
                              true,
                              item,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DomlySecondaryButton(
                            label: 'Нет',
                            foregroundColor: DomlyColors.danger,
                            onPressed: () => _confirmCleaningStartFromInbox(
                              context,
                              orderId,
                              false,
                              item,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleNotificationTap(
    BuildContext context,
    Map<String, dynamic> item,
    Map<String, dynamic> payload,
  ) async {
    final id = (item['id'] ?? '').toString();
    if (id.isNotEmpty && item['read'] != true) {
      await _data.markNotificationRead(id);
    }

    if (!context.mounted) {
      return;
    }

    final type = (item['type'] ?? '').toString();
    final videoId = (payload['videoId'] ?? '').toString();
    final orderId = (payload['orderId'] ?? payload['chatId'] ?? '').toString();

    if (_isBonusNotification(item, payload)) {
      Navigator.pushNamed(
        context,
        widget.surface == NotificationSurface.cleaner
            ? '/cleaner/bonus'
            : '/client/bonus',
      );
      return;
    }

    if (widget.surface == NotificationSurface.cleaner &&
        (type == 'new_order_offer' || type == 'scheduled_order_offer')) {
      Navigator.pushNamed(context, '/cleaner/orders');
      return;
    }

    if (videoId.isNotEmpty) {
      Navigator.pushNamed(
        context,
        '/video/detail',
        arguments: {
          'videoId': videoId,
          'audienceType': widget.surface == NotificationSurface.cleaner
              ? 'cleaner'
              : 'client',
        },
      );
      return;
    }

    if (type == 'chat_message' && orderId.isNotEmpty) {
      Navigator.pushNamed(context, '/chat', arguments: {'orderId': orderId});
      return;
    }

    if (orderId.isNotEmpty &&
        {
          'cleaner_assigned',
          'order_completed',
          'payment_confirmed',
          'payment_rejected',
          'cleaning_reminder',
          'cleaning_schedule_update',
          'cleaner_schedule_update',
          'schedule_update',
          'cleaning_start_confirmation',
          'cleaning_start_confirmed',
          'cleaning_start_rejected',
        }.contains(type)) {
      Navigator.pushNamed(
        context,
        widget.surface == NotificationSurface.cleaner
            ? '/cleaner/orders'
            : '/client/orders',
      );
      return;
    }

    if (type == 'tier_change' || type == 'referral_bonus') {
      Navigator.pushNamed(
        context,
        widget.surface == NotificationSurface.cleaner
            ? '/cleaner/profile'
            : '/client/profile',
      );
      return;
    }

    if (type == 'verification_status') {
      Navigator.pushNamed(context, '/cleaner/verification');
      return;
    }

    if (type == 'area_quality_check' || type == 'area_verification') {
      Navigator.pushNamed(context, '/client/area-confirmation');
      return;
    }

    if (type == 'area_recalculation_payment') {
      Navigator.pushNamed(context, '/client/payment-history');
    }
  }

  bool _isBonusNotification(
    Map<String, dynamic> item,
    Map<String, dynamic> payload,
  ) {
    final searchable = [
      item['type'],
      item['title'],
      item['body'],
      payload['type'],
      payload['reason'],
      payload['title'],
      payload['body'],
    ].join(' ').toLowerCase();
    return searchable.contains('bonus') || searchable.contains('бонус');
  }

  Future<void> _confirmCleaningStartFromInbox(
    BuildContext context,
    String orderId,
    bool confirmed,
    Map<String, dynamic> item,
  ) async {
    try {
      await FirestoreDataService.instance.confirmCleaningStart(
        orderId: orderId,
        confirmed: confirmed,
      );
      final notificationId = (item['id'] ?? '').toString();
      if (notificationId.isNotEmpty) {
        await FirestoreDataService.instance.markNotificationRead(
          notificationId,
        );
      }
      if (!context.mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: confirmed ? 'Старт подтверждён' : 'Ответ отправлен',
        subtitle: confirmed
            ? 'Уборщица может продолжать уборку.'
            : 'Уборщица не сможет завершить заказ без подтверждения старта.',
        type: confirmed ? DomlySnackBarType.success : DomlySnackBarType.info,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      showDomlySnackBar(
        context,
        title: 'Не удалось отправить ответ',
        subtitle: '$error',
        type: DomlySnackBarType.error,
      );
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'payment_confirmed':
        return Icons.payments_outlined;
      case 'payment_rejected':
        return Icons.error_outline;
      case 'order_completed':
        return Icons.verified_outlined;
      case 'cleaner_assigned':
      case 'new_order_offer':
      case 'scheduled_order_offer':
      case 'cleaning_start_confirmation':
      case 'cleaning_start_confirmed':
      case 'cleaning_start_rejected':
        return Icons.cleaning_services_outlined;
      case 'cleaning_reminder':
        return Icons.schedule_outlined;
      case 'cleaning_schedule_update':
      case 'cleaner_schedule_update':
      case 'schedule_update':
        return Icons.event_note_outlined;
      case 'chat_message':
        return Icons.chat_bubble_outline;
      case 'video_content':
        return Icons.ondemand_video_outlined;
      case 'referral_bonus':
        return Icons.card_giftcard_outlined;
      case 'tier_change':
        return Icons.workspace_premium_outlined;
      case 'verification_status':
        return Icons.verified_user_outlined;
      case 'area_verification':
      case 'area_recalculation_payment':
        return Icons.square_foot_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  String _timestampLabel(dynamic value) {
    if (value is! Timestamp) {
      return 'Недавно'.tr();
    }
    final date = value.toDate();
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$dd.$mm.${date.year} · $hh:$min';
  }

  int _timestampMillis(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    return 0;
  }
}
