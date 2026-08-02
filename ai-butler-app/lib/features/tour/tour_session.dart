import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/domain/services/butler_ai_service.dart';

/// 導覽目前走到哪一個畫面。
///
/// 只涵蓋「需要導航到下一頁」的三段。填單頁那一段由 `FormScreen` 自己跑
/// （它要等表單載入、預填完成才知道有哪些題目），交棒方式是設定
/// `pendingButlerDraftProvider`，見 [TourSessionNotifier.handOffToForm]。
enum TourLeg {
  /// 首頁：圈出對應的服務類別磚
  home,

  /// 服務商列表：圈出管家推薦的那一家
  vendorList,

  /// 商家詳情：圈出「填寫諮詢單」
  vendorDetail,
}

class TourSession {
  const TourSession({
    required this.card,
    required this.leg,
    this.started = false,
  });

  final PrefillCard card;
  final TourLeg leg;

  /// 這一段的光圈是否已經啟動過。
  ///
  /// 畫面的 `build` 會因為各種原因重跑（資料載入、捲動、鍵盤彈出），
  /// 沒有這個旗標就會反覆彈出同一段導覽。
  final bool started;

  TourSession copyWith({TourLeg? leg, bool? started}) => TourSession(
        card: card,
        leg: leg ?? this.leg,
        started: started ?? this.started,
      );
}

class TourSessionNotifier extends Notifier<TourSession?> {
  @override
  TourSession? build() => null;

  /// 從首頁開始教。
  void start(PrefillCard card) {
    state = TourSession(card: card, leg: TourLeg.home);
  }

  /// 標記目前這一段已經啟動，避免重複彈出。
  void markStarted() {
    final current = state;
    if (current == null || current.started) return;
    state = current.copyWith(started: true);
  }

  /// 前進到下一個畫面。`started` 要重置，否則新的一段不會啟動。
  void advanceTo(TourLeg leg) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(leg: leg, started: false);
  }

  /// 使用者中途跳過或關掉導覽。
  void finish() => state = null;
}

final tourSessionProvider =
    NotifierProvider<TourSessionNotifier, TourSession?>(
  TourSessionNotifier.new,
);
