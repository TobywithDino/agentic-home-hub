import 'package:ai_butler_app/domain/models/form_answers.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';

/// 把 [FormAnswers] 轉成 `feedback_content` 的 JSON 結構
/// （requirements.md 附錄 C，Requirement 9.3-6）。
///
/// 這是 App 與後端之間唯一的資料契約定義處。純函式、無 Flutter 依賴，
/// 由屬性測試 P1-P3 守住型別與 JSON-safe 性質。
class FormAnswerSerializer {
  const FormAnswerSerializer._();

  /// 產出 `{ form_id, answers: [...] }`。
  static Map<String, Object?> toFeedbackContent(
    FormDefinition definition,
    FormAnswers answers,
  ) {
    final list = <Map<String, Object?>>[];

    for (final topic in definition.allTopics) {
      // 題型 07 不產生 answers 元素（Requirement 9.6）。
      if (topic.type == TopicType.notice) continue;

      final value = answers.answerOf(topic.topicId);
      list.add(<String, Object?>{
        'topic_id': topic.topicId,
        'type': topic.type.code,
        // 未作答且非必填 → value 為 null（Requirement 9.5）。
        'value': value?.toJson(),
      });
    }

    return <String, Object?>{
      'form_id': definition.formId,
      'answers': list,
    };
  }
}
