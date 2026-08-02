import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/logic/draft_prefill_mapper.dart';
import 'package:ai_butler_app/domain/logic/form_answer_serializer.dart';
import 'package:ai_butler_app/domain/logic/form_validator.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/models/form_answers.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';
import 'package:ai_butler_app/domain/models/answer_value.dart';
import 'package:ai_butler_app/domain/services/butler_ai_service.dart';
import 'package:ai_butler_app/providers/form_providers.dart';
import 'package:ai_butler_app/providers/order_providers.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// 諮詢單草稿的分叉點：「直接送出」或「帶我操作一遍」。
///
/// 這是整個 AI 管家流程的關鍵一步。管家**沒有寫入權限**，草稿一定要由使用者
/// 在這裡選擇才會真的送出 —— 選「直接送出」是 App 帶使用者身分呼叫既有的
/// `POST /app-api/feedbacks`，選「帶我操作」則是進表單頁跑光圈導覽，
/// 最後仍然由使用者自己按送出鈕。
/// 使用者在草稿卡的分叉點選了什麼。
enum DraftSheetAction {
  /// 已經直接送出，呼叫端不用再做事
  submitted,

  /// 要「帶我操作一遍」，由呼叫端啟動導覽
  guide,
}

/// 顯示分叉點，回傳使用者的選擇（直接關掉則回 null）。
///
/// **導覽的啟動刻意不放在這個 sheet 裡。** sheet 被 pop 之後它的
/// `ConsumerState` 就開始銷毀，用那個已失效的 `ref` 去改 provider 會安靜地
/// 什麼都沒發生（實測就是「跳回首頁但導覽沒啟動」）。所以改成回傳選擇，
/// 由聊天畫面來啟動 —— 它是 shell 分頁，全程都活著。
///
/// 附帶好處：`await` 會等到 sheet 完全關閉才 resolve，所以不需要用固定延遲
/// 去猜退場動畫的長度，光圈也不會疊在正在往下滑的 sheet 上。
Future<DraftSheetAction?> showPrefillDraftSheet(
  BuildContext context,
  PrefillCard card,
) {
  return showModalBottomSheet<DraftSheetAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PrefillSheet(card: card),
  );
}

class _PrefillSheet extends ConsumerStatefulWidget {
  const _PrefillSheet({required this.card});

  final PrefillCard card;

  @override
  ConsumerState<_PrefillSheet> createState() => _PrefillSheetState();
}

