import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:ai_butler_app/design_system/components/simple_html_view.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/vendor_providers.dart';
import 'package:ai_butler_app/router/routes.dart';

/// 服務商詳情（Requirement 6）。
class VendorDetailScreen extends ConsumerWidget {
  const VendorDetailScreen({super.key, required this.vendorId});

  final int vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(vendorDetailProvider(vendorId));

    return Scaffold(
      body: AsyncValueWidget<VendorDetail>(
        value: detailAsync,
        onRetry: () => ref.invalidate(vendorDetailProvider(vendorId)),
        data: (vendor) => _DetailBody(vendor: vendor),
      ),
      bottomNavigationBar: detailAsync.maybeWhen(
        data: (vendor) => VendorDetailSubmitBar(vendor: vendor),
        orElse: () => null,
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.vendor});

  final VendorDetail vendor;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: Hero(
              tag: 'vendor-${vendor.vendorId}',
              child: CachedNetworkImage(
                imageUrl: vendor.imgUrl,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                errorWidget: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.primaryContainer),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.md),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              Text(vendor.name, style: AppTypography.headline),
              if (vendor.rating != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: <Widget>[
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    Text(' ${vendor.rating!.toStringAsFixed(1)}'),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (vendor.introContent.isNotEmpty)
                ExpansionTile(
                  title: const Text('服務介紹'),
                  initiallyExpanded: true,
                  children: <Widget>[
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: SimpleHtmlView(html: vendor.introContent),
                    ),
                  ],
                ),
              if (vendor.noticeContent.isNotEmpty)
                ExpansionTile(
                  title: const Text('注意事項'),
                  children: <Widget>[
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: SimpleHtmlView(html: vendor.noticeContent),
                    ),
                  ],
                ),
              if (vendor.termsContent.isNotEmpty)
                ExpansionTile(
                  title: const Text('服務條款'),
                  children: <Widget>[
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: SimpleHtmlView(html: vendor.termsContent),
                    ),
                  ],
                ),
              const SizedBox(height: 80),
            ]),
          ),
        ),
      ],
    );
  }
}

/// 底部固定的「填寫諮詢單」按鈕，抽成獨立元件供 Scaffold.bottomNavigationBar 使用。
class VendorDetailSubmitBar extends StatelessWidget {
  const VendorDetailSubmitBar({super.key, required this.vendor});

  final VendorDetail vendor;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: FilledButton(
          onPressed: () => context.push(Routes.form(vendor.formId)),
          child: const Text('填寫諮詢單'),
        ),
      ),
    );
  }
}
