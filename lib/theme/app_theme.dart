import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryGreen = Color(0xFF3D8A63);
  static const Color accentGreen = Color(0xFF8FD0AE);
  static const Color primaryTerracotta = Color(0xFFC56F4B);
  static const Color primaryTerracottaDark = Color(0xFFA75736);
  static const Color accentTerracotta = Color(0xFFE8B29D);
  static const Color backgroundCream = Color(0xFFF9FCF8);
  static const Color lightGreen = Color(0xFFEAF6EE);
  static const Color darkText = Color(0xFF20382B);
  static const Color mutedText = Color(0xFF5E7B69);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: primaryGreen,
      secondary: accentGreen,
      surface: backgroundCream,
      onPrimary: Colors.white,
      onSecondary: darkText,
      onSurface: darkText,
    ),
    scaffoldBackgroundColor: backgroundCream,
    fontFamily: 'Inter',
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: darkText,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: darkText,
      ),
      displaySmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: darkText,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: darkText,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: darkText,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        color: darkText,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: mutedText,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        color: mutedText,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return primaryTerracotta.withValues(alpha: 0.45);
          }
          if (states.contains(WidgetState.pressed)) {
            return primaryTerracottaDark;
          }
          return primaryTerracotta;
        }),
        foregroundColor: WidgetStateProperty.all(Colors.white),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.16);
          }
          if (states.contains(WidgetState.hovered)) {
            return Colors.white.withValues(alpha: 0.08);
          }
          return null;
        }),
        splashFactory: InkRipple.splashFactory,
        animationDuration: const Duration(milliseconds: 140),
        elevation: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return 1;
          }
          if (states.contains(WidgetState.hovered)) {
            return 2;
          }
          return 0;
        }),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(primaryTerracotta),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return primaryTerracotta.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered)) {
            return primaryTerracotta.withValues(alpha: 0.06);
          }
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          final width = states.contains(WidgetState.pressed) ? 1.5 : 1.0;
          return BorderSide(
            color: primaryTerracotta.withValues(alpha: 0.45),
            width: width,
          );
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return primaryTerracotta.withValues(alpha: 0.10);
          }
          if (states.contains(WidgetState.hovered)) {
            return primaryTerracotta.withValues(alpha: 0.05);
          }
          return null;
        }),
        splashFactory: InkRipple.splashFactory,
        animationDuration: const Duration(milliseconds: 140),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(primaryTerracotta),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return primaryTerracotta.withValues(alpha: 0.10);
          }
          if (states.contains(WidgetState.hovered)) {
            return primaryTerracotta.withValues(alpha: 0.05);
          }
          return null;
        }),
        splashFactory: InkRipple.splashFactory,
        animationDuration: const Duration(milliseconds: 140),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return primaryTerracotta.withValues(alpha: 0.45);
          }
          if (states.contains(WidgetState.pressed)) {
            return primaryTerracottaDark;
          }
          return primaryTerracotta;
        }),
        foregroundColor: WidgetStateProperty.all(Colors.white),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return Colors.white.withValues(alpha: 0.16);
          }
          if (states.contains(WidgetState.hovered)) {
            return Colors.white.withValues(alpha: 0.08);
          }
          return null;
        }),
        splashFactory: InkRipple.splashFactory,
        animationDuration: const Duration(milliseconds: 140),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accentTerracotta.withValues(alpha: 0.35)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accentTerracotta.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryGreen, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
  );
}
