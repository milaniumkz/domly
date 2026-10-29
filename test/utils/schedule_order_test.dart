import 'package:domly/utils/schedule_order.dart';
import 'package:domly/utils/order_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('searching cleaner can be cancelled before account deletion', () {
    expect(isActiveScheduleOrder({'status': 'waiting_cleaner'}), isTrue);
    expect(canCancelScheduledCleaning('waiting_cleaner'), isTrue);
    expect(canCancelScheduledCleaning(' WAITING_CLEANER '), isTrue);
    expect(orderStatusLabel('waiting_cleaner'), 'Ищем уборщицу');
    for (final status in ['in_progress', 'completed', 'cancelled', 'unknown']) {
      expect(canCancelScheduledCleaning(status), isFalse);
    }
  });

  test('package payment never becomes a cancellable scheduled visit', () {
    for (final status in ['pending_payment', 'pending_assignment']) {
      expect(
          isActiveScheduleOrder({'type': 'package_purchase', 'status': status}),
          isFalse);
      expect(
          isActiveScheduleOrder(
              {'view_kind': 'package_purchase', 'status': status}),
          isFalse);
    }
  });
  test('unpaid real cleaning remains cancellable, terminal visits are excluded',
      () {
    expect(isActiveScheduleOrder({'status': 'pending_payment'}), isTrue);
    expect(isActiveScheduleOrder({'status': 'assigned'}), isTrue);
    for (final status in ['cancelled', 'canceled', 'completed']) {
      expect(isActiveScheduleOrder({'status': status}), isFalse);
      expect(isActiveScheduleOrder({'orderStatus': status}), isFalse);
    }
  });
}
