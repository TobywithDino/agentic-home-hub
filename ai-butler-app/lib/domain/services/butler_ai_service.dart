import 'package:ai_butler_app/domain/models/form_definition.dart';

/// AI 管家回覆的串流片段（Requirement 12.4、12.5-9）。
sealed class ButlerChunk {
  const ButlerChunk();
}

/// 文字增量，UI 逐段 append（打字機效果）。
class TextDelta extends ButlerChunk {
  const TextDelta(this.text);
  final String text;
}

/// 建議快捷選項（每則回覆最多 4 個，Requirement 12.5）。
class SuggestionChips extends ButlerChunk {
  const SuggestionChips(this.chips);
  final List<String> chips;
}

/// 服務類別建議卡（Requirement 12.8）。
class CategoryCard extends ButlerChunk {
  const CategoryCard({required this.serviceId, required this.name});
  final int serviceId;
  final String name;
}

/// 服務商推薦卡（Requirement 12.9）。
class VendorCard extends ButlerChunk {
  const VendorCard(
      {required this.vendorId, required this.name, required this.description});
  final int vendorId;
  final String name;
  final String description;
}

/// 表單預填確認卡（Requirement 13.5-6）。
class PrefillCard extends ButlerChunk {
  const PrefillCard({
    required this.serviceId,
    required this.formId,
    required this.filledCount,
    required this.remainingRequired,
    required this.summary,
  });
  final int serviceId;
  final int formId;
  final int filledCount;
  final int remainingRequired;
  final String summary;
}

/// 非表單類的草稿確認卡（訂單評價、個人資料）。
///
/// 諮詢單草稿有表單可以帶使用者去填，走 [PrefillCard]；評價與個資沒有表單，
/// 所以用這張通用卡。
///
/// `submitMethod` / `submitPath` 由 agent 端的草稿自己描述，App 只要重播
/// method + path + payload 就能送出，不必用 `kind` switch 出路徑 ——
/// 之後 agent 新增草稿類型，這裡不用跟著改。
///
/// 對應 agent_service/app/AiButler/schemas.py 的 OrderDraft.to_event_payload。
class DraftCard extends ButlerChunk {
  const DraftCard({
    required this.draftId,
    required this.kind,
    required this.kindLabel,
    required this.summary,
    required this.submitMethod,
    required this.submitPath,
    required this.payload,
  });

  final String draftId;

  /// `review` | `profile`（`feedback` 會被映射成 [PrefillCard]）
  final String kind;

  /// 給使用者看的類型名稱，例如「訂單評價」
  final String kindLabel;
  final String summary;

  /// 送出時要用的 HTTP method 與 bff_server 路徑
  final String submitMethod;
  final String submitPath;

  /// request body，欄位已對齊 `submitPath` 那支端點
  final Map<String, dynamic> payload;
}

/// 串流完成標記。
class Done extends ButlerChunk {
  const Done();
}

/// AI 回應失敗。
class Failed extends ButlerChunk {
  const Failed(this.message);
  final String message;
}

/// AI 需求分類結果。
class IntentResult {
  const IntentResult({required this.serviceIds, required this.confidences});
  final List<int> serviceIds;
  final List<double> confidences;
}

/// AI 表單預填結果。
class PrefillResult {
  const PrefillResult({required this.filledFields, required this.summary});

  /// key = topicId, value = 作答值的 JSON 可序列化形式
  final Map<int, Object?> filledFields;
  final String summary;
}

/// AI 智能管家能力的抽象介面（Requirement 12、13）。
///
/// 三種實作（design.md）：MockButlerAiService、BackendProxyButlerAiService、
/// BedrockButlerAiService。畫面層只依賴此介面。
abstract interface class ButlerAiService {
  /// 對話串流：送出使用者訊息，逐段回傳管家回覆（Requirement 12.4）。
  Stream<ButlerChunk> send(String message);

  /// 需求分類：判定 service_id 清單與信心程度（Requirement 13.1）。
  Future<IntentResult> classify(String utterance);

  /// 表單預填：依使用者描述回傳可對應的題目作答值（Requirement 13.4）。
  Future<PrefillResult> prefill(String utterance, FormDefinition definition);

  /// AI 教你填表單：回傳該題目的說明與範例作答（Requirement 13.9）。
  Future<String> explainTopic(FormTopic topic);
}
