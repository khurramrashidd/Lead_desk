import 'package:flutter/material.dart';

/// One place for colours, so the app looks consistent on phone, tablet and web.
class AppTheme {
  static const seed = Color(0xFF3D5AFE);
  static const hot = Color(0xFFE53935);
  static const warm = Color(0xFFFB8C00);
  static const cold = Color(0xFF546E7A);
  static const ai = Color(0xFF5E35B1);
  static const human = Color(0xFF2E7D32);
  static const guard = Color(0xFFC62828);

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    // Kept to the basics so it builds on every recent Flutter version.
    return ThemeData(colorScheme: scheme, useMaterial3: true);
  }

  static Color temperature(String? t) {
    switch (t) {
      case 'hot':
        return hot;
      case 'warm':
        return warm;
      default:
        return cold;
    }
  }
}
