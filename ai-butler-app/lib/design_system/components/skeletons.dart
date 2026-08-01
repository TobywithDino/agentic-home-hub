import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:ai_butler_app/design_system/app_motion.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';

/// 骨架方塊。所有 skeleton 版面都由這個積木拼出來，
/// 確保各畫面的載入態長相一致（Requirement 18.8、22.6）。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.butler.surfaceVariant,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// 把一組 skeleton 包上 shimmer 動畫。
/// 系統啟用減少動態效果時退化為靜態灰塊（Requirement 18.14）。
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.resolve(context, AppMotion.page) == Duration.zero) {
      return child;
    }
    return Shimmer.fromColors(
      baseColor: context.butler.surfaceVariant,
      highlightColor: context.butler.neutralSurface,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

/// 服務商卡片的骨架版面（Requirement 5.4）
class VendorCardSkeleton extends StatelessWidget {
  const VendorCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.fromBorderSide(BorderSide(color: context.butler.border)),
      ),
      child: const Row(
        children: <Widget>[
          SkeletonBox(width: 72, height: 72, radius: AppRadius.md),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonBox(width: 160, height: 16),
                SizedBox(height: AppSpacing.xs),
                SkeletonBox(height: 12),
                SizedBox(height: AppSpacing.xxs),
                SkeletonBox(width: 120, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 清單列的骨架版面（Requirement 15.10）
class ListRowSkeleton extends StatelessWidget {
  const ListRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.fromBorderSide(BorderSide(color: context.butler.border)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              SkeletonBox(width: 120, height: 14),
              SkeletonBox(width: 56, height: 20, radius: AppRadius.xl),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(height: 12),
          SizedBox(height: AppSpacing.xxs),
          SkeletonBox(width: 140, height: 12),
        ],
      ),
    );
  }
}

/// 產生 n 個骨架項目的清單。
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 3,
    required this.itemBuilder,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.gap = AppSpacing.sm,
  });

  final int itemCount;
  final WidgetBuilder itemBuilder;
  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(height: gap),
        itemBuilder: (context, _) => itemBuilder(context),
      ),
    );
  }
}

/// 只有等待超過 [AppMotion.skeletonThreshold] 才顯示 skeleton，
/// 避免快取命中時的閃爍（Requirement 18.8）。
class DelayedLoader extends StatefulWidget {
  const DelayedLoader({
    super.key,
    required this.skeleton,
    this.delay = AppMotion.skeletonThreshold,
  });

  final Widget skeleton;
  final Duration delay;

  @override
  State<DelayedLoader> createState() => _DelayedLoaderState();
}

class _DelayedLoaderState extends State<DelayedLoader> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay).then((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: AppMotion.resolve(context, AppMotion.fast),
      child: widget.skeleton,
    );
  }
}
