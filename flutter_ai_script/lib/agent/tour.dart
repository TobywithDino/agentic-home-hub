/// 教學導覽(新手教程模式)。
///
/// 設計重點:**步驟由 App 產生,不是由 LLM 產生。**
/// LLM 不知道你的 widget 樹,叫它輸出 GUI 操作步驟它會編 widget id。
/// 所以 LLM 只負責產出語意層的草稿(哪家餐廳、幾點、幾位),
/// 這裡用一張靜態對應表把草稿翻成畫面路徑 + 欄位說明,全程確定性邏輯。
library;

import 'package:flutter/widgets.dart';

import 'agent_event.dart';

/// 錨點註冊表。
///
/// 表單頁面的每個元件掛上 `key: TourAnchors.of('reservation.date')`,
/// 導覽才知道要把光圈打在哪裡。
class TourAnchors {
  TourAnchors._();

  static final Map<String, GlobalKey> _keys = {};

  static GlobalKey of(String id) => _keys.putIfAbsent(id, () => GlobalKey());

  /// 頁面 dispose 時清掉,避免舊 key 綁在已卸載的 element 上導致光圈算錯位置。
  static void release(Iterable<String> ids) {
    for (final id in ids) {
      _keys.remove(id);
    }
  }

  /// 錨點目前是否真的在畫面上。找不到的步驟要跳過,不然導覽會卡住。
  static bool isMounted(String id) {
    final context = _keys[id]?.currentContext;
    return context != null && context.findRenderObject()?.attached == true;
  }
}

/// 一個導覽步驟。
class TourStep {
  const TourStep({
    required this.anchorId,
    required this.instruction,
    this.handOff = false,
  });

  final String anchorId;

  /// 顯示在光圈旁的說明文字。
  final String instruction;

  /// true 表示這是交棒步驟:關掉導覽遮罩,讓使用者自己真的按下去。
  /// 一段導覽裡只會有最後一步是 true。
  final bool handOff;
}

/// 一種服務的導覽藍圖。
class TourBlueprint {
  const TourBlueprint({required this.route, required this.buildSteps});

  /// 要導航到哪個表單頁。
  final String route;

  /// 依草稿內容產生步驟。payload 就是後端 propose_submission 存下來的 body。
  final List<TourStep> Function(Map<String, dynamic> payload) buildSteps;
}

/// 從草稿 payload 撈出某一題的答案。
///
/// 真實的 `feedback_content` 是 `{ "<topic_id>": {"title": ..., "value": ...} }`,
/// topic_id 是每張表單自己的流水號,不能寫死在前端。所以這裡用題目標題的
/// 關鍵字去找 —— 導覽文案只是解說用,找不到就回空字串,不要讓導覽掛掉。
String answerOf(Map<String, dynamic> payload, String titleContains) {
  final content = payload['feedback_content'];
  if (content is! Map) return '';
  for (final entry in content.values) {
    if (entry is! Map) continue;
    final title = entry['title']?.toString() ?? '';
    if (title.contains(titleContains)) return entry['value']?.toString() ?? '';
  }
  return '';
}

/// 服務類型代碼 → 導覽藍圖。
///
/// key 必須跟後端 `ServiceType` 的值一致（`cms_homepage_service.type`）：
/// 1=居家清潔 2=家電清洗 3=包裹寄送 6=餐廳訂位 9=美食外送 10=水電修繕 11=商城購物。
/// 新增服務時兩邊一起加。
///
/// 只有 `kind=feedback`（諮詢單）的草稿走導覽；評價與個人資料草稿沒有表單頁,
/// 不需要藍圖。
final Map<String, TourBlueprint> tourBlueprints = {
  '6': TourBlueprint(
    route: '/reservation/new',
    buildSteps: (payload) => [
      const TourStep(
        anchorId: 'reservation.restaurant',
        instruction: '這裡是餐廳。剛剛你選的那家我已經幫你帶進來了,'
            '以後你也可以從首頁的「餐廳訂位」自己搜尋。',
      ),
      TourStep(
        anchorId: 'reservation.date',
        instruction: '日期選在 ${answerOf(payload, '日期')},點一下可以改。',
      ),
      TourStep(
        anchorId: 'reservation.time',
        instruction: '時段是 ${answerOf(payload, '時段')}。'
            '這裡只會列出還有位子的時間,所以選不到就是滿了。',
      ),
      TourStep(
        anchorId: 'reservation.partySize',
        instruction: '人數 ${answerOf(payload, '人數')} 位。',
      ),
      const TourStep(
        anchorId: 'reservation.contact',
        instruction: '聯絡資訊會自動帶你帳號裡的資料,要換人聯絡就改這裡。',
      ),
      const TourStep(
        anchorId: 'reservation.submit',
        instruction: '最後一步,送出訂單。這次你自己按 —— 按下去才算真的訂位。',
        handOff: true,
      ),
    ],
  ),

  '2': TourBlueprint(
    route: '/laundry/new',
    buildSteps: (payload) => [
      const TourStep(
        anchorId: 'laundry.machine',
        instruction: '這是洗衣機編號,我幫你挑了目前空著的那台。',
      ),
      TourStep(
        anchorId: 'laundry.slot',
        instruction: '預約時段 ${answerOf(payload, '日期')}。',
      ),
      const TourStep(
        anchorId: 'laundry.submit',
        instruction: '確認沒問題就自己按下送出。',
        handOff: true,
      ),
    ],
  ),
};

/// 導覽模式進入表單頁時帶的參數。
///
/// 表單頁在 initState 讀 [prefill] 把 controller 填好 —— 預填是頁面自己做的,
/// 導覽只負責解說。這樣比讓導覽逐欄位寫值穩定得多,
/// 使用者中途改了值也不會被覆蓋回去。
class TourLaunchArgs {
  const TourLaunchArgs({
    required this.draftId,
    required this.prefill,
    required this.steps,
  });

  final String draftId;
  final Map<String, dynamic> prefill;
  final List<TourStep> steps;

  /// 從草稿事件組出啟動參數。
  ///
  /// 回傳 null 表示不走導覽：可能是這個服務類型還沒寫藍圖,
  /// 也可能這張草稿不是諮詢單（評價/個資沒有表單頁可導覽）。
  static ({String route, TourLaunchArgs args})? from(OrderDraftEvent draft) {
    if (draft.kind != 'feedback') return null;
    final blueprint = tourBlueprints[draft.serviceType];
    if (blueprint == null) return null;

    return (
      route: blueprint.route,
      args: TourLaunchArgs(
        draftId: draft.draftId,
        prefill: draft.payload,
        steps: blueprint.buildSteps(draft.payload),
      ),
    );
  }
}
