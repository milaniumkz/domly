import 'package:domly/utils/admin_complaint_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'complaint keeps the exact order link and readable joined customer and visit data',
      () {
    final c = mapAdminComplaint({
      'id': 'complaint',
      'numeric_id': 1,
      'order_id': 'exact-order-uuid',
      'order_number': '73',
      'customer_id': 'customer-uuid',
      'customer_name': 'Клиент',
      'customer_phone': '+77000000000',
      'cleaner_name': 'Уборщица',
      'scheduled_date': '2030-02-02',
      'start_time': '10:00:00',
      'end_time': '12:00:00',
      'body': 'Полный текст жалобы',
      'status': 'open',
      'photo_urls': ['https://example.com/photo'],
      'created_at': '2030-02-03'
    });
    expect(c['orderId'], 'exact-order-uuid');
    expect(c['customerId'], 'customer-uuid');
    expect(c['customerName'], 'Клиент');
    expect(c['startTime'], '10:00');
    expect(c['text'], 'Полный текст жалобы');
    expect(c['number'], 1);
    expect(c['photoUrls'], ['https://example.com/photo']);
    expect(complaintOrderLabel(c), 'Заказ №73');
    expect(complaintOrderLabel(c), isNot(contains('uuid')));
    expect(mapAdminComplaint(c)['orderId'], c['orderId']);
  });
  test(
      'unlinked complaints remain explicit, and unknown numbers never become guessed orders',
      () {
    expect(complaintOrderLabel(mapAdminComplaint({'id': 'complaint'})),
        'Не привязана к заказу');
    expect(
        complaintOrderLabel(
            mapAdminComplaint({'order_id': 'exact-order-uuid'})),
        'Связанный заказ');
  });
}
