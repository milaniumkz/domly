/// Keep the backend review status while presenting consistent queue filters.
Map<String, dynamic> mapAdminAreaCheck(Map<String, dynamic> row) {
  final rawStatus = (row['review_status'] ?? row['status'] ?? 'pending').toString();
  final status = switch (rawStatus) {
    'pending' || 'scheduled' || 'open' => 'open',
    'approved' || 'rejected' || 'cancelled' || 'resolved' => 'resolved',
    _ => rawStatus,
  };
  final address = [
    row['city'],
    row['street'],
    row['house'],
    if (row['apartment'] != null && '${row['apartment']}'.isNotEmpty)
      'кв. ${row['apartment']}'
  ].where((v) => v != null && '$v'.trim().isNotEmpty).join(', ');
  return {
    ...row,
    'userId': row['customer_id'],
    'customerId': row['customer_id'],
    'orderId': row['order_id'],
    'actualArea': row['requested_area'],
    'initialArea': row['verified_area'] ?? row['area'] ?? 0,
    'createdAt': row['created_at'],
    'updatedAt': row['updated_at'],
    'type': row['document_file_id'] == null
        ? 'quality_area_check'
        : 'area_mismatch',
    'status': status,
    'reviewStatus': rawStatus,
    'customerName': row['customer_name'],
    'customerPhone': row['customer_phone'],
    'address': address,
    'packageName': row['package_name_ru'],
  };
}

Future<List<Map<String, dynamic>>> loadAdminAreaChecks(
    Future<List<Map<String, dynamic>>> Function(int offset, int limit)
        fetch) async {
  final rows = <String, Map<String, dynamic>>{};
  const limit = 200;
  for (var offset = 0;; offset += limit) {
    final page = await fetch(offset, limit);
    for (final row in page) {
      if (row['status'] == 'cancelled' &&
          '${row['admin_comment'] ?? ''}'.contains('duplicate_auto_closed'))
        continue;
      if (row['id'] != null) rows['${row['id']}'] = mapAdminAreaCheck(row);
    }
    if (page.length < limit) break;
  }
  return rows.values.toList();
}
