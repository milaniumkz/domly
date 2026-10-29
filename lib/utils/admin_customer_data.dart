Map<String, dynamic> mapAdminCustomer(Map<String, dynamic> row) {
  num number(dynamic value) =>
      value is num ? value : num.tryParse('$value') ?? 0;
  final deleted = row['deleted_at'] ?? row['deletedAt'];
  final paidPackages =
      number(row['paid_package_count'] ?? row['paidPackageCount']);
  final paidTotal = number(row['paid_total'] ?? row['paidTotal']);
  return {
    ...row,
    'name': row['full_name'] ?? row['name'],
    'phone':
        '${row['phone'] ?? ''}'.startsWith('deleted-') ? null : row['phone'],
    'fullName': row['full_name'] ?? row['fullName'],
    'numericId': row['numeric_id'] ?? row['numericId'],
    'createdAt': row['created_at'] ?? row['createdAt'],
    'bonusPoints': number(row['bonus_balance'] ?? row['bonusPoints']),
    'deletedAt': deleted,
    'restoreUntil': row['restore_until'] ?? row['restoreUntil'],
    'paidPackageCount': paidPackages,
    'paidTotal': paidTotal,
    'remainingPaidCleanings': number(
        row['remaining_paid_cleanings'] ?? row['remainingPaidCleanings']),
    'deletedWithPayments':
        deleted != null && (paidPackages > 0 || paidTotal > 0),
  };
}

bool canRestoreCustomer(Map<String, dynamic> customer, {DateTime? now}) {
  final until = DateTime.tryParse('${customer['restoreUntil'] ?? ''}');
  return customer['deletedAt'] != null &&
      until != null &&
      until.isAfter(now ?? DateTime.now());
}

Future<List<Map<String, dynamic>>> loadAdminCustomers(
    Future<List<Map<String, dynamic>>> Function(int offset, int limit)
        fetch) async {
  final rows = <String, Map<String, dynamic>>{};
  const limit = 200;
  for (var offset = 0;; offset += limit) {
    final page = await fetch(offset, limit);
    for (final row in page) {
      if (row['id'] != null) rows[row['id'].toString()] = mapAdminCustomer(row);
    }
    if (page.length < limit) break;
  }
  return rows.values.toList();
}
