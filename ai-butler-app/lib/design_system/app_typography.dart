import 'package:flutter/material.dart';

/// 7 級字體階層（Requirement 17.3）
///
/// 不使用 google_fonts：該套件在執行期下載字型，現場離線 demo 會取不到字。
/// 改用平台預設中文字型（Android: Noto Sans CJK / iOS: PingFang TC），
/// 以 fontFamilyFallback 明確指定，避免不同機器渲染差異。
class AppTypography {
  AppTypography._();

  static const List<String> _fallback = <String>[
    'Noto Sans TC',
    'Noto Sans CJK TC',
    'PingFang TC',
    'Microsoft JhengHei',
    'sans-serif',
  ];

  static const TextStyle display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.25,
    fontFamilyFallback: _fallback,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.3,
    fontFamilyFallback: _fallback,
  );

  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
    fontFamilyFallback: _fallback,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.6,
    fontFamilyFallback: _fallback,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.6,
    fontFamilyFallback: _fallback,
  );

  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
    fontFamilyFallback: _fallback,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    fontFamilyFallback: _fallback,
  );

  /// 對應到 Material 的 TextTheme，讓未特別指定樣式的元件也吃到字階。
  static TextTheme textTheme(Color primary, Color secondary) => TextTheme(
        displaySmall: display.copyWith(color: primary),
        headlineMedium: headline.copyWith(color: primary),
        titleMedium: title.copyWith(color: primary),
        bodyLarge: bodyLarge.copyWith(color: primary),
        bodyMedium: body.copyWith(color: primary),
        labelLarge: label.copyWith(color: primary),
        bodySmall: caption.copyWith(color: secondary),
      );
}
