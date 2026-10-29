import 'package:domly/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cold-start taps wait for the app subscriber and are consumed once',
      () async {
    NotificationService.takePendingTaps();
    final tap = {'targetType': 'order_offer', 'targetId': 'order-1'};
    NotificationService.forwardNotificationTap(tap);
    expect(NotificationService.takePendingTaps(), [tap]);
    expect(NotificationService.takePendingTaps(), isEmpty);
    final events = <Map<String, dynamic>>[];
    final sub = NotificationService.notificationTaps.listen(events.add);
    NotificationService.forwardNotificationTap(tap);
    await Future<void>.delayed(Duration.zero);
    expect(events, [tap]);
    expect(NotificationService.takePendingTaps(), isEmpty);
    await sub.cancel();
  });

  test('backend and legacy cleaner offers use the audible channel', () {
    for (final type in [
      'order_offer',
      'new_order_offer',
      'scheduled_order_offer'
    ]) {
      expect(NotificationService.isOrderOffer({'targetType': type}), isTrue);
      expect(NotificationService.isOrderOffer({'type': type}), isTrue);
    }
    expect(NotificationService.isOrderOffer({'targetType': 'chat'}), isFalse);
  });

  test('bot foreground notifications include navigation and ignore duplicates',
      () async {
    final events = <Map<String, dynamic>>[];
    final subscription =
        NotificationService.foregroundMessages.listen(events.add);
    const reply = RemoteMessage(
        messageId: 'foreground-bot-test',
        data: {'targetType': 'assistant_chat', 'targetId': 'chat'},
        notification:
            RemoteNotification(title: 'Помощник DomLY', body: 'Ответ готов'));
    NotificationService.forwardForegroundMessage(reply);
    NotificationService.forwardForegroundMessage(reply);
    NotificationService.forwardForegroundMessage(const RemoteMessage(
        messageId: 'other-test', data: {'targetType': 'order'}));
    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.single['body'], 'Ответ готов');
    expect(events.single['targetId'], 'chat');
    await subscription.cancel();
  });
}
