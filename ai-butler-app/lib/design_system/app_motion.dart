import 'package:flutter/material.dart';

/// 轉場與動畫的集中定義（Requirement 18）
///
/// 這裡是「卡卡的」問題的主要解法之一：所有畫面共用同一組時長與曲線，
/// 不再由各畫面各自決定。
class AppMotion {
  AppMotion._();

  /// 頁面轉場，落在需求要求的 250–350ms 區間（Requirement 18.2）
  static const Duration page = Duration(milliseconds: 300);

  /// 底部導覽分頁切換（Requirement 18.6）
  static const Duration tab = Duration(milliseconds: 200);

  /// 按壓回饋（Requirement 18.9）
  static const Duration press = Duration(milliseconds: 100);

  /// 列表項目進場的單項延遲上限（Requirement 18.7）
  static const Duration listStagger = Duration(milliseconds: 40);

  /// 列表進場總時長上限（Requirement 18.7）
  static const Duration listStaggerTotal = Duration(milliseconds: 400);

  /// 骨架載入的顯示門檻：低於此值不顯示 skeleton，避免閃爍（Requirement 18.8）
  static const Duration skeletonThreshold = Duration(milliseconds: 200);

  /// 一般元素的淡入。
  static const Duration fast = Duration(milliseconds: 150);

  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve decelerate = Curves.easeOutCubic;
  static const Curve standard = Curves.easeInOut;

  /// 系統啟用「減少動態效果」時回傳 [Duration.zero]，讓動畫直接落到最終狀態
  /// （Requirement 18.14）。
  static Duration resolve(BuildContext context, Duration base) =>
      MediaQuery.of(context).disableAnimations ? Duration.zero : base;

  /// 依索引算出列表項目的進場延遲，並確保總時長不超過
  /// [listStaggerTotal]（Requirement 18.7）。
  static Duration staggerDelay(int index, int itemCount) {
    if (itemCount <= 1) return Duration.zero;
    final perItemMicros = listStagger.inMicroseconds;
    final cappedMicros = listStaggerTotal.inMicroseconds;
    final rawMicros = perItemMicros * index;
    return Duration(
      microseconds: rawMicros > cappedMicros ? cappedMicros : rawMicros,
    );
  }
}
