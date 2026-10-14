import 'package:domly/services/ui_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme and animations apply and persist across reload', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = UiPreferences();
    await prefs.load();
    await prefs.update({'darkMode': true, 'animations': false});
    expect(prefs.darkMode, isTrue);
    expect(prefs.animations, isFalse);
    final restored = UiPreferences();
    await restored.load();
    expect(restored.darkMode, isTrue);
    expect(restored.animations, isFalse);
    await restored.update({'darkMode': false, 'animations': true});
    expect(restored.darkMode, isFalse);
    expect(restored.animations, isTrue);
  });
}
