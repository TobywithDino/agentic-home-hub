import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/design_system/app_theme.dart';
import 'package:ai_butler_app/providers/theme_providers.dart';
import 'package:ai_butler_app/router/app_router.dart';

class AiButlerApp extends ConsumerWidget {
  const AiButlerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeNotifier = ref.watch(themeNotifierProvider.notifier);

    return MaterialApp.router(
      title: 'AI 生活管家',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeNotifier.flutterThemeMode,
      routerConfig: router,
    );
  }
}
