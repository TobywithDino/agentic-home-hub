import 'package:flutter/material.dart';
import 'package:ai_butler_app/design_system/app_colors.dart';

/// 間距刻度（Requirement 17.6）
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// 畫面左右內距。
  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: md);
}

/// 4 級圓角（Requirement 17.4）
class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

/// 3 級陰影（Requirement 17.5）
class AppShadows {
  AppShadows._();

  /// 卡片：貼近表面的柔和陰影。
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F2A2724),
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];

  /// 浮動元件：底部按鈕列、FAB。
  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A2A2724),
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  /// 對話框。
  static const List<BoxShadow> dialog = <BoxShadow>[
    BoxShadow(
      color: Color(0x332A2724),
      blurRadius: 32,
      offset: Offset(0, 8),
    ),
  ];
}

/// 最小觸控目標（Requirement 19.2）
class AppTouch {
  AppTouch._();

  static const double minTarget = 48;
  static const Size minTargetSize = Size(minTarget, minTarget);
}

/// 常用邊框樣式。
class AppBorders {
  AppBorders._();

  static const BorderSide hairline = BorderSide(color: AppColors.border);
}
