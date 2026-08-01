import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:ai_butler_app/design_system/components/service_category_tile.dart';
import 'package:ai_butler_app/design_system/components/skeletons.dart';
import 'package:ai_butler_app/providers/catalog_providers.dart';
import 'package:ai_butler_app/router/routes.dart';

/// 底部導覽「服務」分頁：全部服務類別清單 + 跨類別搜尋
/// （Requirement 4.16-19）。
class ServiceCatalogScreen extends ConsumerStatefulWidget {
  const ServiceCatalogScreen({super.key});

  @override
  ConsumerState<ServiceCatalogScreen> createState() =>
      _ServiceCatalogScreenState();
}

class _ServiceCatalogScreenState extends ConsumerState<ServiceCatalogScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(serviceCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('服務')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜尋服務商',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => context.push(
                '${Routes.vendors}?keyword=${Uri.encodeQueryComponent(value)}',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: AsyncValueWidget<List<dynamic>>(
                value: categoriesAsync,
                skeleton: SkeletonList(
                    itemCount: 5, itemBuilder: (_) => const ListRowSkeleton()),
                onRetry: () => ref.invalidate(serviceCategoriesProvider),
                data: (categories) => ListView.separated(
                  itemCount: categories.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return ListTile(
                      leading: Icon(categoryIcon(category.type)),
                      title:
                          Text(category.name, style: AppTypography.bodyLarge),
                      subtitle: Text('${category.vendorCount ?? 0} 家服務商'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(
                          '${Routes.vendors}?serviceId=${category.serviceId}'),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
