import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_themes.dart';
import 'screens/browser_screen.dart';
import 'services/settings_service.dart';
import 'state/settings_controller.dart';

class VoxApp extends StatelessWidget {
  const VoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>().settings;
    final platform = MediaQuery.platformBrightnessOf(context);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final dyn = s.useDynamicColor
            ? (platform == Brightness.dark ? darkDynamic : lightDynamic)
            : null;

        return MaterialApp(
          title: 'Vox Browser',
          debugShowCheckedModeBanner: false,
          theme: AppThemes.build(s.theme, platform, dynamicScheme: dyn),
          darkTheme: s.theme == ThemeChoice.system
              ? AppThemes.build(ThemeChoice.dark, Brightness.dark,
                  dynamicScheme: s.useDynamicColor ? darkDynamic : null)
              : null,
          themeMode: s.theme == ThemeChoice.system
              ? ThemeMode.system
              : ThemeMode.light, // explicit themes carry their own brightness
          builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx)
                .copyWith(textScaler: TextScaler.linear(s.textScale)),
            child: child!,
          ),
          home: const BrowserScreen(),
        );
      },
    );
  }
}
