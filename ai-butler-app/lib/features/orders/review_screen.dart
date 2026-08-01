import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/order_providers.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// 提交/修改評價畫面。
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({
    super.key,
    required this.order,
  });

  final OrderItem order;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _rating = 0;
  late final TextEditingController _contentController;
  bool _isSubmitting = false;

  bool get _isEditing => widget.order.review != null;

  @override
  void initState() {
    super.initState();
    final existingReview = widget.order.review;
    if (existingReview != null) {
      _rating = existingReview.overallRating;
      _contentController =
          TextEditingController(text: existingReview.reviewContent);
    } else {
      _contentController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
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

      // 重新整理訂單列表
      ref.invalidate(orderInboxProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? '評價已更新' : '評價已送出')),
        );
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '修改評價' : '新增評價')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 訂單資訊
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.order.serviceName,
                        style: AppTypography.bodyLarge),
                    const SizedBox(height: AppSpacing.xxs),
                    Text('訂單編號：${widget.order.orderNo}',
                        style: AppTypography.caption
                            .copyWith(color: context.butler.secondaryText)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 星星評分
            const Text('整體評分', style: AppTypography.title),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                return IconButton(
                  icon: Icon(
                    starIndex <= _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 36,
                  ),
                  onPressed: () => setState(() => _rating = starIndex),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.lg),

            // 文字評價
            const Text('評價內容（選填）', style: AppTypography.title),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _contentController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '分享您的使用心得...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // 送出按鈕
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEditing ? '更新評價' : '送出評價'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
