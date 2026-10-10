import 'package:flutter/material.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class SplitUpApp extends StatefulWidget {
  const SplitUpApp({super.key});

  @override
  State<SplitUpApp> createState() => _SplitUpAppState();
}

class _SplitUpAppState extends State<SplitUpApp> {
  ThemeMode _themeMode = ThemeMode.dark; // Default dark theme as specified in DESIGN.md

  @override
  Widget build(BuildContext context) {
    final router = createAppRouter(
      currentThemeMode: _themeMode,
      onThemeModeChanged: (newMode) => setState(() => _themeMode = newMode),
    );

    return MaterialApp.router(
      title: 'SplitUp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      routerConfig: router,
    );
  }
}
