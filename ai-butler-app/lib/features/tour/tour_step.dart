import 'package:flutter/widgets.dart';

/// 導覽的一步。
///
/// [anchorKey] 指向畫面上真實的 widget，光圈依它的位置與大小挖洞。
/// key 的 `currentContext` 為 null（例如那一題被捲出視野而未掛載）時，
/// 這一步會被跳過而不是讓整個導覽掛掉。
@immutable
class TourStep {
  const TourStep({
    required this.anchorKey,
    required this.instruction,
    this.title = '',
    this.handOff = false,
    this.onTap,
  });

  final GlobalKey anchorKey;

  /// 泡泡裡的說明文字。用第二人稱、口語，像旁邊有人在教。
  final String instruction;

  /// 泡泡標題，留空就不顯示。
  final String title;

  /// 這一步是否為「交棒點」。
  ///
  /// true 代表接下來要使用者自己動手（通常是最後的送出鈕），泡泡的按鈕會
  /// 從「下一步」變成「我知道了」，並且結束導覽把控制權交回去。
  /// 這是刻意的設計：送出一定要由使用者親手按，管家不代按。
  final bool handOff;

  /// 使用者點擊光圈區域時要做的事（通常是導航到下一頁）。
  ///
  /// **為什麼導航要由這裡做，而不是讓點擊穿透到底下的元件**：
  /// `tutorial_coach_mark` 會在光圈區域蓋一層 GestureDetector 攔截點擊，
  /// 底下真正的 widget 收不到。所以「帶使用者點選 GUI」的實作方式是
  /// 由我們在這個 callback 裡執行對應動作 —— 使用者仍然是點在正確的位置上，
  /// 教學效果不變。
  ///
  /// 有設定時泡泡不顯示「下一步」按鈕：只能靠點擊目標前進。
  /// 否則使用者按了下一步會跳過這一步，但畫面沒有跟著切換，導覽就錯位了。
  final VoidCallback? onTap;

  /// 這一步是否要靠點擊目標才能前進。
  bool get requiresTap => onTap != null;
}
