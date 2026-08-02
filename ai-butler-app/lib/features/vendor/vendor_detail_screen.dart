import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:ai_butler_app/design_system/components/simple_html_view.dart';
import 'package:ai_butler_app/features/vendor/service_reviews_section.dart';
import 'package:ai_butler_app/providers/vendor_providers.dart';
import 'package:ai_butler_app/router/routes.dart';

/// 服務商詳情（Requirement 6）。
///
/// 進入後先用 vendorServicesProvider 抓取廠商所有服務項目，
/// 若同 type 有多個服務，頂部顯示 ChoiceChip 讓使用者切換。
class VendorDetailScreen extends ConsumerStatefulWidget {
  const VendorDetailScreen({
    super.key,
    required this.vendorId,
    this.serviceType,
  });

  final int vendorId;

  /// 使用者瀏覽中的服務類型；有值時只顯示該類型的服務項目。
  final String? serviceType;

  @override
  ConsumerState<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends ConsumerState<VendorDetailScreen> {
  int _selectedIndex = 0;

  VendorServicesQuery get _query => VendorServicesQuery(
        vendorId: widget.vendorId,
        serviceType: widget.serviceType,
      );

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(vendorServicesProvider(_query));

    return Scaffold(
      body: AsyncValueWidget<List<VendorServiceItem>>(
        value: servicesAsync,
        onRetry: () => ref.invalidate(vendorServicesProvider(_query)),
        data: (services) {
          if (services.isEmpty) {
            return const Center(child: Text('此廠商目前無服務項目'));
          }
          // 確保 index 不超出範圍（服務清單重新載入後可能變短）
          final index = _selectedIndex.clamp(0, services.length - 1);
          return _DetailBody(
            services: services,
            selectedIndex: index,
            onServiceChanged: (i) => setState(() => _selectedIndex = i),
          );
        },
      ),
      bottomNavigationBar: servicesAsync.maybeWhen(
        data: (services) {
          if (services.isEmpty) return null;
          final idx = _selectedIndex.clamp(0, services.length - 1);
          final current = services[idx];
          if (current.formId == null || current.formId == 0) return null;
          return _SubmitBar(
            formId: current.formId!,
            serviceId: current.id,
          );
        },
        orElse: () => null,
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.services,
    required this.selectedIndex,
    required this.onServiceChanged,
  });

  final List<VendorServiceItem> services;
  final int selectedIndex;
  final void Function(int) onServiceChanged;

  @override
  Widget build(BuildContext context) {
    final current = services[selectedIndex];
    final imgUrl = current.imgUrl.isNotEmpty
        ? current.imgUrl
        : services
            .firstWhere((s) => s.imgUrl.isNotEmpty, orElse: () => current)
            .imgUrl;

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: imgUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imgUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    errorWidget: (_, __, ___) => Container(
                        color: Theme.of(context).colorScheme.primaryContainer),
                  )
                : Container(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: const Icon(Icons.store, size: 64),
                  ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.md),
          sliver: SliverList(
            delegate: SliverChildListDelegate(<Widget>[
              Text(current.name, style: AppTypography.headline),
              const SizedBox(height: AppSpacing.sm),

              // 服務切換（同廠商多個服務時顯示）
              if (services.length > 1) ...<Widget>[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < services.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: ChoiceChip(
                            label: Text(services[i].name),
                            selected: i == selectedIndex,
                            onSelected: (_) => onServiceChanged(i),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // 服務說明
              if (current.description.isNotEmpty)
                ExpansionTile(
                  title: const Text('服務介紹'),
                  initiallyExpanded: true,
                  children: <Widget>[
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      child: SimpleHtmlView(html: current.description),
                    ),
                  ],
                ),

              // 評價區塊
              if (current.id > 0)
                ExpansionTile(
                  title: const Text('用戶評價'),
                  children: <Widget>[
                    ServiceReviewsSection(serviceId: current.id),
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

/// 底部固定的「填寫諮詢單」按鈕。
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.formId, required this.serviceId});

  final int formId;

  /// 一併帶入，讓 feedback 能記到正確的 `cms_homepage_service.id`。
  final int serviceId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: FilledButton(
          onPressed: () =>
              context.push(Routes.form(formId, serviceId: serviceId)),
          child: const Text('填寫諮詢單'),
        ),
      ),
    );
  }
}
