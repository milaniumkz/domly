/// Includes the finishing date for visits that continue past midnight.
String cleaningTimeRange(String start, String end,
    {dynamic date, dynamic durationMinutes}) {
  if (end.isEmpty) return start;
  final parts = start.split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  final duration = num.tryParse('$durationMinutes')?.toInt() ?? 0;
  final days = duration > 0
      ? (hour * 60 + minute + duration) ~/ 1440
      : (end.compareTo(start) < 0 ? 1 : 0);
  final day = DateTime.tryParse('$date');
  if (days > 0 && day != null) {
    final finish =
        day.add(Duration(days: days)).toIso8601String().substring(0, 10);
    return '$start - $end ($finish)';
  }
  return '$start - $end';
}
