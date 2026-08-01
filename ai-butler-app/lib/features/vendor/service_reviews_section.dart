import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';
import 'package:intl/intl.dart';

/// 服務評價區塊 provider（依 serviceId 抓取評價）
final serviceReviewsProvider =
    FutureProvider.autoDispose.family<List<OrderReview>, int>((ref, serviceId) {
  return ref.watch(reviewRepositoryProvider).fetchServiceReviews(serviceId);
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
            // 評價列表（最多顯示 10 則）
            for (final review in reviews.take(10))
              _ReviewCard(review: review),
          ],
        );
      },
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
