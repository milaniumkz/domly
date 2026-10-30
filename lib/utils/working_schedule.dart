import 'dart:convert';
import '../localization/translation_controller.dart';

String workScheduleDay(dynamic value) => '$value'.split('T').first;
List<Map<String, dynamic>> workScheduleDays(
    String monday, List<dynamic> saved) {
  final start = DateTime.parse(monday);
  return List.generate(7, (i) {
    final day = start.add(Duration(days: i));
    final key =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final existing = saved
        .whereType<Map>()
        .where((row) => workScheduleDay(row['date']) == key)
        .firstOrNull;
    return {
      'date': key,
      'working': existing?['working'] == true,
      'startTime': existing?['startTime'] ?? '08:00',
      'endTime': existing?['endTime'] ?? '18:00'
    };
  });
}

String workScheduleStatus(dynamic value) =>
    const {
      'pending': 'На одобрении',
      'approved': 'Одобрен',
      'rejected': 'Отклонён',
      'superseded': 'Заменён новой заявкой'
    }['$value'] ??
    'Не настроен';
String workScheduleDateLabel(dynamic value) {
  final date = DateTime.tryParse(workScheduleDay(value));
  if (date == null) return '—';
  const weekdays = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье'
  ];
  return '${weekdays[date.weekday - 1].tr()}, ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

/// Ignores list ordering and irrelevant clock values on days off.
bool workScheduleMatches(List<dynamic> draft, List<dynamic> saved) {
  List<Map<String, dynamic>> normalized(List<dynamic> days) => days
      .whereType<Map>()
      .map((day) => {
            'date': workScheduleDay(day['date']),
            'working': day['working'] == true,
            if (day['working'] == true) ...{
              'startTime': '${day['startTime']}'
                  .substring(0, '${day['startTime']}'.length.clamp(0, 5)),
              'endTime': '${day['endTime']}'
                  .substring(0, '${day['endTime']}'.length.clamp(0, 5)),
            },
          })
      .toList()
    ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
  return jsonEncode(normalized(draft)) == jsonEncode(normalized(saved));
}
