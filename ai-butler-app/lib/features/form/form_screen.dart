import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/logic/form_validator.dart';
import 'package:ai_butler_app/domain/logic/quotation_calculator.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/models/answer_value.dart';
import 'package:ai_butler_app/domain/models/form_answers.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';
import 'package:ai_butler_app/features/form/topic_widgets.dart';
import 'package:ai_butler_app/providers/form_providers.dart';
import 'package:ai_butler_app/providers/order_providers.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';
import 'package:ai_butler_app/domain/logic/form_answer_serializer.dart';

/// 彈性諮詢單填寫畫面（Requirement 7、8、9）。
class FormScreen extends ConsumerStatefulWidget {
  const FormScreen({super.key, required this.formId, this.serviceId});

  final int formId;

  /// 由服務項目頁帶入的 `cms_homepage_service.id`。
  ///
  /// BFF 的 `GET /app-api/forms/{id}/full` 回應不含 `service_id`，
  /// 因此 [FormDefinition.serviceId] 會是 0；建立 feedback 時優先用這個值。
  final int? serviceId;

  @override
  ConsumerState<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends ConsumerState<FormScreen> {
  ValidationErrors _errors = const <int, String>{};
  bool _isSubmitting = false;
  Timer? _draftTimer;
  bool _draftChecked = false;

  @override
  void dispose() {
    _draftTimer?.cancel();
    super.dispose();
  }

  /// 1 秒 debounce 自動存草稿（Requirement 8.9）。
  void _scheduleDraftSave(FormDefinition definition) {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(seconds: 1), () {
      final answers = ref.read(formAnswersProvider(definition.formId));
      if (answers.values.isEmpty) return;
      final content =
          FormAnswerSerializer.toFeedbackContent(definition, answers);
      ref.read(draftStoreProvider).save(definition.formId, content);
    });
  }

