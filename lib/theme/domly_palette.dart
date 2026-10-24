import 'package:flutter/material.dart';
import '../services/ui_preferences.dart';
import '../localization/translation_controller.dart';

/// Adapts explicit screen colors as well as Material widgets to the selected
/// palette. Brand colors and image pixels remain intact.
class DomlyPalette {
  static bool get isDark => UiPreferences.instance.darkMode;
  static void watch(BuildContext context) {
    Theme.of(context);
    TranslationScope.watch(context);
  }

  static Color background(Color? light) {
    final color = light ?? Colors.transparent;
    if (!isDark || color.a == 0 || color.computeLuminance() < 0.48)
      return color;
    return darkBackground.withValues(alpha: color.a);
  }

  static const darkBackground = Color(0xFF121C17);
  static const darkSurface = Color(0xFF203127);
  static const darkForeground = Color(0xFFF1F6F2);
  static const darkOutline = Color(0xFF496052);

  static Color surface(Color? light) {
    final color = light ?? Colors.transparent;
    if (!isDark || color.a == 0 || color.computeLuminance() < 0.48)
      return color;
    return darkSurface.withValues(alpha: color.a);
  }

  static Color foreground(Color? light) {
    final color = light ?? const Color(0xFF20382B);
    if (!isDark || color.a == 0 || color.computeLuminance() > 0.6) return color;
    final hsv = HSVColor.fromColor(color);
    // Retain the meaning of status/accent colors, raising their brightness.
    if (hsv.saturation > 0.48 && hsv.value > 0.44) {
      return hsv.withValue(hsv.value < 0.8 ? 0.8 : hsv.value).toColor();
    }
    return (color.computeLuminance() > 0.15
            ? const Color(0xFFC1D0C5)
            : darkForeground)
        .withValues(alpha: color.a);
  }

  static Color border(Color? light) {
    final color = light ?? Colors.transparent;
    if (!isDark || color.a == 0) return color;
    final hsv = HSVColor.fromColor(color);
    if (hsv.saturation > 0.65 && (hsv.hue < 45 || hsv.hue > 330))
      return foreground(color);
    return darkOutline.withValues(alpha: color.a < 0.35 ? 0.6 : color.a);
  }
}