class _PrefillSheetState extends ConsumerState<_PrefillSheet> {
  bool _isSubmitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('請確認以下內容', style: AppTypography.title),
            const SizedBox(height: AppSpacing.xs),
            Text(card.summary, style: AppTypography.body),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '管家已整理 ${card.answers.length} 題',
              style: AppTypography.caption
                  .copyWith(color: context.butler.secondaryText),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: context.butler.surfaceVariant,
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  _error!,
                  style: AppTypography.caption
                      .copyWith(color: context.butler.error),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSubmitting ? null : _submitDirectly,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_isSubmitting ? '送出中…' : '直接送出'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _startGuidedTour,
                icon: const Icon(Icons.touch_app_outlined, size: 18),
                label: const Text('帶我操作一遍'),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '選「帶我操作」會從首頁開始帶你走一遍，'
              '讓你知道下次怎麼自己找到這裡，最後由你自己按送出。',
              style: AppTypography.caption
                  .copyWith(color: context.butler.secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  /// 帶我操作：**從首頁開始**教一遍完整的 GUI 路徑。
  ///
  /// 刻意不直接跳到填單頁。這個功能的目的是「教他下次自己也會用」，
  /// 直接丟到表單頁的話他只學到怎麼填表，不知道這張表單在 App 的哪裡、
  /// 怎麼自己走到這一步。所以導覽走完整路徑：
  /// 首頁分類 → 服務商列表 → 商家詳情 → 填單頁逐題 → 送出。
  ///
  /// 用 `go` 而不是 `push`：首頁是 shell 的分頁，要切 branch 而不是疊一層。
  /// 疊上去的話使用者按返回會回到聊天室而不是離開導覽，路徑會亂掉。
  /// 只回報選擇，實際啟動導覽由聊天畫面做（見 [showPrefillDraftSheet] 的說明）。
  void _startGuidedTour() {
    Navigator.of(context).pop(DraftSheetAction.guide);
  }

  /// 直接送出。
  ///
  /// 刻意不把 agent 的 `feedback_content` 原樣轉送，而是先取表單定義、
  /// 走一次跟 GUI 完全相同的「型別化作答 → 序列化 → 驗證」流程。原因有兩個：
  ///   1. agent 的結構是 `{topic_id: {title, value}}`，GUI 送的是
  ///      `FormAnswerSerializer` 的格式。兩種形狀混進同一張表會讓商家後台
  ///      與之後的報表無法統一解析。
  ///   2. 地區與照片這類題目管家填不了，原樣轉送會送出缺必填的單子。
  ///      這裡驗證不過就擋下來，改叫使用者走導覽補齊。
  Future<void> _submitDirectly() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final card = widget.card;
      final definition =
          await ref.read(formDefinitionProvider(card.formId).future);

      final mapped = DraftPrefillMapper.map(
        definition: definition,
        answers: card.answers,
        payload: card.payload,
      );

      final answers = const FormAnswers().applyPrefill(mapped.prefill);
      final errors = FormValidator.validate(definition, answers);

      if (errors.isNotEmpty) {
        final titles = errors.keys
            .map((id) => definition.topicById(id)?.title ?? '第 $id 題')
            .take(3)
            .join('、');
        setState(() {
          _isSubmitting = false;
          _error = '有 ${errors.length} 題我沒辦法幫你填完（$titles）。'
              '請改選「帶我操作一遍」，我會帶你把這幾題補起來。';
        });
        return;
      }

      final contact = _contactFrom(definition, answers, card.payload);
      final receipt = await ref.read(feedbackRepositoryProvider).submit(
            FeedbackDraft(
              serviceId: card.serviceId,
              formId: definition.formId,
              formType: definition.type,
              feedbackContent:
                  FormAnswerSerializer.toFeedbackContent(definition, answers),
              contactName: contact.name,
              contactMobile: contact.mobile,
              contactEmail: contact.email,
              contactLandline: contact.landline,
              description: (card.payload['description'] as String?) ?? '',
            ),
          );

      // 讓「訂單紀錄」立刻看到這張新諮詢單
      ref.invalidate(orderInboxProvider);

      if (!mounted) return;
      Navigator.of(context).pop(DraftSheetAction.submitted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已送出，諮詢單編號 ${receipt.feedbackNo}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = '送出失敗，請稍後重試，或改選「帶我操作一遍」自己送出。';
      });
    }
  }

  /// 聯絡資料優先取表單裡的聯絡題（型 08 優於 10），沒有才退回草稿頂層欄位。
  ({String name, String mobile, String email, String landline}) _contactFrom(
    FormDefinition definition,
    FormAnswers answers,
    Map<String, dynamic> payload,
  ) {
    final topic = definition.firstTopicOfType(TopicType.contactWithAddress) ??
        definition.firstTopicOfType(TopicType.contactWithoutAddress);
    final answer =
        topic == null ? null : answers.answerOf(topic.topicId) as ContactAnswer?;

    return (
      name: answer?.name.isNotEmpty == true
          ? answer!.name
          : (payload['contact_name'] as String? ?? ''),
      mobile: answer?.mobile.isNotEmpty == true
          ? answer!.mobile
          : (payload['contact_mobile'] as String? ?? ''),
      email: answer?.email.isNotEmpty == true
          ? answer!.email
          : (payload['contact_email'] as String? ?? ''),
      landline: answer?.landline ?? '',
    );
  }
}
