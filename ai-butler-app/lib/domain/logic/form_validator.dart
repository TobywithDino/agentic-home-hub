import 'package:ai_butler_app/domain/models/answer_value.dart';
import 'package:ai_butler_app/domain/models/form_answers.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';

/// 表單驗證結果。key 為 topic_id，value 為錯誤訊息
/// （Requirement 8.1-2、9.12）。
typedef ValidationErrors = Map<int, String>;

/// 動態表單驗證器。純函式，由屬性測試 P4、P5 守住。
class FormValidator {
  const FormValidator._();

  static const String requiredMessage = '此為必填項目，請填寫後再送出';
  static const String numberOnlyMessage = '請輸入數字';
  static const String minMediaMessageTemplate = '請至少上傳 {min} 張照片';
  static const String mobileFormatMessage = '手機格式需為 09 開頭的 10 位數字';
  static const String emailFormatMessage = 'Email 格式不正確';

  static final RegExp _mobilePattern = RegExp(r'^09\d{8}$');
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// 驗證整份表單。回傳的 map 為空即代表通過。
  static ValidationErrors validate(
    FormDefinition definition,
    FormAnswers answers,
  ) {
    final errors = <int, String>{};

    for (final topic in definition.allTopics) {
      final error = validateTopic(topic, answers.answerOf(topic.topicId));
      if (error != null) errors[topic.topicId] = error;
    }

    return errors;
  }

  /// 驗證單一題目，供使用者修正後即時重新檢查（Requirement 8.2）。
  static String? validateTopic(FormTopic topic, AnswerValue? value) {
    if (!topic.type.collectsAnswer) return null;

    final isEmpty = value == null || !value.isFilled;

    if (topic.isRequired && isEmpty) {
      // 照片題有專屬的張數訊息，優先顯示（Requirement 8.3）。
      if (topic.type == TopicType.photo) {
        return _minMediaMessage(topic.minMedias ?? 1);
      }
      return requiredMessage;
    }

    if (isEmpty) return null; // 非必填且未填，通過。

    return switch (topic.type) {
      TopicType.shortText => _validateShortText(topic, value as TextAnswer),
      TopicType.photo => _validatePhoto(topic, value as MediaAnswer),
      TopicType.contactWithAddress =>
        _validateContact(value as ContactAnswer),
      TopicType.contactWithoutAddress =>
        _validateContact(value as ContactAnswer),
      _ => null,
    };
  }

  static String? _validateShortText(FormTopic topic, TextAnswer answer) {
    if (!topic.isNumberOnly) return null;
    final isNumeric = RegExp(r'^\d+$').hasMatch(answer.text.trim());
    return isNumeric ? null : numberOnlyMessage;
  }

  static String? _validatePhoto(FormTopic topic, MediaAnswer answer) {
    final min = topic.minMedias;
    if (min != null && answer.fileIds.length < min) {
      return _minMediaMessage(min);
    }
    return null;
  }

  static String? _validateContact(ContactAnswer answer) {
    if (answer.mobile.isNotEmpty && !_mobilePattern.hasMatch(answer.mobile)) {
      return mobileFormatMessage;
    }
    if (answer.email.isNotEmpty && !_emailPattern.hasMatch(answer.email)) {
      return emailFormatMessage;
    }
    return null;
  }

  static String _minMediaMessage(int min) =>
      minMediaMessageTemplate.replaceFirst('{min}', '$min');
}
