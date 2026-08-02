import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:ai_butler_app/design_system/components/simple_html_view.dart';
import 'package:ai_butler_app/features/tour/tour_anchors.dart';
import 'package:ai_butler_app/features/tour/tour_leg_host.dart';
import 'package:ai_butler_app/features/tour/tour_plan.dart';
import 'package:ai_butler_app/features/tour/tour_session.dart';
import 'package:ai_butler_app/features/vendor/service_reviews_section.dart';
import 'package:ai_butler_app/providers/butler_draft_provider.dart';
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
          // 按鈕渲染完才有錨點可圈；沒有 formId 時這個 bar 不存在，
          // 導覽也就走不下去（上面已 return null）。
          _maybeStartVendorDetailTour(context, ref, current);
          return _SubmitBar(
            formId: current.formId!,
            serviceId: current.id,
            anchorKey:
                ref.read(tourAnchorsProvider).of(TourAnchorIds.vendorDetailSubmit),
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

/// 啟動導覽第三段：圈出「填寫諮詢單」，並交棒給表單頁。
///
/// 這是跨畫面導覽與填單頁導覽的接縫。填單頁那一段沒有放進 [TourLeg]，
/// 因為它要等表單載入、預填算完才知道有哪些題目 —— 那些邏輯已經在
/// `FormScreen` 裡了。所以這裡改成設定 `pendingButlerDraftProvider`
/// （帶 `startTour: true`）並結束 session，由表單頁自己接手。
void _maybeStartVendorDetailTour(
  BuildContext context,
  WidgetRef ref,
  VendorServiceItem current,
) {
  final session = ref.read(tourSessionProvider);
  if (session == null || session.leg != TourLeg.vendorDetail) return;

  final card = session.card;
  final anchors = ref.read(tourAnchorsProvider);

  maybeStartTourLeg(
    ref: ref,
    context: context,
    leg: TourLeg.vendorDetail,
    buildSteps: () => TourPlan.vendorDetailLeg(
      submitAnchor: anchors.of(TourAnchorIds.vendorDetailSubmit),
      onTap: () {
        tourLog('交棒給填單頁 form_id=${card.formId}');
        ref
            .read(pendingButlerDraftProvider.notifier)
            .handOff(card, startTour: true);
        ref.read(tourSessionProvider.notifier).finish();
        // 用草稿裡的 formId/serviceId 而不是畫面當前選中的服務項目：
        // 使用者可能在這頁按了 ChoiceChip 切到別的服務，
        // 但預填的答案是對應原本那張表單的。
        context.push(Routes.form(card.formId, serviceId: card.serviceId));
      },
    ),
  );
}

/// 底部固定的「填寫諮詢單」按鈕。
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.formId,
    required this.serviceId,
    this.anchorKey,
  });

  final int formId;

  /// 一併帶入，讓 feedback 能記到正確的 `cms_homepage_service.id`。
  final int serviceId;

  /// 導覽錨點。
  final GlobalKey? anchorKey;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: FilledButton(
          key: anchorKey,
          onPressed: () =>
              context.push(Routes.form(formId, serviceId: serviceId)),
          child: const Text('填寫諮詢單'),
        ),
      ),
    );
  }
}
