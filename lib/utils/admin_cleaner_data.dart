Map<String, dynamic> mapAdminCleaner(Map<String, dynamic> row) {
  final fullName =
      (row['full_name'] ?? row['fullName'] ?? '').toString().trim();
  final status = (row['verification_status'] ?? row['status'] ?? 'new').toString();
  final result = <String, dynamic>{
    ...row,
    'cleanerId': row['id'] ?? row['user_id'],
    'name': fullName.isEmpty ? 'Уборщица' : fullName,
    'fullName': fullName,
    'numericId': row['numeric_id'],
    'verificationStatus': row['verification_status'] ?? 'pending',
    'registrationStatus': row['registration_status'] ?? 'pending',
    'cleanerStatusLabel': {
          'approved': 'Одобрено',
          'pending': 'На проверке',
          'new': 'Новая',
          'rejected': 'Отклонено',
          'blocked': 'Заблокировано'
        }[status] ??
        status,
    'createdAt': row['created_at'],
    'updatedAt': row['updated_at'],
    'verifiedAt': row['verified_at'],
    'workStartDate': row['work_start_date'],
  };
  for (final document
      in (row['documents'] as List? ?? const []).whereType<Map>()) {
    final type = (document['type'] ?? '').toString();
    final url = (document['url'] ?? document['public_url'] ?? '').toString();
    if (type.isNotEmpty && url.isNotEmpty) result.putIfAbsent(type, () => url);
  }
  return result;
}
