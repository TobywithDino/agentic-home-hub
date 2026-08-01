import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_motion.dart';

/// 頁面轉場工廠（Requirement 18.1-3）
///
/// 三種轉場集中在此，各畫面不自己刻動畫。這是修掉「轉場卡卡的」的核心：
/// 之前 router 全用 `NoTransitionPage`，所以畫面之間是硬切，
/// 沒有任何連續感。
class AppTransitions {
  AppTransitions._();

  /// 共享軸水平轉場。用於同層或父子層導覽
  /// （服務商列表 → 詳情、首頁 → 帳戶頁）。
  static CustomTransitionPage<T> sharedAxis<T>({
    required Widget child,
    required GoRouterState state,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: AppMotion.page,
      reverseTransitionDuration: AppMotion.page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (AppMotion.resolve(context, AppMotion.page) == Duration.zero) {
          return child;
        }
        return _SharedAxisTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        );
      },
    );
  }

  /// 淡入向上位移。用於登入 → 首頁這種「換場景」的導覽。
  static CustomTransitionPage<T> fadeThrough<T>({
    required Widget child,
    required GoRouterState state,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: AppMotion.page,
      reverseTransitionDuration: AppMotion.page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (AppMotion.resolve(context, AppMotion.page) == Duration.zero) {
          return child;
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.decelerate,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// 由底部升起的全螢幕頁（對話畫面、表單）。
  static CustomTransitionPage<T> modal<T>({
    required Widget child,
    required GoRouterState state,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: AppMotion.page,
      reverseTransitionDuration: AppMotion.page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (AppMotion.resolve(context, AppMotion.page) == Duration.zero) {
          return child;
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.emphasized,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.14),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  /// 分頁切換用的無轉場頁（切換動畫由 App_Shell 的
  /// AnimatedSwitcher 負責，Requirement 18.6）。
  static NoTransitionPage<T> noTransition<T>({
    required Widget child,
    required GoRouterState state,
  }) {
    return NoTransitionPage<T>(key: state.pageKey, child: child);
  }
}

/// Material 的 shared axis (horizontal) 行為：
/// 新頁由右側 30px 淡入，舊頁向左淡出。
class _SharedAxisTransition extends StatelessWidget {
  const _SharedAxisTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enter = CurvedAnimation(parent: animation, curve: AppMotion.emphasized);
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.emphasized,
    );

    return AnimatedBuilder(
      animation: secondaryAnimation,
      child: child,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(-30 * exit.value, 0),
          child: Opacity(
            opacity: 1 - exit.value * 0.4,
            child: AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(30 * (1 - enter.value), 0),
                  child: Opacity(opacity: enter.value, child: child),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
