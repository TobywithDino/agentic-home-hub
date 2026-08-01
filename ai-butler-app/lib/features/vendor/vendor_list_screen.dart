import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/skeletons.dart';
import 'package:ai_butler_app/design_system/components/stagger.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/features/vendor/vendor_filter_panel.dart';
import 'package:ai_butler_app/providers/vendor_providers.dart';
import 'package:ai_butler_app/router/routes.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 服務商列表（Requirement 5）。
class VendorListScreen extends ConsumerStatefulWidget {
  const VendorListScreen({super.key, this.serviceId, this.keyword = ''});

  final int? serviceId;
  final String keyword;

  @override
  ConsumerState<VendorListScreen> createState() => _VendorListScreenState();
}

class _VendorListScreenState extends ConsumerState<VendorListScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _debounce;

  // 累積載入的項目（分頁用）
  final List<VendorSummary> _loadedItems = [];
  bool _hasMore = false;
  bool _isLoadingMore = false;
  VendorCapabilities _capabilities = VendorCapabilities.none;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.keyword;
    _scrollController.addListener(_onScroll);

    // 設初始查詢條件
    Future<void>.microtask(() {
      ref.read(vendorQueryProvider.notifier).setQuery(
            VendorQuery(serviceId: widget.serviceId, keyword: widget.keyword),
          );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// 距底部 200px 時載入下一頁（Requirement 5.18）
  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    setState(() => _isLoadingMore = true);
    final currentQuery = ref.read(vendorQueryProvider);
    final nextQuery = currentQuery.copyWith(page: currentQuery.page + 1);
    ref.read(vendorQueryProvider.notifier).setQuery(nextQuery);
    // 實際載入由 vendorSearchProvider 自動處理，下方 listener 會累積資料
  }

  /// 300ms debounce（Requirement 5.17）
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _loadedItems.clear();
      ref.read(vendorQueryProvider.notifier).setQuery(
            ref.read(vendorQueryProvider).copyWith(keyword: value, page: 1),
          );
    });
  }

  Future<void> _openFilter() async {
    final currentQuery = ref.read(vendorQueryProvider);
    final newQuery = await VendorFilterPanel.show(
      context,
      currentQuery: currentQuery,
      capabilities: _capabilities,
    );
    if (newQuery != null) {
      _loadedItems.clear();
      ref.read(vendorQueryProvider.notifier).setQuery(newQuery);
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0); // Requirement 5.14：套用後回到頂端
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultAsync = ref.watch(vendorSearchProvider);
    final currentQuery = ref.watch(vendorQueryProvider);
    final filterCount = currentQuery.activeFilterCount;

    // 收到新資料時累積
    resultAsync.whenData((page) {
      if (currentQuery.page == 1) {
        _loadedItems
          ..clear()
          ..addAll(page.items);
      } else {
        // 避免重複加入（provider rebuild 可能重複觸發）
        final existingIds = _loadedItems.map((v) => v.vendorId).toSet();
        _loadedItems
            .addAll(page.items.where((v) => !existingIds.contains(v.vendorId)));
      }
      _hasMore = page.hasMore;
      _capabilities = page.capabilities;
      _isLoadingMore = false;
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.serviceId == null ? '全部服務' : '服務商列表'),
        actions: <Widget>[
          // 篩選按鈕含角標（Requirement 5.15）
          Stack(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.tune_outlined),
                onPressed: _openFilter,
                tooltip: '篩選',
              ),
              if (filterCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$filterCount',
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 關鍵字搜尋欄
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜尋服務商',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // 標題列：類別名稱 + 筆數（Requirement 5.3）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: resultAsync.maybeWhen(
              data: (page) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '共 ${page.totalCount} 家服務商',
                  style: AppTypography.caption
                      .copyWith(color: context.butler.secondaryText),
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // 清單主體
          Expanded(
            child: resultAsync.when(
              loading: () => SkeletonList(
                itemCount: 4,
                itemBuilder: (_) => const VendorCardSkeleton(),
              ),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text('載入失敗'),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(vendorSearchProvider),
                      child: const Text('重新載入'),
                    ),
                  ],
                ),
              ),
              data: (page) {
                if (_loadedItems.isEmpty) {
                  return _EmptyState(
                    onClearFilter: filterCount > 0
                        ? () {
                            _loadedItems.clear();
                            ref.read(vendorQueryProvider.notifier).setQuery(
                                  VendorQuery(serviceId: widget.serviceId),
                                );
                            _searchController.clear();
                          }
                        : null,
                  );
                }
                return ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: _loadedItems.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    if (index >= _loadedItems.length) {
                      // 底部載入指示器（Requirement 5.19）
                      return const Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final vendor = _loadedItems[index];
                    return StaggeredItem(
                      index: index,
                      itemCount: _loadedItems.length,
                      enabled: currentQuery.page == 1, // 第一頁才播動畫
                      child: _VendorCard(
                        vendor: vendor,
                        onTap: () =>
                            context.push(Routes.vendorDetail(vendor.vendorId)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onClearFilter});

  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.search_off_outlined,
              size: 48, color: context.butler.secondaryText),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '找不到符合條件的服務商',
            style: AppTypography.body
                .copyWith(color: context.butler.secondaryText),
          ),
          if (onClearFilter != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: onClearFilter,
              child: const Text('清除篩選條件'),
            ),
          ],
        ],
      ),
    );
  }
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor, required this.onTap});

  final VendorSummary vendor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.lgAll,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: context.butler.border),
        ),
        child: Row(
          children: <Widget>[
            Hero(
              tag: 'vendor-${vendor.vendorId}',
              child: ClipRRect(
                borderRadius: AppRadius.mdAll,
                child: CachedNetworkImage(
                  imageUrl: vendor.imgUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  memCacheWidth: 144,
                  fadeInDuration: const Duration(milliseconds: 150),
                  errorWidget: (_, __, ___) => Container(
                    width: 72,
                    height: 72,
                    color: context.butler.surfaceVariant,
                    child: const Icon(Icons.storefront_outlined),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(vendor.name, style: AppTypography.bodyLarge),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    vendor.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption
                        .copyWith(color: context.butler.secondaryText),
                  ),
                  if (vendor.rating != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: <Widget>[
                        Icon(Icons.star,
                            size: 14, color: context.butler.warning),
                        Text(' ${vendor.rating!.toStringAsFixed(1)}',
                            style: AppTypography.caption),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
