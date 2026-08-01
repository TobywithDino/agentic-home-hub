import 'package:flutter/material.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/models/answer_value.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';

/// 動態表單題目渲染（Requirement 7）。
///
/// 每種題型一個 build 函式，由 [buildTopicWidget] 依 [TopicType] 分派
/// （design.md「渲染註冊表」）。未支援題型渲染成提示卡並繼續渲染其餘題目
/// （Requirement 7.18）。
class TopicFieldParams {
  const TopicFieldParams({
    required this.topic,
    required this.answer,
    required this.errorMessage,
    required this.onChanged,
  });

  final FormTopic topic;
  final AnswerValue? answer;
  final String? errorMessage;
  final void Function(AnswerValue? value) onChanged;
}

Widget buildTopicWidget(BuildContext context, TopicFieldParams params) {
  final topic = params.topic;

  final field = switch (topic.type) {
    TopicType.shortText || TopicType.longText => _TextField(params: params),
    TopicType.singleChoice => _SingleChoiceField(params: params),
    TopicType.multiChoice => _MultiChoiceField(params: params),
    TopicType.region => _RegionField(params: params),
    TopicType.photo => _PhotoPlaceholderField(params: params),
    TopicType.notice => _NoticeField(params: params),
    TopicType.contactWithAddress => _ContactField(params: params, includesAddress: true),
    TopicType.contactWithoutAddress => _ContactField(params: params, includesAddress: false),
    TopicType.date => _DateField(params: params),
    TopicType.unsupported => _UnsupportedField(params: params),
  };

  if (topic.type == TopicType.notice) return field;

  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _TopicHeader(topic: topic),
        const SizedBox(height: AppSpacing.xs),
        field,
        if (params.errorMessage != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            params.errorMessage!,
            style: AppTypography.caption.copyWith(color: context.butler.error),
          ),
        ],
      ],
    ),
  );
}

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.topic});

  final FormTopic topic;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(topic.title, style: AppTypography.bodyLarge)),
            if (topic.isRequired)
              Semantics(
                label: '必填',
                child: Text('必填', style: AppTypography.caption.copyWith(color: context.butler.error)),
              ),
          ],
        ),
        if (topic.remark.isNotEmpty)
          Text(
            topic.remark,
            style: AppTypography.caption.copyWith(color: context.butler.secondaryText),
          ),
      ],
    );
  }
}

class _TextField extends StatefulWidget {
  const _TextField({required this.params});

  final TopicFieldParams params;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final answer = widget.params.answer;
    _controller = TextEditingController(text: answer is TextAnswer ? answer.text : '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLong = widget.params.topic.type == TopicType.longText;
    return TextField(
      controller: _controller,
      minLines: isLong ? 4 : 1,
      maxLines: isLong ? null : 1,
      keyboardType: widget.params.topic.isNumberOnly ? TextInputType.number : TextInputType.text,
      onChanged: (value) => widget.params.onChanged(TextAnswer(value)),
    );
  }
}

class _SingleChoiceField extends StatelessWidget {
  const _SingleChoiceField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    final selected = params.answer is OptionAnswer ? (params.answer as OptionAnswer).option.optionId : null;
    return Column(
      children: <Widget>[
        for (final option in params.topic.sortedOptions)
          RadioListTile<int>(
            value: option.id,
            groupValue: selected,
            title: Text(_optionLabel(option)),
            subtitle: option.remark.isNotEmpty ? Text(option.remark) : null,
            onChanged: (value) {
              if (value == null) return;
              params.onChanged(OptionAnswer(SelectedOption(optionId: value)));
            },
          ),
      ],
    );
  }
}

class _MultiChoiceField extends StatelessWidget {
  const _MultiChoiceField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    final selections = params.answer is OptionListAnswer
        ? (params.answer as OptionListAnswer).options
        : const <SelectedOption>[];
    final selectedIds = selections.map((s) => s.optionId).toSet();

    return Column(
      children: <Widget>[
        for (final option in params.topic.sortedOptions)
          CheckboxListTile(
            value: selectedIds.contains(option.id),
            title: Text(_optionLabel(option)),
            subtitle: option.remark.isNotEmpty ? Text(option.remark) : null,
            onChanged: (checked) {
              final next = List<SelectedOption>.of(selections);
              next.removeWhere((s) => s.optionId == option.id);
              if (checked == true) {
                next.add(SelectedOption(optionId: option.id, quantity: option.effectiveMin));
              }
              params.onChanged(OptionListAnswer(next));
            },
          ),
      ],
    );
  }
}

