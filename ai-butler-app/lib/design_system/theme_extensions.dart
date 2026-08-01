import 'package:flutter/material.dart';
import 'package:ai_butler_app/design_system/app_colors.dart';

/// 把 Design_System 的值掛到 ThemeData 上，讓畫面一律透過
/// `context.butler` 取用，而非直接 import 色票常數（Requirement 17.8-9）。
@immutable
class ButlerTheme extends ThemeExtension<ButlerTheme> {
  const ButlerTheme({
    required this.accent,
    required this.secondaryText,
    required this.surfaceVariant,
    required this.border,
    required this.success,
    required this.warning,
    required this.error,
    required this.neutral,
    required this.successSurface,
    required this.warningSurface,
    required this.errorSurface,
    required this.neutralSurface,
    required this.cardShadow,
    required this.floatingShadow,
  });

  final Color accent;
  final Color secondaryText;
  final Color surfaceVariant;
  final Color border;
  final Color success;
  final Color warning;
  final Color error;
  final Color neutral;
  final Color successSurface;
  final Color warningSurface;
  final Color errorSurface;
  final Color neutralSurface;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> floatingShadow;

  static const ButlerTheme light = ButlerTheme(
    accent: AppColors.accent,
    secondaryText: AppColors.secondaryText,
    surfaceVariant: AppColors.surfaceVariant,
    border: AppColors.border,
    success: AppColors.success,
    warning: AppColors.warning,
    error: AppColors.error,
    neutral: AppColors.neutral,
    successSurface: AppColors.successSurface,
    warningSurface: AppColors.warningSurface,
    errorSurface: AppColors.errorSurface,
    neutralSurface: AppColors.neutralSurface,
    cardShadow: <BoxShadow>[
      BoxShadow(color: Color(0x0F2A2724), blurRadius: 12, offset: Offset(0, 2)),
    ],
    floatingShadow: <BoxShadow>[
      BoxShadow(color: Color(0x1A2A2724), blurRadius: 20, offset: Offset(0, 4)),
    ],
  );

  static const ButlerTheme dark = ButlerTheme(
    accent: AppColors.accent,
    secondaryText: AppColors.darkTextSecondary,
    surfaceVariant: AppColors.darkSurfaceVariant,
    border: AppColors.darkBorder,
    success: Color(0xFF7FD48A),
    warning: Color(0xFFE0B060),
    error: Color(0xFFEF8A8A),
    neutral: AppColors.darkTextSecondary,
    successSurface: Color(0xFF1E2E20),
    warningSurface: Color(0xFF33291A),
    errorSurface: Color(0xFF33201F),
    neutralSurface: Color(0xFF2B2721),
    cardShadow: <BoxShadow>[
      BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 2)),
    ],
    floatingShadow: <BoxShadow>[
      BoxShadow(color: Color(0x4D000000), blurRadius: 20, offset: Offset(0, 4)),
    ],
  );

  @override
  ButlerTheme copyWith({
    Color? accent,
    Color? secondaryText,
    Color? surfaceVariant,
    Color? border,
    Color? success,
    Color? warning,
    Color? error,
    Color? neutral,
    Color? successSurface,
    Color? warningSurface,
    Color? errorSurface,
    Color? neutralSurface,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? floatingShadow,
  }) {
    return ButlerTheme(
      accent: accent ?? this.accent,
      secondaryText: secondaryText ?? this.secondaryText,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      border: border ?? this.border,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      neutral: neutral ?? this.neutral,
      successSurface: successSurface ?? this.successSurface,
      warningSurface: warningSurface ?? this.warningSurface,
      errorSurface: errorSurface ?? this.errorSurface,
      neutralSurface: neutralSurface ?? this.neutralSurface,
      cardShadow: cardShadow ?? this.cardShadow,
      floatingShadow: floatingShadow ?? this.floatingShadow,
    );
  }

  @override
  ButlerTheme lerp(ThemeExtension<ButlerTheme>? other, double t) {
    if (other is! ButlerTheme) return this;
    return ButlerTheme(
      accent: Color.lerp(accent, other.accent, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      successSurface: Color.lerp(successSurface, other.successSurface, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      errorSurface: Color.lerp(errorSurface, other.errorSurface, t)!,
      neutralSurface: Color.lerp(neutralSurface, other.neutralSurface, t)!,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      floatingShadow: t < 0.5 ? floatingShadow : other.floatingShadow,
    );
  }
}

extension ButlerThemeContext on BuildContext {
  /// Design_System 的擴充色票。缺失時回退淺色，避免在任何畫面拋 null 錯誤。
  ButlerTheme get butler =>
      Theme.of(this).extension<ButlerTheme>() ?? ButlerTheme.light;

  ColorScheme get scheme => Theme.of(this).colorScheme;

  TextTheme get texts => Theme.of(this).textTheme;
}
