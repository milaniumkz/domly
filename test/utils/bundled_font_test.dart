import 'dart:typed_data';
import 'package:domly/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled fallback supplies the tenge glyph in both themes', () async {
    final currency = await rootBundle.load('assets/fonts/NotoSans-Currency.ttf');
    expect(hasGlyph(currency, 0x20b8), isTrue);
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      expect(theme.textTheme.bodyMedium?.fontFamilyFallback, contains('DomlyCurrency'));
    }
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  test('both themes have a bundled text fallback without a font CDN', () async {
    final bytes = await rootBundle.load('assets/fonts/Roboto-Variable.ttf');
    expect(bytes.lengthInBytes, greaterThan(100000));
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      expect(
          theme.textTheme.bodyMedium?.fontFamilyFallback, contains('Roboto'));
    }
  });
}

// Read cmap directly: loading a font alone does not prove it contains ₸.
bool hasGlyph(ByteData data, int codepoint) {
  int u16(int offset) => data.getUint16(offset);
  int u32(int offset) => data.getUint32(offset);
  int? cmap;
  for (var i = 0; i < u16(4); i++) {
    final entry = 12 + i * 16;
    if (u32(entry) == 0x636d6170) cmap = u32(entry + 8);
  }
  if (cmap == null) return false;
  for (var i = 0; i < u16(cmap + 2); i++) {
    final table = cmap + u32(cmap + 4 + i * 8 + 4);
    if (u16(table) == 12) {
      for (var j = 0; j < u32(table + 12); j++) {
        final group = table + 16 + j * 12;
        if (codepoint >= u32(group) && codepoint <= u32(group + 4)) {
          return u32(group + 8) + codepoint - u32(group) != 0;
        }
      }
    } else if (u16(table) == 4 && codepoint <= 0xffff) {
      final count = u16(table + 6) ~/ 2;
      final ends = table + 14, starts = ends + count * 2 + 2;
      final deltas = starts + count * 2, ranges = deltas + count * 2;
      for (var j = 0; j < count; j++) {
        if (codepoint < u16(starts + j * 2) || codepoint > u16(ends + j * 2)) continue;
        final delta = u16(deltas + j * 2), range = u16(ranges + j * 2);
        if (range == 0) return (codepoint + delta) & 0xffff != 0;
        final glyph = u16(ranges + j * 2 + range + (codepoint - u16(starts + j * 2)) * 2);
        return glyph != 0 && (glyph + delta) & 0xffff != 0;
      }
    }
  }
  return false;
}
