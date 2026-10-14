import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UiPreferences extends ChangeNotifier {
  static final instance = UiPreferences();
  bool darkMode = false;
  bool animations = true;
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    darkMode = prefs.getBool('domly_ui_dark_mode') ?? false;
    animations = prefs.getBool('domly_ui_animations') ?? true;
    notifyListeners();
  }

  Future<void> update(Map<String, dynamic> values) async {
    final beforeDark = darkMode, beforeAnimations = animations;
    if (values['darkMode'] is bool) darkMode = values['darkMode'];
    if (values['animations'] is bool) animations = values['animations'];
    if (beforeDark == darkMode && beforeAnimations == animations) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('domly_ui_dark_mode', darkMode);
    await prefs.setBool('domly_ui_animations', animations);
  }
}
