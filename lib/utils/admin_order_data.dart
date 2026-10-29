import 'cleaning_time_range.dart';

Map<String, dynamic> mapAdminOrder(Map<String, dynamic> row) {
  num amount(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;
  final purchase = row['view_kind'] == 'package_purchase' ||
      row['type'] == 'package_purchase';
  final status = (row['status'] ?? row['orderStatus'] ?? '').toString();
  final date = (row['scheduled_date'] ?? row['scheduledFor'] ?? '').toString();
  final start = (row['start_time'] ?? row['startTime'] ?? '').toString();
  final end = (row['end_time'] ?? row['endTime'] ?? '').toString();
  final address = [
    row['city'],
    row['settlement'],
    row['street'],
    row['house'],
    if (row['apartment'] != null) 'кв. ${row['apartment']}'
  ]
      .where((part) => part != null && part.toString().trim().isNotEmpty)
      .join(', ');
  final cleanerId = row['cleaner_id'] ?? row['cleanerId'];
  final addons = (row['addons'] ?? row['addonsDetailed'] ?? const []) as List;
  final normalizedAddons = addons
      .whereType<Map>()
      .map((item) => {
            ...item,
            'label': item['label'] ?? item['title_ru'] ?? item['title'],
            'durationMinutes':
                item['durationMinutes'] ?? item['duration_minutes'],
            'paymentStatus': item['paymentStatus'] ?? item['payment_status'],
          })
      .toList();
  final latestPayment = row['latest_payment_status'] ?? row['payment_status'];
  return {
    ...row,
    'id': row['id'],
    'orderId': row['id'],
    'orderNumber': row['numeric_id'] ?? row['orderNumber'],
    'type': purchase ? 'package_purchase' : 'cleaning_visit',
    'scopeType': purchase ? 'package_purchase' : 'order',
    'status': status,
    'orderStatus': status,
    'customerId': row['customer_id'] ?? row['customerId'],
    'cleanerId': cleanerId,
    'customerName': row['customer_name'] ?? row['customerName'],
    'customerPhone': row['customer_phone'] ?? row['customerPhone'],
    'cleanerName': row['cleaner_name'] ?? row['cleanerName'],
    'cleanerPhone': row['cleaner_phone'] ?? row['cleanerPhone'],
    'packageId': row['package_id'] ?? row['packageId'],
    'subscriptionId': row['customer_package_id'] ?? row['subscriptionId'],
    'package': row['package_name_ru'] ?? row['package'],
    'packageName': row['package_name_ru'] ?? row['packageName'],
    'scheduledFor': date,
    'date': date,
    'scheduledDateKey': date,
    'startTime': start,
    'endTime': end,
    'time': start.isEmpty
        ? ''
        : cleaningTimeRange(start, end,
            date: date, durationMinutes: row['estimated_duration_minutes']),
    'address': address.isEmpty ? row['address'] ?? '' : address,
    'area': amount(row['area'] ?? row['profile_area']),
    'price': amount(row['total_amount'] ?? row['price']),
    'amount': amount(row['total_amount'] ?? row['amount']),
    'baseAmount': amount(row['base_amount']),
    'addonAmount': amount(row['addon_amount']),
    'payableAmount': amount(row['payable_amount'] ?? row['payableAmount']),
    'bonusAppliedAmount': amount(row['bonus_spent']),
    'paymentStatus': latestPayment ??
        (status == 'pending_payment' ? 'pending_invoice' : '—'),
    'addonsDetailed': normalizedAddons,
    'createdAt': row['created_at'] ?? row['createdAt'],
    'updatedAt': row['updated_at'] ?? row['updatedAt'],
    'totalDurationMinutes': amount(row['estimated_duration_minutes']),
    'assignmentStatus': cleanerId == null || cleanerId.toString().isEmpty
        ? 'pending_assignment'
        : 'assigned',
    'totalVisits': row['total_cleanings'] ?? 1,
  };
}

/// Preserve every order ID, including separate visits at the same address/time.
Future<List<Map<String, dynamic>>> loadAdminOrders(
  Future<List<Map<String, dynamic>>> Function(int offset, int limit) fetch,
) async {
  const limit = 200;
  final orders = <String, Map<String, dynamic>>{};
  for (var offset = 0;; offset += limit) {
    final page = await fetch(offset, limit);
    for (final row in page) {
      final id = (row['id'] ?? '').toString();
      if (id.isNotEmpty) orders[id] = mapAdminOrder(row);
    }
    if (page.length < limit) break;
  }
  return orders.values.toList();
}

bool canAdminAssignOrder(Map<String, dynamic> order) =>
    order['type'] != 'package_purchase' &&
    {'pending_assignment', 'waiting_cleaner', 'assigned'}
        .contains(order['orderStatus'] ?? order['status']) &&
    (num.tryParse(
                '${order['payableAmount'] ?? order['payable_amount'] ?? 0}') ??
            0) <=
        0;

bool canAdminCancelOrder(Map<String, dynamic> order) =>
    order['type'] != 'package_purchase' &&
    !{'completed', 'cancelled', 'canceled'}
        .contains(order['orderStatus'] ?? order['status']);
