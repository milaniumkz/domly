/// City-wide coverage does not require enrollment of an individual building.
bool hasCityWideService(String? city) {
  final normalized = (city ?? '')
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[\s.\-]'), '')
      .replaceFirst(RegExp(r'^(город|г)'), '');
  return const {'астана', 'astana', 'нурсултан', 'nursultan'}
      .contains(normalized);
}
