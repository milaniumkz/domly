/// PostgreSQL date values may arrive as either YYYY-MM-DD or an ISO timestamp.
String calendarDateKey(Object? value) {
  final text = value is DateTime ? value.toIso8601String() : '$value';
  return RegExp(r'^\d{4}-\d{2}-\d{2}(?:$|T)').hasMatch(text)
      ? text.substring(0, 10)
      : '';
}

/// Keep calendar requests bounded while preserving date order and failing closed
/// for days the backend could not calculate.
Future<List<Map<String, dynamic>>> loadAvailableCalendarDays(
  List<String> dates, {
  required Future<List<Map<String, dynamic>>> Function(String) loadSlots,
}) async {
  final results = List<Map<String, dynamic>?>.filled(dates.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < dates.length) {
      final index = next++;
      try {
        final slots = await loadSlots(dates[index]);
        if (slots.isNotEmpty) {
          results[index] = {'date': dates[index], 'availableSlotsCount': slots.length, 'backend': true};
        }
      } catch (_) {
        // Unavailable and failed dates must not become bookable.
      }
    }
  }
  await Future.wait(List.generate(dates.length.clamp(0, 4), (_) => worker()));
  return results.whereType<Map<String, dynamic>>().toList();
}
