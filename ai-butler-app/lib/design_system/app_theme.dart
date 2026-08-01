import 'package:flutter/material.dart';
import 'package:ai_butler_app/design_system/app_colors.dart';
import 'package:ai_butler_app/design_system/app_motion.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';

/// 組出淺色與深色 ThemeData（Requirement 17.8-10、20.1）
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(
        brightness: Brightness.light,
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryContainer,
        background: AppColors.background,
        surface: AppColors.surface,
        textPrimary: AppColors.textPrimary,
        textSecondary: AppColors.textSecondary,
        border: AppColors.border,
        extension: ButlerTheme.light,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        primary: AppColors.darkPrimary,
        primaryContainer: const Color(0xFF24463A),
        background: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        textPrimary: AppColors.darkTextPrimary,
        textSecondary: AppColors.darkTextSecondary,
        border: AppColors.darkBorder,
        extension: ButlerTheme.dark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color primaryContainer,
    required Color background,
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
    required ButlerTheme extension,
  }) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: isLight ? Colors.white : const Color(0xFF0B2418),
      primaryContainer: primaryContainer,
      onPrimaryContainer: isLight ? const Color(0xFF1B4A37) : AppColors.darkTextPrimary,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      error: extension.error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: extension.surfaceVariant,
      onSurfaceVariant: textSecondary,
      outline: border,
    );

    final textTheme = AppTypography.textTheme(textPrimary, textSecondary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[extension],

      // 頁面轉場統一由 router 的 Page 工廠決定，這裡關掉預設的 Material 轉場，
      // 避免兩套動畫疊加造成拖曳感（Requirement 18.1-3）
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.title.copyWith(color: textPrimary),
      ),

      cardTheme: CardTheme(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppTouch.minTarget),
          backgroundColor: primary,
          foregroundColor: scheme.onPrimary,
          textStyle: AppTypography.label.copyWith(fontSize: 15),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          animationDuration: AppMotion.press,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppTouch.minTarget),
          foregroundColor: primary,
          side: BorderSide(color: border),
          textStyle: AppTypography.label.copyWith(fontSize: 15),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          animationDuration: AppMotion.press,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: AppTypography.label,
          minimumSize: const Size(AppTouch.minTarget, AppTouch.minTarget),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: AppTouch.minTargetSize,
          foregroundColor: textPrimary,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        hintStyle: AppTypography.body.copyWith(color: textSecondary),
        labelStyle: AppTypography.body.copyWith(color: textSecondary),
        errorStyle: AppTypography.caption.copyWith(color: extension.error),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: extension.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdAll,
          borderSide: BorderSide(color: extension.error, width: 1.6),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: extension.surfaceVariant,
        selectedColor: primaryContainer,
        side: BorderSide(color: border),
        labelStyle: AppTypography.label.copyWith(color: textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
      ),

      dialogTheme: DialogTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        titleTextStyle: AppTypography.title.copyWith(color: textPrimary),
        contentTextStyle: AppTypography.body.copyWith(color: textSecondary),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        selectedLabelStyle: AppTypography.caption,
        unselectedLabelStyle: AppTypography.caption,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: textPrimary,
        contentTextStyle: AppTypography.body.copyWith(color: surface),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    );
  }
}
