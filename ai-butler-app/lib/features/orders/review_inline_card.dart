import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/order_providers.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// 可嵌入訂單卡片或詳情頁的 inline 評價元件。
///
/// 用法：放在任何已完成訂單的區域，它會自動判斷：
/// - 訂單尚未評價 → 顯示星星 + 文字框 + 送出按鈕
/// - 訂單已有評價 → 顯示評價摘要 + 修改按鈕
/// - 訂單未完成或無須評價 → 不渲染（回傳空 widget）
///
/// ```dart
/// ReviewInlineCard(order: myOrderItem)
/// ```
class ReviewInlineCard extends ConsumerStatefulWidget {
  const ReviewInlineCard({super.key, required this.order});

  final OrderItem order;

  @override
  ConsumerState<ReviewInlineCard> createState() => _ReviewInlineCardState();
}

class _ReviewInlineCardState extends ConsumerState<ReviewInlineCard> {
  bool _isExpanded = false;
  bool _isSubmitting = false;
  int _rating = 0;
  late final TextEditingController _contentController;

  bool get _isEditing => widget.order.review != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.order.review;
    _rating = existing?.overallRating ?? 0;
    _contentController =
        TextEditingController(text: existing?.reviewContent ?? '');
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    // 不符合評價條件就不渲染
    if (!order.canReview && !order.isReviewed) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 標題列
            Row(
              children: <Widget>[
                Icon(
                  order.isReviewed
                      ? Icons.rate_review
                      : Icons.rate_review_outlined,
                  size: 20,
                  color: order.isReviewed
                      ? Colors.amber
                      : context.butler.secondaryText,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    order.isReviewed ? '我的評價' : '為這次服務評分',
                    style: AppTypography.bodyLarge,
                  ),
                ),
                if (!_isExpanded)
                  TextButton(
                    onPressed: () => setState(() => _isExpanded = true),
                    child: Text(order.isReviewed ? '查看/修改' : '撰寫評價'),
                  ),
              ],
            ),

            // 已有評價的摘要（收起狀態）
            if (order.isReviewed && !_isExpanded) ...<Widget>[
              const SizedBox(height: AppSpacing.xxs),
              Row(
                children: List.generate(5, (i) {
                  return Icon(
                    i < (order.review?.overallRating ?? 0)
                        ? Icons.star
                        : Icons.star_border,
                    color: Colors.amber,
                    size: 16,
                  );
                }),
              ),
              if (order.review?.reviewContent.isNotEmpty == true) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  order.review!.reviewContent,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body
                      .copyWith(color: context.butler.secondaryText),
                ),
              ],
            ],

            // 展開的編輯區域
            if (_isExpanded) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              // 星星
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final star = index + 1;
                  return GestureDetector(
                    onTap: () => setState(() => _rating = star),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        star <= _rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: AppSpacing.sm),
              // 文字框
              TextField(
                controller: _contentController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '分享您的使用心得...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // 按鈕列
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() => _isExpanded = false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isEditing ? '更新' : '送出'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請選擇評分')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final accountId = ref
              .read(sharedPreferencesProvider)
              .getString('session.inbr_account_id') ??
          '';
      final draft = ReviewDraft(
        inbrAccountId: accountId,
        overallRating: _rating,
        reviewContent: _contentController.text.trim(),
      );

      if (_isEditing) {
        await ref.read(reviewRepositoryProvider).updateReview(
              recordId: widget.order.recordId,
              draft: draft,
            );
      } else {
        await ref.read(reviewRepositoryProvider).createReview(
              recordId: widget.order.recordId,
              draft: draft,
            );
      }

      // 重新整理訂單，讓評價狀態即時反映。
      ref.read(orderInboxProvider.notifier).refreshNow();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? '評價已更新' : '評價已送出')),
        );
        setState(() => _isExpanded = false);
      }
    } catch (error) {
      if (mounted) {
        // 顯示後端的實際原因（例如「訂單狀態不允許評價」），
        // 而不是含糊的「請稍後再試」。
        final reason = error is AppError ? error.message : '$error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_isEditing ? '更新' : '送出'}失敗：$reason'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
