import 'package:domly/utils/admin_order_data.dart';
import 'package:domly/utils/order_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server order fields populate the administrator card and its actions',
      () {
    final order = mapAdminOrder({
      'id': 'order',
      'numeric_id': 128,
      'status': 'waiting_cleaner',
      'customer_id': 'customer',
      'customer_name': 'Клиент',
      'customer_phone': '+7700',
      'scheduled_date': '2030-01-02',
      'start_time': '10:00:00',
      'end_time': '12:00:00',
      'city': 'Астана',
      'street': 'Тестовая',
      'house': '1',
      'apartment': '12',
      'total_amount': '12000.00',
      'payable_amount': '0.00',
      'area': '100',
      'latest_payment_status': 'paid',
      'created_at': '2030-01-01T10:00:00Z',
      'addons': [
        {'title_ru': 'Окна', 'quantity': '2', 'payment_status': 'paid'}
      ],
    });
    expect(orderDisplayId(order), '128');
    expect(order['customerId'], 'customer');
    expect(order['customerName'], 'Клиент');
    expect(order['address'], 'Астана, Тестовая, 1, кв. 12');
    expect(order['time'], '10:00:00 - 12:00:00');
    expect(order['scheduledFor'], '2030-01-02');
    expect(order['price'], 12000);
    expect(order['paymentStatus'], 'paid');
    expect((order['addonsDetailed'] as List).single['label'], 'Окна');
    expect(canAdminCancelOrder(order), isTrue);
    expect(canAdminAssignOrder(order), isTrue);
    expect(canAdminAssignOrder({...order, 'payableAmount': 100}), isFalse);
    expect(
        canAdminCancelOrder({...order, 'orderStatus': 'completed'}), isFalse);
  });

  test(
      'all server pages are read and separate orders at the same time are retained',
      () async {
    final calls = <int>[];
    final orders = await loadAdminOrders((offset, limit) async {
      calls.add(offset);
      return List.generate(
          offset == 0 ? limit : 1,
          (i) => {
                'id': 'order-${offset + i}',
                'customer_id': 'same-customer',
                'scheduled_date': '2030-01-02',
                'start_time': '10:00:00',
              });
    });
    expect(calls, [0, 200]);
    expect(orders, hasLength(201));
    expect(orders.map((o) => o['id']).toSet(), hasLength(201));
  });

  test('purchase records remain visible without receiving visit-only actions',
      () {
    final purchase = mapAdminOrder({
      'id': 'purchase',
      'view_kind': 'package_purchase',
      'package_name_ru': 'Квартальный пакет',
      'status': 'active'
    });
    expect(purchase['type'], 'package_purchase');
    expect(purchase['packageName'], 'Квартальный пакет');
    expect(canAdminAssignOrder(purchase), isFalse);
    expect(canAdminCancelOrder(purchase), isFalse);
  });
}
