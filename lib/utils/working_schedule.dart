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
