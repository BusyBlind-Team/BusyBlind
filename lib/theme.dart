import 'package:flutter/material.dart';

/// 视觉基调：暗夜 + 暖金。Low-Poly 部件见 widgets/。
abstract final class AppTheme {
  static const Color bg = Color(0xFF0B0B10);
  static const Color ink = Color(0xFFE8DFC8);
  static const Color inkDim = Color(0x88E8DFC8);
  static const Color inkFaint = Color(0x44E8DFC8);
  static const Color gold = Color(0xFFD8B36A);
  static const Color goldDim = Color(0x66D8B36A);

  static ThemeData get data => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.dark(
      primary: gold,
      surface: bg,
      onSurface: ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
    ),
  );
}
