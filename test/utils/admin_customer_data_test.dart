import 'package:domly/utils/admin_customer_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'deleted paid customers remain identifiable and show their remaining entitlement',
      () {
    final customer = mapAdminCustomer({
      'id': 'customer',
      'full_name': 'Клиент',
      'phone': '+77000000000',
      'deleted_at': '2030-01-01T00:00:00Z',
      'restore_until': '2030-01-31T00:00:00Z',
      'paid_package_count': 1,
      'paid_total': '129600.00',
      'remaining_paid_cleanings': '8',
      'package_names': ['Квартальный пакет'],
      'residential_complex': 'ЖК Тест',
      'house': '39',
      'area': '67.00',
      'address': 'Астана, Тестовая, 39'
    });
    expect(customer['name'], 'Клиент');
    expect(customer['packageNames'], ['Квартальный пакет']);
    expect(customer['residentialComplex'], 'ЖК Тест');
    expect(customer['houseTitle'], 'ЖК Тест, 39');
    expect(mapAdminCustomer({'residential_complex':'','house':'39'})['houseTitle'], '39');
    expect(customer['area'], '67.00');
    expect(customer['address'], contains('39'));
    expect(customer['phone'], '+77000000000');
    expect(customer['deletedWithPayments'], isTrue);
    expect(customer['remainingPaidCleanings'], 8);
    expect(
        canRestoreCustomer(customer, now: DateTime.utc(2030, 1, 30)), isTrue);
    expect(
        canRestoreCustomer(customer, now: DateTime.utc(2030, 1, 31)), isFalse);
  });
  test(
      'legacy anonymized records keep the financial warning without a false restoration promise',
      () {
    final customer = mapAdminCustomer({
      'id': 'old',
      'phone': 'deleted-old',
      'deleted_at': '2029-01-01T00:00:00Z',
      'paid_package_count': 1,
      'paid_total': '100'
    });
    expect(customer['phone'], isNull);
    expect(customer['deletedWithPayments'], isTrue);
    expect(canRestoreCustomer(customer), isFalse);
    expect(
        mapAdminCustomer({'paid_total': 100})['deletedWithPayments'], isFalse);
  });
  test(
      'support loads later pages instead of overlooking older deleted accounts',
      () async {
    final result = await loadAdminCustomers((offset, limit) async =>
        List.generate(offset == 0 ? limit : 1,
            (i) => {'id': 'customer-${offset + i}', 'full_name': 'Клиент'}));
    expect(result, hasLength(201));
    expect(result.last['id'], 'customer-200');
  });
}
