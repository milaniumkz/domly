import 'package:flutter_test/flutter_test.dart';
import 'package:domly/utils/cleaner_order_history.dart';

void main() {
  test(
      'overdue assignments stay actionable until explicitly completed or cancelled',
      () {
    for (final status in [
      'assigned',
      'start_pending',
      'in_progress',
      'waiting_cleaner'
    ]) {
      expect(
          cleanerOrderIsActive({
            'id': 'existing',
            'status': status,
            'scheduledFor': '2020-01-01',
            'time': '08:00 - 10:00',
            'estimatedDurationMinutes': 120
          }),
          isTrue,
          reason: status);
    }
  });
  test(
      'completion and cancellation, rather than the planned clock, close the active list',
      () {
    for (final status in ['completed', 'cancelled', 'canceled', 'COMPLETED']) {
      expect(
          cleanerOrderIsActive(
              {'status': status, 'scheduledFor': '2099-01-01'}),
          isFalse);
    }
    final completed = {
      'id': 'completed',
      'status': 'completed',
      'scheduledFor': '2020-01-01'
    };
    expect(
        cleanerOrderHistory([
          completed,
          {
            'id': 'unfinished',
            'status': 'assigned',
            'scheduledFor': '2020-01-01'
          }
        ]).map((row) => row['id']),
        ['completed']);
  });
}
