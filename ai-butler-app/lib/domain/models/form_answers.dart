import 'package:flutter/foundation.dart';

import 'package:ai_butler_app/domain/models/answer_value.dart';

/// 一份諮詢單填寫中的作答狀態，key 為 `topic_id`。
///
/// 不可變：每次變更回傳新的 [FormAnswers]，方便 Notifier 用
/// `state = state.setAnswer(...)` 的模式驅動 UI 重繪（Requirement 8.2）。
@immutable
class FormAnswers {
  const FormAnswers({
    this.values = const <int, AnswerValue>{},
    this.aiFilledTopicIds = const <int>{},
  });

  final Map<int, AnswerValue> values;

  /// 由 AI 預填、尚未被使用者手動修改過的題目（Requirement 13.6、13.11）。
  final Set<int> aiFilledTopicIds;

  AnswerValue? answerOf(int topicId) => values[topicId];

  bool isAiFilled(int topicId) => aiFilledTopicIds.contains(topicId);

  /// 設定作答值。若該題原本是 AI 填入，使用者一改動就移除標記
  /// （Requirement 13.11）。
  FormAnswers setAnswer(int topicId, AnswerValue? value, {bool byUser = true}) {
    final nextValues = Map<int, AnswerValue>.of(values);
    if (value == null) {
      nextValues.remove(topicId);
    } else {
      nextValues[topicId] = value;
    }

    final nextAiFilled = Set<int>.of(aiFilledTopicIds);
    if (byUser) {
      nextAiFilled.remove(topicId);
    }

    return FormAnswers(values: nextValues, aiFilledTopicIds: nextAiFilled);
  }

  /// AI 一次性預填多題，標記為 AI 填入。
  FormAnswers applyPrefill(Map<int, AnswerValue> prefill) {
    final nextValues = Map<int, AnswerValue>.of(values)..addAll(prefill);
    final nextAiFilled = Set<int>.of(aiFilledTopicIds)..addAll(prefill.keys);
    return FormAnswers(values: nextValues, aiFilledTopicIds: nextAiFilled);
  }

  FormAnswers clear() => const FormAnswers();

  @override
  bool operator ==(Object other) =>
      other is FormAnswers &&
      mapEquals(other.values, values) &&
      setEquals(other.aiFilledTopicIds, aiFilledTopicIds);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(values.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAllUnordered(aiFilledTopicIds),
      );
}
