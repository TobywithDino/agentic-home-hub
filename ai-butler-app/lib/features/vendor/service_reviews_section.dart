import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/models/review_summary.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';
import 'package:intl/intl.dart';

/// 服務評價區塊 provider（依 serviceId 抓取評價）
final serviceReviewsProvider =
    FutureProvider.autoDispose.family<List<OrderReview>, int>((ref, serviceId) {
  return ref.watch(reviewRepositoryProvider).fetchServiceReviews(serviceId);
});

/// 服務項目的評價 AI 摘要。尚未生成時後端回 404 → 這裡拿到 null。
final serviceReviewSummaryProvider = FutureProvider.autoDispose
    .family<ReviewSummary?, int>((ref, serviceId) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.getOptional<Map<String, dynamic>>(
    ApiEndpoints.serviceReviewSummary(serviceId),
  );
  final body = response?.data;
  if (body == null) return null;
  return ReviewSummary.fromJson(body);
});

/// 顯示某個服務項目的評價列表。
class ServiceReviewsSection extends ConsumerWidget {
  const ServiceReviewsSection({super.key, required this.serviceId});

  final int serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(serviceReviewsProvider(serviceId));

    return reviewsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (reviews) {
        if (reviews.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              '尚無評價',
              style: AppTypography.body
                  .copyWith(color: context.butler.secondaryText),
            ),
          );
        }

        // 計算平均分
        final avg = reviews.fold<int>(0, (sum, r) => sum + r.overallRating) /
            reviews.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 評分摘要
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.star, color: Colors.amber, size: 20),
                  const SizedBox(width: 4),
                  Text(avg.toStringAsFixed(1), style: AppTypography.bodyLarge),
                  const SizedBox(width: 8),
                  Text(
                    '(${reviews.length} 則評價)',
                    style: AppTypography.caption
                        .copyWith(color: context.butler.secondaryText),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // AI 摘要（尚未生成時整塊不顯示）
            _AiSummaryCard(serviceId: serviceId),
            // 評價列表（最多顯示 10 則）
            for (final review in reviews.take(10)) _ReviewCard(review: review),
          ],
        );
      },
    );
  }
}

/// 評價 AI 摘要卡。
///
/// 尚未生成（後端 404）或生成失敗時整塊不顯示，避免使用者看到空殼區塊。
/// 生成中／內容過期則以提示文字說明，並提供「AI 摘要說明」提示窗。
class _AiSummaryCard extends ConsumerWidget {
  const _AiSummaryCard({required this.serviceId});

  final int serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(serviceReviewSummaryProvider(serviceId));

    return summaryAsync.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (summary) {
        if (summary == null) return const SizedBox.shrink();

        // 生成中：先讓使用者知道摘要正在準備。
        if (summary.status == SummaryStatus.generating ||
            summary.status == SummaryStatus.pending) {
          return _Shell(
            child: Row(
              children: <Widget>[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'AI 正在整理這個服務的評價摘要…',
                    style: AppTypography.caption
                        .copyWith(color: context.butler.secondaryText),
                  ),
                ),
              ],
            ),
          );
        }

        if (!summary.hasContent) return const SizedBox.shrink();

        return _Shell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.auto_awesome,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: AppSpacing.xxs),
                  const Text('AI 評價摘要', style: AppTypography.label),
                  const Spacer(),
                  // 提示窗入口
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    tooltip: 'AI 摘要說明',
                    onPressed: () => _showInfoDialog(context, summary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              // 摘要字數不多，直接完整顯示，不做收合／展開
              Text(summary.summaryContent, style: AppTypography.body),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _footnote(summary),
                style: AppTypography.caption
                    .copyWith(color: context.butler.secondaryText),
              ),
              if (summary.isStale)
                Text(
                  '有新評價尚未納入這份摘要',
                  style: AppTypography.caption
                      .copyWith(color: context.butler.warning),
                ),
            ],
          ),
        );
      },
    );
  }

  String _footnote(ReviewSummary summary) {
    final parts = <String>[
      '彙整 ${summary.sourceReviewCount} 則評價',
      if (summary.sourceAvgRating != null)
        '平均 ${summary.sourceAvgRating!.toStringAsFixed(1)} 分',
    ];
    return parts.join(' · ');
  }

  /// 提示窗：資料來源與 AI 生成的免責說明。
  ///
  /// 摘要本文已在卡片上完整顯示，這裡不再重複。
  Future<void> _showInfoDialog(
      BuildContext context, ReviewSummary summary) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: <Widget>[
            Icon(Icons.auto_awesome,
                size: 18, color: Theme.of(dialogContext).colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            const Text('AI 摘要說明'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _footnote(summary),
                style: AppTypography.caption
                    .copyWith(color: dialogContext.butler.secondaryText),
              ),
              if (summary.generateTime != null)
                Text(
                  '產生時間：'
                  '${DateFormat('yyyy/MM/dd HH:mm').format(summary.generateTime!)}',
                  style: AppTypography.caption
                      .copyWith(color: dialogContext.butler.secondaryText),
                ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '這段摘要由 AI 依實際評價自動整理，可能不完全精確，'
                '建議搭配下方原始評價一起參考。',
                style: AppTypography.caption
                    .copyWith(color: dialogContext.butler.secondaryText),
              ),
              if (summary.isStale) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '有新評價尚未納入這份摘要。',
                  style: AppTypography.caption
                      .copyWith(color: dialogContext.butler.warning),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }
}

/// 摘要卡外框，統一邊距與底色。
class _Shell extends StatelessWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: AppRadius.mdAll,
      ),
      child: child,
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final OrderReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // 星星
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < review.overallRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 16,
                    ),
                  ),
                  const Spacer(),
                  if (review.creTime != null)
                    Text(
                      DateFormat('yyyy/MM/dd').format(review.creTime!),
                      style: AppTypography.caption
                          .copyWith(color: context.butler.secondaryText),
                    ),
                ],
              ),
              if (review.reviewContent.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(review.reviewContent, style: AppTypography.body),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
