import 'package:domly/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bot foreground notifications include navigation and ignore duplicates',
      () async {
    final events = <Map<String, dynamic>>[];
    final subscription =
        NotificationService.foregroundMessages.listen(events.add);
    const reply = RemoteMessage(
        messageId: 'foreground-bot-test',
        data: {'targetType': 'assistant_chat', 'targetId': 'chat'},
        notification:
            RemoteNotification(title: 'Помощник Domly', body: 'Ответ готов'));
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
