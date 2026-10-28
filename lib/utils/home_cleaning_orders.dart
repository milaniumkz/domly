import 'customer_home_state.dart';

List<Map<String, dynamic>> orderedHomeCleanings(List<Map<String, dynamic>> orders) {
  const statuses = {'pending_assignment','offered','assigned','confirmed','rescheduled','in_progress'};
  final byId = <String, Map<String, dynamic>>{};
  for (final order in orders) {
    final id = (order['id'] ?? '').toString();
    if (id.isNotEmpty && order['type'] != 'package_purchase' &&
        scheduledCleaningDate(order) != null &&
        statuses.contains(order['orderStatus'] ?? order['status'])) byId[id] = order;
  }
  DateTime start(Map<String, dynamic> o) {
    final day = scheduledCleaningDate(o)!;
    final parts = (o['startTime'] ?? o['time'] ?? '').toString().split(':');
    return DateTime(day.year, day.month, day.day,
      int.tryParse(parts.first) ?? day.hour,
      parts.length > 1 ? int.tryParse(parts[1]) ?? day.minute : day.minute);
  }
  return byId.values.toList()..sort((a,b) {
    final comparison = start(a).compareTo(start(b));
    return comparison != 0 ? comparison : a['id'].toString().compareTo(b['id'].toString());
  });
}
