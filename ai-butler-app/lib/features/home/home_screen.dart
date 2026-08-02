import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/service_category_tile.dart';
import 'package:ai_butler_app/design_system/components/skeletons.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/services/butler_ai_service.dart';
import 'package:ai_butler_app/features/tour/tour_anchors.dart';
import 'package:ai_butler_app/features/tour/tour_leg_host.dart';
import 'package:ai_butler_app/features/tour/tour_plan.dart';
import 'package:ai_butler_app/features/tour/tour_session.dart';
import 'package:ai_butler_app/providers/catalog_providers.dart';
import 'package:ai_butler_app/providers/session_providers.dart';
import 'package:ai_butler_app/router/routes.dart';

/// AI 生活管家首頁（Requirement 4）。
///
/// 版面刻意用單一 [CustomScrollView] + slivers：先前 `SingleChildScrollView`
/// 內嵌 `GridView`／`Wrap` 加手算寬度的寫法會在 layout 期間互相觸發
/// re-layout，造成 `RenderBox was not laid out` 連鎖錯誤而整頁空白。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(serviceCategoriesProvider);
    final authState = ref.watch(authNotifierProvider);
    // 必須 watch（不是 read）：首頁是 StatefulShellRoute.indexedStack 的分頁，
    // 四個分頁會一直保持已建置狀態，切回首頁只是換 IndexedStack 的 index，
    // 不會重新 build。少了這行，AI 管家啟動導覽後首頁的 build 不會重跑，
    // _maybeStartHomeTour 永遠不會被呼叫 —— 實測就是「跳到首頁但沒有導覽」。
    ref.watch(tourSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI 生活管家')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(serviceCategoriesProvider.future),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  _ButlerGreeting(
                    name: authState.isLoggedIn ? '您好' : '訪客',
                    // 用 go 而非 push：AI 管家是 shell 的分頁，
                    // 要切換 branch 而不是疊一層新畫面在上面。
                    onTap: () => context.go(Routes.chat),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text('服務項目', style: AppTypography.title),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              sliver: categoriesAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: SkeletonBox(height: 96),
                  ),
                ),
                error: (error, _) => SliverToBoxAdapter(
                  child: _CategoriesError(
                    error: error,
                    onRetry: () => ref.invalidate(serviceCategoriesProvider),
                  ),
                ),
                data: (categories) {
                  // 分類磚渲染完才能圈它，所以導覽在這裡啟動而不是在 build
                  // 開頭 —— categoriesAsync 還在 loading 時錨點根本不存在。
                  _maybeStartHomeTour(context, ref, categories);
                  return _CategoryGrid(categories: categories);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 啟動「帶我操作一遍」的第一段：圈出對應的服務類別磚。
///
/// 管家給的 `service_type` 是未補零的 `'6'`，而 [ServiceCategory.type] 是
/// 兩位數 `'06'`，所以用 `normalizedServiceType` 比對。對不上（例如那個類別
/// 目前沒有任何服務商而沒被列出來）就直接結束 session，不要讓使用者對著
/// 一個永遠不會出現的光圈等。
void _maybeStartHomeTour(
  BuildContext context,
  WidgetRef ref,
  List<ServiceCategory> categories,
) {
  final session = ref.read(tourSessionProvider);
  if (session == null || session.leg != TourLeg.home) return;

  tourLog('首頁收到導覽請求，分類共 ${categories.length} 個');

  final card = session.card;
  final anchors = ref.read(tourAnchorsProvider);

  maybeStartTourLeg(
    ref: ref,
    context: context,
    leg: TourLeg.home,
    buildSteps: () {
      // 兩邊都正規化：真實 API 的分類是 '6'，mock 是 '06'，
      // 只正規化其中一邊會在換資料來源時比不到。
      final wanted = card.normalizedServiceType;
      final target = categories
          .where((c) => PrefillCard.normalizeServiceType(c.type) == wanted)
          .firstOrNull;
      if (target == null) {
        tourLog('首頁找不到 service_type=$wanted 的分類'
            '（現有：${categories.map((c) => c.type).join(",")}）');
        return null;
      }
      return TourPlan.homeLeg(
        categoryAnchor: anchors.of(TourAnchorIds.homeCategory(target.type)),
        categoryName: target.name,
        onTap: () {
          ref.read(tourSessionProvider.notifier).advanceTo(TourLeg.vendorList);
          context.push('${Routes.vendors}?serviceId=${target.serviceId}');
        },
      );
    },
  );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories});

  final List<ServiceCategory> categories;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            '目前沒有可預約的服務項目',
            style: AppTypography.body
                .copyWith(color: context.butler.secondaryText),
          ),
        ),
      );
    }

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.md,
        // 圖示 56 + 間距 + 一行文字，留一點餘裕避免溢出。
        childAspectRatio: 0.82,
      ),
      delegate: SliverChildBuilderDelegate(
        childCount: categories.length,
        (context, index) {
          final category = categories[index];
          return Consumer(
            builder: (context, ref, _) => ServiceCategoryTile(
              // 兼作 list 識別與導覽錨點。GlobalKey 由 TourAnchors 快取，
              // 每次 build 都是同一個實例，不會破壞 grid 的 diff。
              key: ref
                  .read(tourAnchorsProvider)
                  .of(TourAnchorIds.homeCategory(category.type)),
              category: category,
              onTap: () => context.push(
                '${Routes.vendors}?serviceId=${category.serviceId}',
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoriesError extends StatelessWidget {
  const _CategoriesError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = switch (error) {
      final dynamic e when e is Exception && _hasMessage(e) =>
        (e as dynamic).message as String,
      _ => '服務項目載入失敗',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            message,
            style: AppTypography.body
                .copyWith(color: context.butler.secondaryText),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('重新載入')),
        ],
      ),
    );
  }

  static bool _hasMessage(Object error) {
    try {
      return (error as dynamic).message is String;
    } catch (_) {
      return false;
    }
  }
}

/// 首頁問候卡，點擊即切換到 AI 管家分頁。
class _ButlerGreeting extends StatelessWidget {
  const _ButlerGreeting({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '詢問 AI 管家',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: AppRadius.lgAll,
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context).colorScheme.surface,
                child: Icon(Icons.smart_toy_outlined,
                    color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '$name，今天想安排什麼生活服務呢？',
                      style: AppTypography.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    // 明示這張卡可以點，否則使用者不會知道。
                    Text(
                      '點我跟 AI 管家說說看',
                      style: AppTypography.caption.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
