List<String> bookingAddonIds(Map<String, dynamic> selection) {
  final ids = <String>{};
  for (final key in ['addonsDetailed', 'newAddonsDetailed']) {
    for (final item in (selection[key] as List? ?? const []).whereType<Map>()) {
      final id = (item['id'] ?? item['addonId'] ?? '').toString().trim();
      if (id.isNotEmpty) ids.add(id);
    }
  }
  return ids.toList();
}
