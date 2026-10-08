class NotificationDestination {
  const NotificationDestination(this.route, [this.arguments]);
  final String route;
  final Map<String, dynamic>? arguments;
}

/// Resolve backend entity links and older event payloads on either app surface.
NotificationDestination? notificationDestination(Map<String, dynamic> item,
    {required bool cleaner}) {
  final payload = item['payload'] is Map
      ? Map<String, dynamic>.from(item['payload'] as Map)
      : <String, dynamic>{};
  final data = {...payload, ...item};
  String value(String key) => (data[key] ?? '').toString().trim();
  final type = value('targetType').isNotEmpty
      ? value('targetType')
      : value('target_type').isNotEmpty
          ? value('target_type')
          : value('type');
  final id = ['orderId', 'chatId', 'slotId', 'targetId', 'target_id', 'scopeId']
          .map(value)
          .where((id) => id.isNotEmpty)
          .firstOrNull ??
      '';
  final orders = cleaner ? '/cleaner/orders' : '/client/orders';
  if (type.contains('bonus') || type == 'referral_bonus') {
    return NotificationDestination(
        cleaner ? '/cleaner/bonus' : '/client/bonus');
  }
  if (value('videoId').isNotEmpty) {
    return NotificationDestination('/video/detail', {
      'videoId': value('videoId'),
      'audienceType': cleaner ? 'cleaner' : 'client',
    });
  }
  if (type == 'chat' || type == 'chat_message') {
    return id.isEmpty
        ? NotificationDestination(cleaner ? '/cleaner/messages' : orders)
        : NotificationDestination('/chat', {'orderId': id});
  }
  if ({'quality_check', 'area_quality_check', 'area_verification'}
      .contains(type)) {
    return NotificationDestination(
        cleaner ? '/cleaner/profile' : '/client/area-confirmation');
  }
  if ({'payment', 'payments', 'area_recalculation_payment'}.contains(type)) {
    return NotificationDestination(
        cleaner ? '/cleaner/earnings' : '/client/payment-history');
  }
  if ({'cleaner', 'cleaner_profile', 'verification_status'}.contains(type)) {
    return NotificationDestination(cleaner ? '/cleaner/verification' : orders);
  }
  if ({'user', 'address_request', 'tier_change'}.contains(type)) {
    return NotificationDestination(
        cleaner ? '/cleaner/profile' : '/client/profile');
  }
  if ({
    'order',
    'order_offer',
    'package',
    'preorder',
    'addon_request',
    'checklist',
    'photo_report',
    'review',
    'complaint',
    'new_order_offer',
    'scheduled_order_offer',
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
    'cleaning_start_rejected'
  }.contains(type)) {
    return NotificationDestination(
        orders,
        type == 'package' || id.isEmpty
            ? null
            : {'focusOrderId': id, 'orderId': id});
  }
  if (type == 'payout' && cleaner) {
    return const NotificationDestination('/cleaner/earnings');
  }
  return null;
}
