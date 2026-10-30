import 'package:domly/utils/addon_request_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> row(String id,
          {String status = 'pending', String orderStatus = 'assigned'}) =>
      {
        'id': 'row-$id',
        'order_id': 'order-1',
        'addon_id': id,
        'payment_status': status,
        'order_status': orderStatus,
        'cleaner_id': 'cleaner-1',
        'cleaner_name': 'Анара',
        'addon_title_ru': 'Окна',
        'addon_title_kk': 'Терезелер',
        'quantity': '2.00',
        'price': '1000.00',
      };
  test('approval groups rows by order and uses order ID for actions', () {
    final result = mapBackendAddonRequests([row('a'), row('b')]);
    expect(result, hasLength(1));
    expect(result.single['id'], 'order-1');
    expect(result.single['status'], 'pending_customer');
    expect(result.single['amount'], 4000);
    expect(result.single['addonsDetailed'], hasLength(2));
    expect(result.single['cleanerName'], 'Анара');
  });
  test('paid services stay separate from pending proposals', () {
    final result =
        mapBackendAddonRequests([row('a'), row('b', status: 'paid')]);
    expect(result, hasLength(2));
    expect(result.map((r) => r['status']), ['pending_customer', 'paid']);
    expect(result.map((r) => r['amount']), [2000, 2000]);
  });
  test('checkout addons and unassigned orders are not cleaner proposals', () {
    final checkout =
        mapBackendAddonRequests([row('a', orderStatus: 'pending_payment')]);
    expect(checkout.single['status'], 'pending');
    final unassigned = row('b')..['cleaner_id'] = null;
    expect(mapBackendAddonRequests([unassigned]).single['status'], 'pending');
  });
  test(
      'Kazakh labels are preserved with Russian fallback and empty rows ignored',
      () {
    final fallback = row('b')..['addon_title_kk'] = '';
    final result =
        mapBackendAddonRequests([{}, row('a'), fallback], locale: 'kk');
    final details = result.single['addonsDetailed'] as List;
    expect(details.map((r) => r['label']), ['Терезелер', 'Окна']);
  });
  test(
      'explicit origins separate customer edits from cleaner proposals and on-site payment',
      () {
    final own = row('own')..['requires_customer_approval'] = false;
    final specialist = row('sofa', status: 'draft')
      ..['requires_customer_approval'] = true
      ..['paid_separately'] = true;
    final result = mapBackendAddonRequests([own, specialist]);
    expect(result.first['status'], 'pending');
    expect(result.last['status'], 'pending_customer');
    expect(result.last['amount'], 0);
    expect((result.last['addonsDetailed'] as List).single['separatePayment'],
        true);
  });
}
