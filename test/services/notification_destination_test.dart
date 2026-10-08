import 'package:flutter_test/flutter_test.dart';
import 'package:domly/utils/notification_destination.dart';

void main() {
  test('backend order notification opens and focuses its customer order', () {
    final link = notificationDestination(
        {'type': 'order', 'targetId': 'order-1'},
        cleaner: false)!;
    expect(link.route, '/client/orders');
    expect(link.arguments?['focusOrderId'], 'order-1');
  });
  test('backend area, payment, package and bonus links use customer sections',
      () {
    for (final entry in {
      'quality_check': '/client/area-confirmation',
      'payments': '/client/payment-history',
      'package': '/client/orders',
      'bonuses': '/client/bonus'
    }.entries) {
      expect(
          notificationDestination({'targetType': entry.key, 'targetId': 'id'},
                  cleaner: false)
              ?.route,
          entry.value);
    }
  });
  test('push snake case metadata and legacy payload retain linked order', () {
    final push = notificationDestination(
        {'target_type': 'order', 'target_id': 'order-2'},
        cleaner: false)!;
    final legacy = notificationDestination({
      'type': 'cleaner_assigned',
      'payload': {'orderId': 'order-2'}
    }, cleaner: false)!;
    expect(push.arguments, legacy.arguments);
    expect(push.route, legacy.route);
  });
  test(
      'cleaner links remain on cleaner surface and unknown messages have no fabricated route',
      () {
    expect(
        notificationDestination({'type': 'order_offer', 'targetId': 'order-3'},
                cleaner: true)
            ?.route,
        '/cleaner/orders');
    expect(
        notificationDestination({'type': 'quality_check'}, cleaner: true)
            ?.route,
        '/cleaner/profile');
    expect(notificationDestination({'type': 'payments'}, cleaner: true)?.route,
        '/cleaner/earnings');
    expect(
        notificationDestination(
            {'type': 'external', 'route': 'https://example.com'},
            cleaner: false),
        isNull);
    expect(
        notificationDestination({'type': 'chat', 'targetId': 'order-4'},
                cleaner: true)
            ?.arguments,
        {'orderId': 'order-4'});
  });
}
