import 'package:domly/utils/cleaner_order_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'backend offer keeps a future expiry and uses order ID for accept and decline',
      () {
    final expiry = DateTime.now().toUtc().add(const Duration(minutes: 15));
    final row = mapCleanerWorkItem({
      'id': 'offer-1',
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
  });
}
