import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/routing/app_router.dart';
import 'core/settings/theme_provider.dart';
import 'core/theme/app_theme.dart';

class SplitUpApp extends ConsumerWidget {
  const SplitUpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    final router = createAppRouter(
      currentThemeMode: themeMode,
      onThemeModeChanged: (newMode) {
        ref.read(themeModeProvider.notifier).setThemeMode(newMode);
      },
    );

    return MaterialApp.router(
      title: 'SplitUp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
