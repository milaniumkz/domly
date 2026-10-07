import 'package:domly/utils/cleaner_order_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'backend offer keeps a future expiry and uses order ID for accept and decline',
      () {
    final expiry = DateTime.now().toUtc().add(const Duration(minutes: 2));
    final row = mapCleanerWorkItem({
      'id': 'offer-1',
      'status': 'offered',
      'order_id': 'order-1',
      'expires_at': expiry.toIso8601String(),
      'scheduled_date': '2026-10-08T00:00:00Z',
      'start_time': '10:00:00',
      'end_time': '12:00:00',
      'street': 'Test',
      'house': '14',
      'apartment': '5',
      'estimated_duration_minutes': 120,
      'package_name_ru': 'Пакет'
    }, offer: true);
    expect(DateTime.parse(row['expiresAt'] as String).isAfter(DateTime.now()),
        isTrue);
    expect(row['status'], 'pending');
    expect(row['id'], 'order-1');
    expect(row['offerId'], 'offer-1');
    expect(row['scheduledFor'], '2026-10-08T00:00:00Z');
    expect(row['time'], '10:00:00 - 12:00:00');
    expect(row['address'], 'Test, 14, кв. 5');
    expect(row['package'], 'Пакет');
    expect(row['estimatedDurationMinutes'], 120);
  });
  test('accepted order preserves identity, schedule and customer details', () {
    final row = mapCleanerWorkItem({
      'id': 'order-1',
      'scheduled_date': '2026-10-08',
      'start_time': '10:00',
      'customer_name': 'Клиент',
      'customer_phone': '+77000000000'
    });
    expect(row['id'], 'order-1');
    expect(row['customerName'], 'Клиент');
    expect(row['customerPhone'], '+77000000000');
    expect(row['date'], '2026-10-08');
    expect(row['scheduledDateKey'], '2026-10-08');
  });
  test('backend start confirmation and completion fields reach Pro unchanged',
      () {
    final row = mapCleanerWorkItem({
      'id': 'one',
      'status': 'start_pending',
      'start_requires_customer_confirmation': true,
      'cleaning_start_confirmed': false,
      'cleaning_start_rejected': false,
      'started_at': null,
      'completed_at': null
    });
    expect(row['status'], 'start_pending');
    expect(row['startRequiresCustomerConfirmation'], true);
    expect(row['cleaningStartConfirmed'], false);
    expect(row['startedAt'], null);
    final completed = mapCleanerWorkItem({
      'id': 'one',
      'status': 'completed',
      'cleaning_start_confirmed': true,
      'started_at': 'start',
      'completed_at': 'finish'
    });
    expect(completed['completedAt'], 'finish');
    expect(completed['cleaningStartConfirmed'], true);
  });
}
