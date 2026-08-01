import 'package:flutter/foundation.dart';

import 'package:ai_butler_app/domain/models/answer_value.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';

/// 題目選項（`pms_topic_option`）
@immutable
class TopicOption {
  const TopicOption({
    required this.id,
    required this.optionName,
    this.unitPrice = 0,
    this.unit = '',
    this.isQuantity = false,
    this.minQuantity = 1,
    this.maxQuantity = 1,
    this.isQuotedSeparately = false,
    this.remark = '',
    this.sort = 0,
  });

  final int id;
  final String optionName;
  final int unitPrice;
  final String unit;

  /// 數量是否可選（`is_quantity`）
  final bool isQuantity;
  final int minQuantity;
  final int maxQuantity;

  /// 是否另行報價（`is_quoted_separately`）。為 true 時金額以 0 計入試算。
  final bool isQuotedSeparately;
  final String remark;
  final int sort;

  /// 數量的合法下界。不可選數量時固定為 1。
  int get effectiveMin => isQuantity ? (minQuantity < 1 ? 1 : minQuantity) : 1;

  /// 數量的合法上界。
  int get effectiveMax {
    if (!isQuantity) return 1;
    final max = maxQuantity;
    return max < effectiveMin ? effectiveMin : max;
  }

  /// 將任意數量夾到合法區間（Requirement 7.20）。
  int clampQuantity(int quantity) {
    if (quantity < effectiveMin) return effectiveMin;
    if (quantity > effectiveMax) return effectiveMax;
    return quantity;
  }
}

/// 題目輔助圖片（`pms_topic_media`）
@immutable
class TopicMedia {
  const TopicMedia({required this.id, required this.imgUrl, this.sort = 0});

  final int id;
  final String imgUrl;
  final int sort;
}

/// 表單題目（`pms_form_topic`）
@immutable
class FormTopic {
  const FormTopic({
    required this.topicId,
    required this.type,
    required this.title,
    this.remark = '',
    this.isRequired = false,
    this.sort = 0,
    this.isNumberOnly = false,
    this.minMedias,
    this.maxMedias,
    this.specifiedMedias,
    this.startDateOffsetDays,
    this.endDateOffsetDays,
    this.options = const <TopicOption>[],
    this.medias = const <TopicMedia>[],
  });

  final int topicId;
  final TopicType type;
  final String title;
  final String remark;
  final bool isRequired;
  final int sort;

  /// 簡答題是否只能輸入數字（`is_number_only`）
  final bool isNumberOnly;

  final int? minMedias;
  final int? maxMedias;
  final int? specifiedMedias;

  /// 日期題可選起日相對今日的偏移天數。
  final int? startDateOffsetDays;

  /// 日期題可選迄日相對今日的偏移天數。
  final int? endDateOffsetDays;

  final List<TopicOption> options;
  final List<TopicMedia> medias;

  /// 依 sort 排序後的選項。
  List<TopicOption> get sortedOptions {
    final sorted = List<TopicOption>.of(options)
      ..sort((a, b) => a.sort.compareTo(b.sort));
    return List<TopicOption>.unmodifiable(sorted);
  }

  TopicOption? optionById(int id) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  /// 這個題目的空白初始作答值。
  AnswerValue? emptyAnswer() => switch (type) {
        TopicType.shortText || TopicType.longText => const TextAnswer(''),
        TopicType.singleChoice => null,
        TopicType.multiChoice => const OptionListAnswer(<SelectedOption>[]),
        TopicType.region => const RegionAnswer(),
        TopicType.photo => const MediaAnswer(<String>[]),
        TopicType.contactWithAddress => const ContactAnswer(),
        TopicType.contactWithoutAddress =>
          const ContactAnswer(includesAddress: false),
        TopicType.date => const DateAnswer(null),
        TopicType.notice || TopicType.unsupported => null,
      };
}

/// 表單題組（`pms_form_group`）
@immutable
class FormGroup {
  const FormGroup({
    required this.id,
    required this.name,
    this.sort = 0,
    this.topics = const <FormTopic>[],
  });

  final int id;
  final String name;
  final int sort;
  final List<FormTopic> topics;

  /// 依 sort 排序後的題目（Requirement 7.2）。
  List<FormTopic> get sortedTopics {
    final sorted = List<FormTopic>.of(topics)
      ..sort((a, b) => a.sort.compareTo(b.sort));
    return List<FormTopic>.unmodifiable(sorted);
  }
}

/// 表單主檔（`pms_form`）
@immutable
class FormDefinition {
  const FormDefinition({
    required this.formId,
    required this.serviceVendorId,
    required this.serviceId,
    required this.name,
    this.type = '1',
    this.subType = '1',
    this.introContent = '',
    this.noticeContent = '',
    this.termsContent = '',
    this.groups = const <FormGroup>[],
  });

  final int formId;
  final int serviceVendorId;
  final int serviceId;
  final String name;

  /// 1 C端(無現場評估) / 2 C端(需評估) / 3 B端 / 4 轉訂單流程 / 5 客服
  final String type;

  /// 1 一般表單 / 2 估價表單
  final String subType;

  final String introContent;
  final String noticeContent;
  final String termsContent;
  final List<FormGroup> groups;

  /// 是否為估價表單，決定是否顯示金額試算（Requirement 8.5）。
  bool get isQuotation => TopicType.normalize(subType) == '02';

  /// 依 sort 排序後的題組（Requirement 7.2）。
  List<FormGroup> get sortedGroups {
    final sorted = List<FormGroup>.of(groups)
      ..sort((a, b) => a.sort.compareTo(b.sort));
    return List<FormGroup>.unmodifiable(sorted);
  }

  /// 全部題目，依題組與題目 sort 攤平。
  List<FormTopic> get allTopics {
    final result = <FormTopic>[];
    for (final group in sortedGroups) {
      result.addAll(group.sortedTopics);
    }
    return List<FormTopic>.unmodifiable(result);
  }

  FormTopic? topicById(int topicId) {
    for (final topic in allTopics) {
      if (topic.topicId == topicId) return topic;
    }
    return null;
  }

  /// 依題型找出第一個題目（依 sort 順序）。
  FormTopic? firstTopicOfType(TopicType type) {
    for (final topic in allTopics) {
      if (topic.type == type) return topic;
    }
    return null;
  }

  bool hasType(TopicType type) => firstTopicOfType(type) != null;

  /// 必填題目數（不含備註說明與未支援題型）。
  int get requiredTopicCount =>
      allTopics.where((t) => t.isRequired && t.type.collectsAnswer).length;
}
