import 'package:ai_butler_app/domain/models/answer_value.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';

/// 轉換結果。
class DraftPrefillResult {
  const DraftPrefillResult({
    required this.prefill,
    required this.unresolved,
  });

  /// 可以直接套進表單的作答值。
  final Map<int, AnswerValue> prefill;

  /// 管家有給答案、但轉不成合法作答值的題目。
  ///
  /// 導覽會針對這些題目改口說「這題請你自己選」，而不是假裝已經填好。
  /// 硬塞一個猜的值比留空更糟：使用者不會注意到，直接送出就錯了。
  final Map<int, String> unresolved;

  bool get isEmpty => prefill.isEmpty;
}

/// 把 AI 管家草稿的字串答案轉成 App 的型別化作答值。
///
/// 為什麼需要這一層：agent 端的 `feedback_content` 一律是字串（它不知道也不該
/// 知道 App 的作答模型），但 App 用 sealed [AnswerValue]，單選要 `option_id`
/// 不是 `option_name`、日期要 `DateTime`、地區要縣市**代碼**不是名稱。
///
/// 原則是**寧缺勿錯**：對不上的一律進 [DraftPrefillResult.unresolved]，
/// 不要退而求其次塞一個看起來像的值。
class DraftPrefillMapper {
  const DraftPrefillMapper._();

  static DraftPrefillResult map({
    required FormDefinition definition,
    required Map<int, String> answers,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    final prefill = <int, AnswerValue>{};
    final unresolved = <int, String>{};

    for (final topic in definition.allTopics) {
      if (!topic.type.collectsAnswer) continue;

      // 聯絡資料題不看逐題答案：管家把聯絡資訊放在 payload 頂層
      // （contact_name/contact_mobile/...），那才是結構化的來源。
      if (topic.type.isContact) {
        final contact = _contactFrom(payload, topic.type);
        if (contact != null) {
          prefill[topic.topicId] = contact;
        }
        continue;
      }

      final raw = answers[topic.topicId]?.trim();
      if (raw == null || raw.isEmpty) continue;

      final value = _convert(topic, raw);
      if (value == null) {
        unresolved[topic.topicId] = raw;
      } else {
        prefill[topic.topicId] = value;
      }
    }

    return DraftPrefillResult(prefill: prefill, unresolved: unresolved);
  }

  static AnswerValue? _convert(FormTopic topic, String raw) {
    switch (topic.type) {
      case TopicType.shortText:
      case TopicType.longText:
        return TextAnswer(raw);

      case TopicType.singleChoice:
        final option = _matchOption(topic, raw);
        return option == null
            ? null
            : OptionAnswer(SelectedOption(
                optionId: option.id,
                quantity: option.effectiveMin,
              ));

      case TopicType.multiChoice:
        // 管家用逗號分隔複選答案（見 tools.py 的 propose_submission 說明）。
        // 全形逗號與頓號也接受，模型實測會混用。
        final parts = raw
            .split(RegExp(r'[,，、]'))
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty);
        final selected = <SelectedOption>[];
        for (final part in parts) {
          final option = _matchOption(topic, part);
          // 有任何一項對不上就整題視為未解析 —— 只填一半會讓使用者
          // 以為已經選好，反而更容易送出錯的內容。
          if (option == null) return null;
          selected.add(SelectedOption(
            optionId: option.id,
            quantity: option.effectiveMin,
          ));
        }
        return selected.isEmpty ? null : OptionListAnswer(selected);

      case TopicType.date:
        final date = DateTime.tryParse(raw);
        return date == null ? null : DateAnswer(DateTime(date.year, date.month, date.day));

      case TopicType.region:
        // 地區需要縣市/行政區**代碼**，管家給的是名稱（例如「台北市 大安區」），
        // App 這邊沒有名稱→代碼的對照表可用，硬猜會送出錯的地址。
        // 交給使用者在導覽時自己選。
        return null;

      case TopicType.photo:
        // 照片管家代填不了（agent 端的 fillable_by_agent 已經是 false）。
        return null;

      case TopicType.contactWithAddress:
      case TopicType.contactWithoutAddress:
      case TopicType.notice:
      case TopicType.unsupported:
        return null;
    }
  }

  /// 以 `option_name` 比對選項。
  ///
  /// 先精確比對，再退成忽略大小寫與空白的寬鬆比對 —— 模型偶爾會把
  /// 「18:00」寫成「18：00」或多帶空白。仍然只接受真的存在的選項名稱，
  /// 不做模糊猜測。
  static TopicOption? _matchOption(FormTopic topic, String raw) {
    for (final option in topic.options) {
      if (option.optionName == raw) return option;
    }
    final needle = _loose(raw);
    for (final option in topic.options) {
      if (_loose(option.optionName) == needle) return option;
    }
    return null;
  }

  static String _loose(String value) => value
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('：', ':')
      .toLowerCase();

  static ContactAnswer? _contactFrom(
    Map<String, dynamic> payload,
    TopicType type,
  ) {
    final name = (payload['contact_name'] as String?)?.trim() ?? '';
    final mobile = (payload['contact_mobile'] as String?)?.trim() ?? '';
    if (name.isEmpty && mobile.isEmpty) return null;

    return ContactAnswer(
      name: name,
      mobile: mobile,
      email: (payload['contact_email'] as String?)?.trim() ?? '',
      landline: (payload['contact_landline'] as String?)?.trim() ?? '',
      // 地址同樣缺代碼對照，留空讓使用者填。
      includesAddress: type == TopicType.contactWithAddress,
    );
  }
}