String _optionLabel(TopicOption option) {
  if (option.unitPrice > 0) {
    return '${option.optionName}（NT\$${option.unitPrice}${option.unit.isNotEmpty ? '/${option.unit}' : ''}）';
  }
  return option.optionName;
}

class _RegionField extends StatelessWidget {
  const _RegionField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    final answer = params.answer is RegionAnswer ? params.answer as RegionAnswer : const RegionAnswer();
    // 簡化版連動選單：完整縣市/行政區資料由 mock/HTTP repository 提供，
    // 這裡先用文字輸入承載，待任務 9.3 補上正式下拉選單。
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            decoration: const InputDecoration(labelText: '縣市代碼'),
            controller: TextEditingController(text: answer.countyCode),
            onChanged: (v) => params.onChanged(answer.copyWith(countyCode: v)),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextField(
            decoration: const InputDecoration(labelText: '行政區代碼'),
            controller: TextEditingController(text: answer.districtCode),
            onChanged: (v) => params.onChanged(answer.copyWith(districtCode: v)),
          ),
        ),
      ],
    );
  }
}

class _PhotoPlaceholderField extends StatelessWidget {
  const _PhotoPlaceholderField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: context.butler.border),
        borderRadius: AppRadius.mdAll,
      ),
      child: Text(
        '照片上傳（最少 ${params.topic.minMedias ?? 0} 張）尚在實作中',
        style: AppTypography.caption.copyWith(color: context.butler.secondaryText),
      ),
    );
  }
}

class _NoticeField extends StatelessWidget {
  const _NoticeField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.butler.surfaceVariant,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(params.topic.title, style: AppTypography.label),
          if (params.topic.remark.isNotEmpty) Text(params.topic.remark, style: AppTypography.caption),
        ],
      ),
    );
  }
}

class _ContactField extends StatelessWidget {
  const _ContactField({required this.params, required this.includesAddress});

  final TopicFieldParams params;
  final bool includesAddress;

  @override
  Widget build(BuildContext context) {
    final answer = params.answer is ContactAnswer
        ? params.answer as ContactAnswer
        : ContactAnswer(includesAddress: includesAddress);

    return Column(
      children: <Widget>[
        TextField(
          decoration: const InputDecoration(labelText: '姓名'),
          controller: TextEditingController(text: answer.name),
          onChanged: (v) => params.onChanged(answer.copyWith(name: v)),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          decoration: const InputDecoration(labelText: '手機'),
          keyboardType: TextInputType.phone,
          controller: TextEditingController(text: answer.mobile),
          onChanged: (v) => params.onChanged(answer.copyWith(mobile: v)),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          decoration: const InputDecoration(labelText: 'Email'),
          controller: TextEditingController(text: answer.email),
          onChanged: (v) => params.onChanged(answer.copyWith(email: v)),
        ),
        if (includesAddress) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          TextField(
            decoration: const InputDecoration(labelText: '詳細地址'),
            controller: TextEditingController(text: answer.addressDetail),
            onChanged: (v) => params.onChanged(answer.copyWith(addressDetail: v)),
          ),
        ],
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    final answer = params.answer is DateAnswer ? params.answer as DateAnswer : const DateAnswer(null);
    final label = answer.date == null
        ? '請選擇日期'
        : '${answer.date!.year}-${answer.date!.month.toString().padLeft(2, '0')}-${answer.date!.day.toString().padLeft(2, '0')}';

    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text(label),
      onPressed: () async {
        final now = DateTime.now();
        final start = now.add(Duration(days: params.topic.startDateOffsetDays ?? 0));
        final end = now.add(Duration(days: params.topic.endDateOffsetDays ?? 30));
        final picked = await showDatePicker(
          context: context,
          initialDate: start,
          firstDate: start,
          lastDate: end.isBefore(start) ? start : end,
        );
        if (picked != null) params.onChanged(DateAnswer(picked));
      },
    );
  }
}

class _UnsupportedField extends StatelessWidget {
  const _UnsupportedField({required this.params});

  final TopicFieldParams params;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.butler.warningSurface,
        borderRadius: AppRadius.mdAll,
      ),
      child: Text('此題型尚未支援', style: AppTypography.caption.copyWith(color: context.butler.warning)),
    );
  }
}