  /// 開啟時偵測草稿並提示（Requirement 8.10-11）。
  Future<void> _checkDraft(FormDefinition definition) async {
    if (_draftChecked) return;
    _draftChecked = true;

    final draftStore = ref.read(draftStoreProvider);
    if (!draftStore.hasDraft(definition.formId)) return;

    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('偵測到未完成的草稿'),
        content: const Text('要繼續填寫上次的內容，還是重新填寫？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('重新填寫'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('繼續填寫'),
          ),
        ],
      ),
    );

    if (choice == false) {
      // 使用者選擇重新填寫（Requirement 8.11）
      await draftStore.delete(definition.formId);
      ref.read(formAnswersProvider(definition.formId).notifier).reset();
    }
    // choice == true：保留 notifier 目前狀態（已載入），不做額外動作
    // 注意：完整的草稿恢復需要 deserialize answers，目前 demo 簡化為只偵測有/無草稿
  }

  @override
  Widget build(BuildContext context) {
    final definitionAsync = ref.watch(formDefinitionProvider(widget.formId));

    return PopScope(
      // 返回時提示已保存草稿（Requirement 8.13）
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final answers = ref.read(formAnswersProvider(widget.formId));
        if (answers.values.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('已保存為草稿'), duration: Duration(seconds: 2)),
          );
        }
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('填寫諮詢單')),
        body: AsyncValueWidget<FormDefinition>(
          value: definitionAsync,
          onRetry: () => ref.invalidate(formDefinitionProvider(widget.formId)),
          data: (definition) {
            // 首次進入時檢查草稿
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _checkDraft(definition));
            return _FormBody(
              definition: definition,
              errors: _errors,
              onErrorsChanged: (errors) => setState(() => _errors = errors),
              onAnswerChanged: () => _scheduleDraftSave(definition),
            );
          },
        ),
        bottomNavigationBar: definitionAsync.maybeWhen(
          data: (definition) => _SubmitBar(
            definition: definition,
            isSubmitting: _isSubmitting,
            onSubmit: () => _submit(definition),
          ),
          orElse: () => null,
        ),
      ),
    );
  }

  Future<void> _submit(FormDefinition definition) async {
    final answers = ref.read(formAnswersProvider(definition.formId));
    final errors = FormValidator.validate(definition, answers);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      final content =
          FormAnswerSerializer.toFeedbackContent(definition, answers);
      final contact = _extractContact(definition, answers);

      // 優先用路由帶進來的 service_id；表單 API 沒有這個欄位，
      // definition.serviceId 幾乎永遠是 0。
      final resolvedServiceId =
          (widget.serviceId != null && widget.serviceId != 0)
              ? widget.serviceId!
              : definition.serviceId;

      final draft = FeedbackDraft(
        serviceId: resolvedServiceId,
        formId: definition.formId,
        formType: definition.type,
        feedbackContent: content,
        contactName: contact.name,
        contactMobile: contact.mobile,
        contactLandline: contact.landline,
        contactEmail: contact.email,
        contactAddressCounty: contact.countyCode,
        contactAddressDistrict: contact.districtCode,
        contactAddressDetail: contact.addressDetail,
      );

      final receipt = await ref.read(feedbackRepositoryProvider).submit(draft);
      ref.read(formAnswersProvider(definition.formId).notifier).reset();
      // 送出成功刪除草稿（Requirement 8.12）
      await ref.read(draftStoreProvider).delete(definition.formId);
      // 讓「訂單紀錄」立即看到這張新諮詢單，不必手動下拉重整。
      ref.invalidate(orderInboxProvider);

      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('送出成功'),
            content: Text('您的諮詢單編號：${receipt.feedbackNo}'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.pop();
                },
                child: const Text('回上一頁'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('送出失敗，請稍後重試')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// 依 Requirement 7.25-26 決定聯絡地址取值優先序（題型 8 優先於題型 5）。
  ({
    String name,
    String mobile,
    String landline,
    String email,
    String countyCode,
    String districtCode,
    String addressDetail
  }) _extractContact(
    FormDefinition definition,
    FormAnswers answers,
  ) {
    final contactTopic =
        definition.firstTopicOfType(TopicType.contactWithAddress) ??
            definition.firstTopicOfType(TopicType.contactWithoutAddress);
    final contactAnswer = contactTopic == null
        ? null
        : answers.answerOf(contactTopic.topicId) as ContactAnswer?;

    if (contactAnswer != null && contactAnswer.includesAddress) {
      return (
        name: contactAnswer.name,
        mobile: contactAnswer.mobile,
        landline: contactAnswer.landline,
        email: contactAnswer.email,
        countyCode: contactAnswer.countyCode,
        districtCode: contactAnswer.districtCode,
        addressDetail: contactAnswer.addressDetail,
      );
    }

    final regionTopic = definition.firstTopicOfType(TopicType.region);
    final regionAnswer = regionTopic == null
        ? null
        : answers.answerOf(regionTopic.topicId) as RegionAnswer?;

    return (
      name: contactAnswer?.name ?? '',
      mobile: contactAnswer?.mobile ?? '',
      landline: contactAnswer?.landline ?? '',
      email: contactAnswer?.email ?? '',
      countyCode: regionAnswer?.countyCode ?? '',
      districtCode: regionAnswer?.districtCode ?? '',
      addressDetail: '',
    );
  }
}

class _FormBody extends ConsumerWidget {
  const _FormBody({
    required this.definition,
    required this.errors,
    required this.onErrorsChanged,
    this.onAnswerChanged,
  });

  final FormDefinition definition;
  final ValidationErrors errors;
  final void Function(ValidationErrors errors) onErrorsChanged;
  final VoidCallback? onAnswerChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(formAnswersProvider(definition.formId));
    final notifier = ref.read(formAnswersProvider(definition.formId).notifier);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        for (final group in definition.sortedGroups) ...<Widget>[
          Text(group.name, style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          for (final topic in group.sortedTopics)
            buildTopicWidget(
              context,
              TopicFieldParams(
                topic: topic,
                answer: answers.answerOf(topic.topicId),
                errorMessage: errors[topic.topicId],
                onChanged: (value) {
                  notifier.setAnswer(topic.topicId, value);
                  onAnswerChanged?.call();
                  final message = FormValidator.validateTopic(topic, value);
                  final next = Map<int, String>.of(errors);
                  if (message == null) {
                    next.remove(topic.topicId);
                  } else {
                    next[topic.topicId] = message;
                  }
                  onErrorsChanged(next);
                },
              ),
            ),
        ],
        if (definition.isQuotation)
          _QuotationSummary(definition: definition, answers: answers),
      ],
    );
  }
}

class _QuotationSummary extends StatelessWidget {
  const _QuotationSummary({required this.definition, required this.answers});

  final FormDefinition definition;
  final FormAnswers answers;

  @override
  Widget build(BuildContext context) {
    final result = QuotationCalculator.calculate(definition, answers);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.butler.surfaceVariant,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('金額試算', style: AppTypography.title),
          const SizedBox(height: AppSpacing.xs),
          for (final item in result.lineItems)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(item.optionName),
                  Text(item.isQuotedSeparately ? '另行報價' : 'NT\$${item.amount}'),
                ],
              ),
            ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text('總計', style: AppTypography.bodyLarge),
              Text('NT\$${result.total}', style: AppTypography.bodyLarge),
            ],
          ),
          if (result.hasSeparatelyQuoted)
            Text(
              '部分項目由廠商另行報價',
              style: AppTypography.caption
                  .copyWith(color: context.butler.secondaryText),
            ),
          Text(
            '金額為系統試算，實際費用以廠商報價為準',
            style: AppTypography.caption
                .copyWith(color: context.butler.secondaryText),
          ),
        ],
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.definition,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final FormDefinition definition;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: FilledButton(
          onPressed: isSubmitting ? null : onSubmit,
          child: isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('送出諮詢單'),
        ),
      ),
    );
  }
}
