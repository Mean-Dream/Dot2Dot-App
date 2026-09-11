import 'package:flutter/material.dart';

class ThemeOption {
  const ThemeOption({
    required this.id,
    required this.label,
    required this.background,
    required this.surface,
    required this.primary,
    required this.onPrimary,
    required this.onSurface,
  });

  final String id;
  final String label;
  final Color background;
  final Color surface;
  final Color primary;
  final Color onPrimary;
  final Color onSurface;

  ThemeData get themeData {
    final scheme = ColorScheme.dark(
      primary: primary,
      onPrimary: onPrimary,
      surface: surface,
      onSurface: onSurface,
      secondary: primary,
      onSecondary: onPrimary,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      cardTheme: CardThemeData(color: surface, elevation: 4),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        inactiveTrackColor: surface,
      ),
    );
  }

  /// Swatch color shown in the theme picker.
  Color get swatch => primary;
}

abstract final class AppTheme {
  static const List<ThemeOption> themes = [cosmic, forest, ocean, dusk, dino, unicorn];

  /// Deep navy + teal — matches the WonderDot app icon.
  static const ThemeOption cosmic = ThemeOption(
    id: 'cosmic',
    label: 'Cosmic',
    background: Color(0xFF080C2A),
    surface: Color(0xFF0F1544),
    primary: Color(0xFF4EDFFF),
    onPrimary: Color(0xFF080C2A),
    onSurface: Color(0xFFF0F4FF),
  );

  static const ThemeOption forest = ThemeOption(
    id: 'forest',
    label: 'Forest',
    background: Color(0xFF111E18),
    surface: Color(0xFF253B30),
    primary: Color(0xFF4EFE98),
    onPrimary: Color(0xFF111E18),
    onSurface: Color(0xFFF1F7F4),
  );

  static const ThemeOption ocean = ThemeOption(
    id: 'ocean',
    label: 'Ocean',
    background: Color(0xFF0D1B2A),
    surface: Color(0xFF1A3550),
    primary: Color(0xFF4FC3F7),
    onPrimary: Color(0xFF0D1B2A),
    onSurface: Color(0xFFE8F4FD),
  );

  static const ThemeOption dusk = ThemeOption(
    id: 'dusk',
    label: 'Dusk',
    background: Color(0xFF1A1128),
    surface: Color(0xFF2E1F42),
    primary: Color(0xFFCE93D8),
    onPrimary: Color(0xFF1A1128),
    onSurface: Color(0xFFF3EEFF),
  );

  /// Prehistoric jungle — dark moss greens with bright lime primary.
  static const ThemeOption dino = ThemeOption(
    id: 'dino',
    label: 'Dino',
    background: Color(0xFF0A1A08),
    surface: Color(0xFF162B12),
    primary: Color(0xFF76C442),
    onPrimary: Color(0xFF0A1A08),
    onSurface: Color(0xFFEDF7E8),
  );

  /// Magical fantasy — deep violet with hot-pink primary.
  static const ThemeOption unicorn = ThemeOption(
    id: 'unicorn',
    label: 'Unicorn',
    background: Color(0xFF14092B),
    surface: Color(0xFF270F50),
    primary: Color(0xFFFF6EC7),
    onPrimary: Color(0xFF14092B),
    onSurface: Color(0xFFFFF0FB),
  );

  static ThemeOption fromId(String id) =>
      themes.firstWhere((t) => t.id == id, orElse: () => cosmic);
}
