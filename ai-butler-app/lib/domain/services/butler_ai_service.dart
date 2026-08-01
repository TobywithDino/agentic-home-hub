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
