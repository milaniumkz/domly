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
