import 'package:flutter/foundation.dart';

import 'package:ai_butler_app/domain/models/answer_value.dart';
import 'package:ai_butler_app/domain/models/form_answers.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';

/// 單一選項的金額小計。
@immutable
class QuotationLineItem {
  const QuotationLineItem({
    required this.topicId,
    required this.optionId,
    required this.optionName,
    required this.unitPrice,
    required this.quantity,
    required this.isQuotedSeparately,
  });

  final int topicId;
  final int optionId;
  final String optionName;
  final int unitPrice;
  final int quantity;
  final bool isQuotedSeparately;

  /// 另行報價的項目金額以 0 計入（Requirement 8.7）。
  int get amount => isQuotedSeparately ? 0 : unitPrice * quantity;
}

@immutable
class QuotationResult {
  const QuotationResult({
    required this.lineItems,
    required this.total,
    required this.hasSeparatelyQuoted,
  });

  final List<QuotationLineItem> lineItems;
  final int total;

  /// 已選項目中是否存在另行報價項目，UI 據此顯示提示文字（Requirement 8.7）。
  final bool hasSeparatelyQuoted;

  static const QuotationResult empty = QuotationResult(
    lineItems: <QuotationLineItem>[],
    total: 0,
    hasSeparatelyQuoted: false,
  );
}

/// 估價表單（`sub_type == '2'`）的金額試算（Requirement 8.5-8）。
///
/// 純函式，由屬性測試 P6 守住單調性與總計等式。
class QuotationCalculator {
  const QuotationCalculator._();

  static QuotationResult calculate(
    FormDefinition definition,
    FormAnswers answers,
  ) {
    final lineItems = <QuotationLineItem>[];

    for (final topic in definition.allTopics) {
      final value = answers.answerOf(topic.topicId);
      final selections = _selectionsOf(value);
      if (selections.isEmpty) continue;

      for (final selection in selections) {
        final option = topic.optionById(selection.optionId);
        if (option == null) continue;

        lineItems.add(QuotationLineItem(
          topicId: topic.topicId,
          optionId: option.id,
          optionName: option.optionName,
          unitPrice: option.unitPrice,
          quantity: selection.quantity,
          isQuotedSeparately: option.isQuotedSeparately,
        ));
      }
    }

    final total = lineItems.fold<int>(0, (sum, item) => sum + item.amount);
    final hasSeparatelyQuoted = lineItems.any((item) => item.isQuotedSeparately);

    return QuotationResult(
      lineItems: List<QuotationLineItem>.unmodifiable(lineItems),
      total: total,
      hasSeparatelyQuoted: hasSeparatelyQuoted,
    );
  }

  static List<SelectedOption> _selectionsOf(AnswerValue? value) {
    return switch (value) {
      OptionAnswer(option: final option) => <SelectedOption>[option],
      OptionListAnswer(options: final options) => options,
      _ => const <SelectedOption>[],
    };
  }
}
