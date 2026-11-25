import 'dart:math' as math;

String adminCalendarDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
num calendarNumber(Object? value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
int calendarClockMinutes(Object? clock) {
  final match = RegExp(r'^(\d{2}):(\d{2})').firstMatch('$clock');
  return match == null ? 0 : int.parse(match[1]!) * 60 + int.parse(match[2]!);
}

String calendarClockLabel(int minute) =>
    '${((minute % 1440) ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
bool calendarCancelled(Object? status) =>
    {'cancelled', 'canceled', 'draft'}.contains('$status');

class AdminCalendarVisit {
  const AdminCalendarVisit(this.order, this.assignment);
  final Map<String, dynamic> order;
  final Map<String, dynamic> assignment;
  String get id => '${order['id']}';
  String get cleanerId => '${assignment['cleaner_id']}';
  String get day =>
      '${order['service_date'] ?? order['scheduled_date']}'.split('T').first;
  double get area =>
      calendarNumber(assignment['allocated_area'] ?? order['area']).toDouble();
  String get parentStatus => '${order['status']}';
  String get status => calendarCancelled(parentStatus)
      ? 'cancelled'
      : parentStatus == 'completed'
          ? 'completed'
          : '${assignment['member_status'] ?? parentStatus}';
  bool get occupiesTime =>
      !calendarCancelled(parentStatus) && parentStatus != 'completed';
  bool get countsArea => !calendarCancelled(parentStatus);
  int get start => calendarClockMinutes(order['start_time']);
  int get duration {
    final saved = calendarNumber(order['estimated_duration_minutes']).toInt();
    if (saved > 0) return saved;
    final diff = calendarClockMinutes(order['end_time']) - start;
    return diff < 0 ? diff + 1440 : diff;
  }

  int startOn(String selectedDay) =>
      start -
      DateTime.parse('${selectedDay}T00:00:00Z')
              .difference(DateTime.parse('${day}T00:00:00Z'))
              .inDays *
          1440;
  int endOn(String selectedDay) => startOn(selectedDay) + duration;
  bool appearsOn(String selectedDay) => duration == 0
      ? selectedDay == day
      : startOn(selectedDay) < 1440 && endOn(selectedDay) > 0;
}

class AdminCalendarSnapshot {
  AdminCalendarSnapshot(this.raw) {
    orders = maps(raw['orders']);
    cleaners = maps(raw['cleaners']);
    final indexed = {for (final order in orders) '${order['id']}': order};
    visits = [
      for (final row in maps(raw['assignments']))
        if (indexed.containsKey('${row['order_id']}'))
          AdminCalendarVisit(indexed['${row['order_id']}']!, row)
    ];
    final lower = DateTime.tryParse('${raw['from']}T00:00:00Z');
    final upper = DateTime.tryParse('${raw['to']}T00:00:00Z');
    final daysByOrder = <String, List<String>>{};
    for (final order in orders) {
      final visit = AdminCalendarVisit(order, const {}),
          start = DateTime.parse(
              '${AdminCalendarVisit(order, const {}).day}T00:00:00Z');
      final finish = start.add(
          Duration(minutes: visit.start + math.max(1, visit.duration).toInt() - 1));
      var cursor = lower != null && start.isBefore(lower) ? lower : start;
      final end = upper != null && finish.isAfter(upper)
          ? upper
          : DateTime.utc(finish.year, finish.month, finish.day);
      final keys = <String>[];
      while (!cursor.isAfter(end)) {
        final key = adminCalendarDay(cursor);
        keys.add(key);
        (_ordersByDay[key] ??= []).add(order);
        cursor = cursor.add(const Duration(days: 1));
      }
      daysByOrder[visit.id] = keys;
      if (!calendarCancelled(visit.parentStatus))
        _rootAreaByDay[visit.day] = (_rootAreaByDay[visit.day] ?? 0) +
            calendarNumber(order['area']).toDouble();
    }
    for (final visit in visits) {
      for (final day in daysByOrder[visit.id] ?? <String>[]) {
        (_visitsByCleanerDay['${visit.cleanerId}:$day'] ??= []).add(visit);
      }
      if (visit.countsArea) {
        final key = '${visit.cleanerId}:${visit.day}';
        _areaByCleanerDay[key] = (_areaByCleanerDay[key] ?? 0) + visit.area;
      }
    }
    for (final items in _visitsByCleanerDay.values) {
      items.sort((a, b) {
        final date = a.day.compareTo(b.day);
        return date == 0 ? a.start.compareTo(b.start) : date;
      });
    }
  }
  final Map<String, List<Map<String, dynamic>>> _ordersByDay = {};
  final Map<String, List<AdminCalendarVisit>> _visitsByCleanerDay = {};
  final Map<String, double> _areaByCleanerDay = {}, _rootAreaByDay = {};
  final Map<String, dynamic> raw;
  late final List<Map<String, dynamic>> orders, cleaners;
  late final List<AdminCalendarVisit> visits;
  static List<Map<String, dynamic>> maps(Object? value) =>
      (value is List ? value : const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
  double get norm => calendarNumber(raw['areaNorm'] ?? 220).toDouble();
  double get maximum => calendarNumber(raw['areaMaximum'] ?? 250).toDouble();

  List<AdminCalendarVisit> forCleaner(String id, String day,
          {bool includeCancelled = false}) =>
      (_visitsByCleanerDay['$id:$day'] ?? <AdminCalendarVisit>[])
          .where((v) => includeCancelled || !calendarCancelled(v.parentStatus))
          .toList();
  Map<String, dynamic>? workingDay(String id, String day) {
    for (final row in maps(raw['workingDays'])) {
      if (row['cleaner_id'] == id && row['service_date'] == day) return row;
    }
    return null;
  }

  bool approvedWeek(String id, String day) {
    final date = DateTime.parse('${day}T00:00:00Z');
    return maps(raw['approvedWeeks']).any((row) {
      final start = DateTime.tryParse('${row['week_start']}T00:00:00Z');
      return row['cleaner_id'] == id &&
          start != null &&
          date.difference(start).inDays >= 0 &&
          date.difference(start).inDays < 7;
    });
  }

  double dailyArea(String id, String day) => _areaByCleanerDay['$id:$day'] ?? 0;
  List<Map<String, dynamic>> ordersOn(String day,
          {bool includeCancelled = false}) =>
      (_ordersByDay[day] ?? <Map<String, dynamic>>[])
          .where((order) =>
              includeCancelled || !calendarCancelled(order['status']))
          .toList();
  List<Map<String, dynamic>> unassignedOn(String day) =>
      ordersOn(day).where((order) {
        if (order['status'] == 'completed') return false;
        final required =
            calendarNumber(order['required_cleaners'] ?? 1).toInt();
        return visits.where((v) => v.id == '${order['id']}').length < required;
      }).toList();
  double totalArea(String day, {String? cleanerId}) => cleanerId == null
      ? (_rootAreaByDay[day] ?? 0)
      : dailyArea(cleanerId, day);
}

/// Approved shift minus the union of occupied intervals. Completed visits still
/// consume square metres but no longer reserve time, matching the server policy.
List<({int start, int end})> calendarFreeIntervals(
    Map<String, dynamic> shift, List<AdminCalendarVisit> visits, String day) {
  final start = calendarClockMinutes(shift['start_time']);
  final end = calendarClockMinutes(shift['end_time']);
  if (end <= start) return [];
  final busy = visits
      .where((v) => v.occupiesTime)
      .map((v) => (
            start: math.max(start, v.startOn(day)),
            end: math.min(end, v.endOn(day))
          ))
      .where((i) => i.end > i.start)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final free = <({int start, int end})>[];
  var cursor = start;
  for (final interval in busy) {
    if (interval.start > cursor) free.add((start: cursor, end: interval.start));
    cursor = math.max(cursor, interval.end);
  }
  if (cursor < end) free.add((start: cursor, end: end));
  return free;
}
