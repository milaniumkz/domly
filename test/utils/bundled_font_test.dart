import 'package:domly/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
