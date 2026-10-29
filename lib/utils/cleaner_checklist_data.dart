/// Preserve saved checkboxes and required server tasks when reopening a report.
Map<String, dynamic>? mapCleanerChecklist(
    String orderId, Map<String, dynamic> data) {
  final report =
      Map<String, dynamic>.from((data['report'] as Map?) ?? const {});
  final items = (data['items'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  if (report.isEmpty && items.isEmpty) return null;
  String title(Map<String, dynamic> item) =>
      (item['title_ru'] ?? '').toString();
  return {
    'id': orderId,
    ...report,
    'items': items,
    'completedTasks':
        items.where((item) => item['checked'] == true).map(title).toList(),
    'requiredTasks':
        items.where((item) => item['required'] != false).map(title).toList(),
    'addons': items
        .where((item) =>
            item['checked'] == true && title(item).startsWith('Доп. услуга: '))
        .map((item) => title(item).substring('Доп. услуга: '.length))
        .toList(),
  };
}

/// Cleaning work comes from the report/template, never subscription features.
List<String> cleanerBaseChecklistTasks({
  List<String>? requiredTasks,
  List<Map<String, dynamic>> templateGroups = const [],
}) {
  const standardTasks = [
    'Протереть пыль',
    'Пропылесосить',
    'Вымыть пол',
    'Очистить кухню',
    'Очистить санузел',
  ];
  final template = templateGroups
      .where(
          (group) => group['key'] == 'base_tasks' && group['isActive'] != false)
      .firstOrNull;
  final source =
      requiredTasks ?? (template?['items'] as List? ?? standardTasks);
  final tasks = source
      .map((item) => item.toString().trim())
      .where((task) => task.isNotEmpty && !task.startsWith('Доп. услуга: '))
      .toSet()
      .toList();
  return tasks.isEmpty ? standardTasks : tasks;
}
