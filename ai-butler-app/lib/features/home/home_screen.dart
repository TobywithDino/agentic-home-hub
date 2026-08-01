import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:ai_butler_app/design_system/components/skeletons.dart';
import 'package:ai_butler_app/design_system/components/service_category_tile.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/catalog_providers.dart';
import 'package:ai_butler_app/providers/session_providers.dart';
import 'package:ai_butler_app/router/routes.dart';

/// AI 生活管家首頁（Requirement 4）。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(serviceCategoriesProvider);
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 生活管家'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(serviceCategoriesProvider.future),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ButlerGreeting(name: authState.isLoggedIn ? '王小明' : '訪客'),
              const SizedBox(height: AppSpacing.md),
              _ChatEntryField(onTap: () => context.push(Routes.chat)),
              const SizedBox(height: AppSpacing.lg),
              const Text('服務項目', style: AppTypography.title),
              const SizedBox(height: AppSpacing.sm),
              AsyncValueWidget<List<ServiceCategory>>(
                value: categoriesAsync,
                skeleton: const SkeletonList(
                    itemCount: 1, itemBuilder: _skeletonGrid),
                onRetry: () => ref.invalidate(serviceCategoriesProvider),
                data: (categories) => Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.md,
                  children: <Widget>[
                    for (final category in categories)
                      SizedBox(
                        width: (MediaQuery.of(context).size.width -
                                AppSpacing.md * 2 -
                                AppSpacing.sm * 3) /
                            4,
                        child: ServiceCategoryTile(
                          key: ValueKey(category.serviceId),
                          category: category,
                          onTap: () => context.push(
                            '${Routes.vendors}?serviceId=${category.serviceId}',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _skeletonGrid(BuildContext context) =>
      const SkeletonBox(height: 96);
}

class _ButlerGreeting extends StatelessWidget {
  const _ButlerGreeting({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: Text(
              '$name，今天想安排什麼生活服務呢？',
              style: AppTypography.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatEntryField extends StatelessWidget {
  const _ChatEntryField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.xlAll,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: AppRadius.xlAll,
          border: Border.all(color: context.butler.border),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.chat_bubble_outline,
                color: context.butler.secondaryText),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '輸入你的生活需求…',
                style: AppTypography.body
                    .copyWith(color: context.butler.secondaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
