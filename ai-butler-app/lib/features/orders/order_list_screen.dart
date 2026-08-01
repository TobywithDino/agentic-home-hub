import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/core/utils/pii_masker.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:ai_butler_app/design_system/components/skeletons.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/logic/order_status_mapper.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/order_providers.dart';
import 'package:intl/intl.dart';

/// 我的諮詢單／我的訂單（Requirement 15）。
class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key});

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inboxAsync = ref.watch(orderInboxProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('訂單紀錄'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Widget>[Tab(text: '我的諮詢單'), Tab(text: '我的訂單')],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(orderInboxProvider.future),
        child: AsyncValueWidget<OrderInbox>(
          value: inboxAsync,
          skeleton: SkeletonList(
              itemCount: 4, itemBuilder: (_) => const ListRowSkeleton()),
          onRetry: () => ref.invalidate(orderInboxProvider),
          data: (inbox) => TabBarView(
            controller: _tabController,
            children: <Widget>[
              _ConsultationList(items: inbox.consultations),
              _OrderList(items: inbox.orders),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsultationList extends StatelessWidget {
  const _ConsultationList({required this.items});

  final List<ConsultationItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('尚無諮詢單'));
    }
    final sorted = List<ConsultationItem>.of(items)
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final item = sorted[index];
        return InkWell(
          onTap: () => context.push('/orders/detail/${item.feedbackNo}'),
          borderRadius: AppRadius.lgAll,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(item.serviceName, style: AppTypography.bodyLarge),
                      Text(item.status, style: AppTypography.caption),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${item.feedbackNo} · ${DateFormat('yyyy/MM/dd HH:mm').format(item.submittedAt)}',
                    style: AppTypography.caption
                        .copyWith(color: context.butler.secondaryText),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.items});

  final List<OrderItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('尚無訂單'));
    }
    final sorted = List<OrderItem>.of(items)
      ..sort((a, b) => b.orderTime.compareTo(a.orderTime));

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final order = sorted[index];
        final statusView =
            OrderStatusMapper.map(order.orderType, order.orderStatus);
        return InkWell(
          onTap: () => context.push('/orders/detail/${order.orderNo}'),
          borderRadius: AppRadius.lgAll,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(statusView.categoryName,
                          style: AppTypography.bodyLarge),
                      _StatusChip(view: statusView),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${order.orderNo} · ${DateFormat('yyyy/MM/dd HH:mm').format(order.orderTime)}',
                    style: AppTypography.caption
                        .copyWith(color: context.butler.secondaryText),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '聯絡人：${PiiMasker.maskMobile(order.contactMobile)}',
                    style: AppTypography.caption
                        .copyWith(color: context.butler.secondaryText),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.view});

  final OrderStatusView view;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (view.group) {
      OrderStatusGroup.completed => (
          context.butler.successSurface,
          context.butler.success
        ),
      OrderStatusGroup.cancelled => (
          context.butler.errorSurface,
          context.butler.error
        ),
      OrderStatusGroup.inProgress => (
          context.butler.warningSurface,
          context.butler.warning
        ),
    };
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.xlAll),
      child: Text(view.statusLabel,
          style: AppTypography.caption.copyWith(color: fg)),
    );
  }
}
