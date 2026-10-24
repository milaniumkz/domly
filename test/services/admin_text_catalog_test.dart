import 'package:domly/services/admin_text_catalog.dart';
import 'package:domly/localization/translation_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled text is editable even before first server synchronization', () async {
    final rows = await loadAdminTextCatalog((offset, limit) async => [], ['Ваш прогресс']);
    expect(rows.single['source'], 'Ваш прогресс');
    expect((rows.single['locales'] as Map)['ru'], 'Ваш прогресс');
    expect((rows.single['locales'] as Map)['kk'], isNotEmpty);
  });

  test('loads later pages, exposes both languages and preserves source after editing', () async {
    const source = 'Ваш прогресс';
    final key = TranslationController.translationKey(source);
    final calls = <int>[];
    final rows = await loadAdminTextCatalog((offset, limit) async {
      calls.add(offset);
      if (offset == 0) return List.generate(200, (i) => {'key': 'other_$i', 'ru': 'Текст $i'});
      return [{'key': key, 'ru': 'Мой уровень', 'kk': 'Менің деңгейім'}];
    }, [source]);
    expect(calls, [0, 200]);
    expect(rows.length, 201);
    final edited = rows.singleWhere((row) => row['id'] == key);
    expect(edited['source'], source);
    expect(edited['locales'], {'ru': 'Мой уровень', 'kk': 'Менің деңгейім'});
  });
}
