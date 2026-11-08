import 'backend_compat.dart';

enum CleanerHistoryPeriod { all, week, month, year }

DateTime? cleanerHistoryDate(Map<String, dynamic> order) {
  for (final value in [
    order['completedAt'],
    order['completed_at'],
    order['date'],
    order['scheduledFor'],
    order['scheduled_date'],
    order['createdAt'],
    order['created_at']
  ]) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    final parsed = DateTime.tryParse('$value');
    if (parsed != null) return parsed;
  }
  return null;
}

List<Map<String, dynamic>> cleanerOrderHistory(List<Map<String, dynamic>> rows,
    {CleanerHistoryPeriod period = CleanerHistoryPeriod.all, DateTime? now}) {
  final date = now ?? DateTime.now();
  final cutoff = switch (period) {
    CleanerHistoryPeriod.all => null,
    CleanerHistoryPeriod.week => date.subtract(const Duration(days: 7)),
    CleanerHistoryPeriod.month => DateTime(date.year, date.month),
    CleanerHistoryPeriod.year => DateTime(date.year),
  };
  final result = rows.where((row) {
    if ('${row['orderStatus'] ?? row['status']}'.trim().toLowerCase() !=
        'completed') return false;
    final completed = cleanerHistoryDate(row);
    return cutoff == null || (completed != null && !completed.isBefore(cutoff));
  }).toList();
  result.sort((a, b) {
    final compared = (cleanerHistoryDate(b) ?? DateTime(1970))
        .compareTo(cleanerHistoryDate(a) ?? DateTime(1970));
    return compared != 0 ? compared : '${b['id']}'.compareTo('${a['id']}');
  });
  return result;
}
