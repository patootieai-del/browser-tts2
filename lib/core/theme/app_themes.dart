import 'package:flutter/material.dart';
import '../../services/settings_service.dart';

class ThemeSpec {
  final String label;
  final IconData icon;
  final Color seed;
  final Brightness brightness;
  final Color? scaffold;
  const ThemeSpec(this.label, this.icon, this.seed, this.brightness,
      {this.scaffold});
}

class AppThemes {
  static const specs = <ThemeChoice, ThemeSpec>{
    ThemeChoice.system:
        ThemeSpec('Follow system', Icons.brightness_auto, Color(0xFF4F6BED), Brightness.light),
    ThemeChoice.light:
        ThemeSpec('Light', Icons.light_mode, Color(0xFF4F6BED), Brightness.light),
    ThemeChoice.dark:
        ThemeSpec('Dark', Icons.dark_mode, Color(0xFF8AB4F8), Brightness.dark),
    ThemeChoice.midnight: ThemeSpec('Midnight blue', Icons.nights_stay,
        Color(0xFF2B5CE6), Brightness.dark, scaffold: Color(0xFF0B1020)),
    ThemeChoice.sepia: ThemeSpec('Sepia (easy read)', Icons.menu_book,
        Color(0xFF9A6A3A), Brightness.light, scaffold: Color(0xFFF4ECD8)),
    ThemeChoice.dracula: ThemeSpec('Dracula', Icons.bug_report,
        Color(0xFFBD93F9), Brightness.dark, scaffold: Color(0xFF282A36)),
    ThemeChoice.oled: ThemeSpec('OLED black', Icons.contrast,
        Color(0xFF00E5A0), Brightness.dark, scaffold: Color(0xFF000000)),
  };

  static ThemeData build(ThemeChoice choice, Brightness platform,
      {ColorScheme? dynamicScheme}) {
    final spec = specs[choice]!;
    final brightness =
        choice == ThemeChoice.system ? platform : spec.brightness;

    ColorScheme scheme;
    if (dynamicScheme != null && choice == ThemeChoice.system) {
      scheme = dynamicScheme;
    } else {
      scheme = ColorScheme.fromSeed(
          seedColor: spec.seed, brightness: brightness);
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor:
          choice == ThemeChoice.system ? null : spec.scaffold,
      appBarTheme: AppBarTheme(
        backgroundColor: spec.scaffold ?? scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: spec.scaffold ?? scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: spec.scaffold ?? scheme.surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withOpacity(.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      sliderTheme: const SliderThemeData(year2023: false),
    );
  }
}
