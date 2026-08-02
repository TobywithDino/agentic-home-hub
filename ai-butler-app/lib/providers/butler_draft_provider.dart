import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/domain/services/butler_ai_service.dart';

/// AI 管家交棒給表單頁的待處理草稿。
///
/// 為什麼用 provider 而不是路由參數：草稿含逐題答案與聯絡資料，塞進 query
/// string 要序列化成 JSON 再 URL encode，網址會變得又長又難 debug，重整頁面
/// 還會把使用者的個資留在瀏覽器歷史裡。provider 存在記憶體，跳頁後就取用，
/// 用完即清。
///
/// 只保留「一筆」待處理草稿。使用者同時開兩張草稿本來就沒有意義，
/// 而且後產生的那張才是他當下想處理的。
class PendingButlerDraft {
  const PendingButlerDraft({required this.card, required this.startTour});

  final PrefillCard card;

  /// true = 使用者選了「帶我操作一遍」，進表單頁要跑光圈導覽；
  /// false = 只做預填，讓他自己看。
  final bool startTour;
}

class PendingButlerDraftNotifier extends Notifier<PendingButlerDraft?> {
  @override
  PendingButlerDraft? build() => null;

  void handOff(PrefillCard card, {required bool startTour}) {
    state = PendingButlerDraft(card: card, startTour: startTour);
  }

  /// 表單頁套用完就清掉。
  ///
  /// 不清的話使用者之後自己從服務項目頁進同一張表單，會莫名被塞入上次的答案
  /// 又跑一次導覽。
  void clear() => state = null;
}

final pendingButlerDraftProvider =
    NotifierProvider<PendingButlerDraftNotifier, PendingButlerDraft?>(
  PendingButlerDraftNotifier.new,
);
