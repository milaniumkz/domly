import 'cleaning_time_range.dart';

Map<String, dynamic> mapCleanerWorkItem(Map<String, dynamic> row,
    {bool offer = false}) {
  final orderId = row['order_id'] ?? row['orderId'] ?? row['id'];
  final start = (row['start_time'] ?? row['startTime'] ?? '').toString();
  final end = (row['end_time'] ?? row['endTime'] ?? '').toString();
  final addonRows =
      (row['addonsDetailed'] ?? row['addons'] ?? const []) as List;
  final detailed = addonRows
      .whereType<Map>()
      .where((item) => !['cancelled', 'rejected', 'refunded']
          .contains('${item['paymentStatus'] ?? item['payment_status']}'))
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  final accepted = detailed
      .where((item) => item['requires_customer_approval'] != true)
      .toList();
  final proposed = detailed
      .where((item) => item['requires_customer_approval'] == true)
      .toList();
  final address = [
    row['settlement'],
    row['street'],
    row['house'],
    if (row['apartment'] != null) 'кв. ${row['apartment']}'
  ]
      .where((part) => part != null && part.toString().trim().isNotEmpty)
      .join(', ');
  return {
    ...row,
    'status': offer && row['status'] == 'offered' ? 'pending' : row['status'],
    'id': orderId,
    'orderId': orderId,
    'area': _workItemArea(row['area']),
    'addonsDetailed': accepted,
    'addons': accepted
        .map((item) => item['label'] ?? item['title_ru'] ?? '')
        .where((label) => '$label'.isNotEmpty)
        .toList(),
    'addonCount': accepted.length,
    'pendingAddonCount': proposed.length,
    'proposedAddons': proposed,
    'startRequiresCustomerConfirmation':
        row['start_requires_customer_confirmation'] == true,
    'cleaningStartConfirmed': row['cleaning_start_confirmed'] == true,
    'cleaningStartRejected': row['cleaning_start_rejected'] == true,
    'startedAt': row['started_at'],
    'completedAt': row['completed_at'],
    if (offer) 'offerId': row['id'],
    'expiresAt': row['expires_at'] ?? row['expiresAt'],
    'createdAt': row['created_at'] ?? row['createdAt'],
    'scheduledFor': row['scheduled_date'] ?? row['scheduledFor'] ?? row['date'],
    'date': row['scheduled_date'] ?? row['date'],
    'scheduledDateKey':
        row['scheduled_date'] ?? row['scheduledDateKey'] ?? row['date'],
    'time': row['time'] ??
        cleaningTimeRange(start, end,
            date: row['scheduled_date'] ?? row['date'],
            durationMinutes: row['estimated_duration_minutes'] ??
                row['estimatedDurationMinutes']),
    'startTime': start,
    'endTime': end,
    'orderNumber':
        row['order_number'] ?? row['numeric_id'] ?? row['orderNumber'],
    'customerId': row['customer_id'] ?? row['customerId'],
    'cleanerId': row['cleaner_id'] ?? row['cleanerId'],
    'customerName': row['customer_name'] ?? row['customerName'],
    'customerPhone': row['customer_phone'] ?? row['customerPhone'],
    'package': row['package_name_ru'] ?? row['package'],
    'address': address.isNotEmpty ? address : row['address'],
    'estimatedDurationMinutes':
        row['estimated_duration_minutes'] ?? row['estimatedDurationMinutes'],
    'totalDurationMinutes':
        row['estimated_duration_minutes'] ?? row['totalDurationMinutes'],
  };
}

num _workItemArea(dynamic value) {
  final area = value is num ? value : num.tryParse((value ?? '').toString());
  return area != null && area.isFinite && area >= 0 ? area : 0;
}
