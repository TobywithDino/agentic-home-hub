import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/providers/repository_providers.dart';

/// 主題模式（Requirement 20.3）。
enum AppThemeMode { system, light, dark }

class ThemeNotifier extends Notifier<AppThemeMode> {
  static const String _key = 'app_theme_mode';

  @override
  AppThemeMode build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final stored = prefs.getString(_key);
    return switch (stored) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = mode;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_key, mode.name);
  }

  ThemeMode get flutterThemeMode => switch (state) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };
}

final themeNotifierProvider =
    NotifierProvider<ThemeNotifier, AppThemeMode>(ThemeNotifier.new);
