/// Adapts backend addon rows to the order-level approval actions used by clients.
List<Map<String, dynamic>> mapBackendAddonRequests(
    List<Map<String, dynamic>> rows,
    {String locale = 'ru'}) {
  num number(Object? value) =>
      value is num ? value : num.tryParse('$value') ?? 0;
  final groups = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    final orderId = (row['order_id'] ?? '').toString();
    if (orderId.isEmpty) continue;
    final paymentStatus =
        (row['payment_status'] ?? row['status'] ?? '').toString();
    final cleanerId = (row['cleaner_id'] ?? '').toString();
    final orderStatus = (row['order_status'] ?? '').toString();
    final legacyApproval = paymentStatus == 'pending' &&
        cleanerId.isNotEmpty &&
        orderStatus != 'pending_payment';
    final needsApproval = (row['requires_customer_approval'] == true ||
            (row['requires_customer_approval'] == null && legacyApproval)) &&
        !{'cancelled', 'completed'}.contains(orderStatus);
    final separate = row['paid_separately'] == true;
    final status = needsApproval ? 'pending_customer' : paymentStatus;
    final group = groups.putIfAbsent(
        '$orderId:$status',
        () => <String, dynamic>{
              'id': orderId,
              'orderId': orderId,
              'customerId': row['customer_id'],
              'cleanerId': row['cleaner_id'],
              'cleanerName': row['cleaner_name'] ?? '',
              'status': status,
              'createdAt': row['created_at'],
              'updatedAt': row['created_at'],
              'amount': 0,
              'addonsDetailed': <Map<String, dynamic>>[],
            });
    final kazakh = (row['addon_title_kk'] ?? '').toString().trim();
    final label = locale == 'kk' && kazakh.isNotEmpty
        ? kazakh
        : (row['addon_title_ru'] ?? '').toString();
    final quantity = number(row['quantity']);
    final price = number(row['price']);
    (group['addonsDetailed'] as List<Map<String, dynamic>>).add({
      'key': row['addon_id'],
      'addonId': row['addon_id'],
      'label': label,
      'quantity': quantity,
      'price': price,
      'durationMinutes': number(row['duration_minutes']),
      'separatePayment': separate,
    });
    group['amount'] =
        (group['amount'] as num) + (separate ? 0 : price * quantity);
  }
  return groups.values.toList();
}
