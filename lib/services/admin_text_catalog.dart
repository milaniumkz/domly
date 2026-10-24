import '../localization/kazakh_translations.dart';
import '../localization/builtin_translations.dart';
import '../localization/translation_controller.dart';

/// Loads every server page and keeps immutable keys separate from editable text.
Future<List<Map<String, dynamic>>> loadAdminTextCatalog(
  Future<List<Map<String, dynamic>>> Function(int offset, int limit) fetch,
  Iterable<String> sources,
) async {
  final originals = {
    for (final source in sources)
      TranslationController.translationKey(source): source,
  };
  final result = <String, Map<String, dynamic>>{
    for (final entry in originals.entries)
      entry.key: {'id': entry.key, 'key': entry.key, 'source': entry.value,
        'locales': {'ru': entry.value, 'kk': kBuiltinTranslations[entry.value]?['kk'] ?? kKazakhTranslations[entry.value] ?? ''}},
  };
  const limit = 200;
  for (var offset = 0;; offset += limit) {
    final page = await fetch(offset, limit);
    for (final row in page) {
      final key = (row['key'] ?? row['id'] ?? '').toString();
      result[key] = {
        ...row,
        'id': key,
        'source': originals[key] ?? row['source'] ?? row['ru'] ?? key,
        'locales': {'ru': row['ru'] ?? '', 'kk': row['kk'] ?? ''},
      };
    }
    if (page.length < limit) break;
  }
  return result.values.toList();
}
