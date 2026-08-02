import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:ai_butler_app/design_system/components/skeletons.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/logic/order_status_mapper.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/models/order_update.dart';
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
    final updates = ref.watch(orderUpdatesProvider);

    // 使用者已經看到這一頁，通知就算讀過了；紅點隨之消失。
    if (updates.any((u) => !u.isRead)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(orderUpdatesProvider.notifier).markAllRead();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('訂單紀錄'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const <Widget>[Tab(text: '我的諮詢單'), Tab(text: '我的訂單')],
        ),
      ),
      body: AsyncValueWidget<OrderInbox>(
        value: inboxAsync,
        skeleton: SkeletonList(
            itemCount: 4, itemBuilder: (_) => const ListRowSkeleton()),
        onRetry: () => ref.invalidate(orderInboxProvider),
        data: (inbox) => Column(
          children: <Widget>[
            if (updates.isNotEmpty) _UpdatesBanner(updates: updates),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  RefreshIndicator(
                    onRefresh: () =>
                        ref.read(orderInboxProvider.notifier).refreshNow(),
                    child: _ConsultationList(items: inbox.consultations),
                  ),
                  RefreshIndicator(
                    onRefresh: () =>
                        ref.read(orderInboxProvider.notifier).refreshNow(),
                    child: _OrderList(items: inbox.orders),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 最近的後端變更摘要，讓使用者知道「剛剛有什麼被更新」。
class _UpdatesBanner extends ConsumerWidget {
  const _UpdatesBanner({required this.updates});

  final List<OrderUpdate> updates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = updates.take(3).toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.butler.surfaceVariant,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.notifications_active_outlined,
                  size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child:
                    Text('最近更新（${updates.length}）', style: AppTypography.label),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(orderUpdatesProvider.notifier).clear(),
                child: const Text('清除'),
              ),
            ],
          ),
          for (final update in recent)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '· ${update.title}：${update.description}',
                style: AppTypography.caption
                    .copyWith(color: context.butler.secondaryText),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const <Widget>[
          SizedBox(height: 120),
          Center(child: Text('尚無諮詢單')),
        ],
      );
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const <Widget>[
          SizedBox(height: 120),
          Center(child: Text('尚無訂單')),
        ],
      );
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
                      Expanded(
                        child: Text(order.serviceName,
                            style: AppTypography.bodyLarge),
                      ),
                      _StatusChip(view: statusView),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${order.orderNo} · ${DateFormat('yyyy/MM/dd HH:mm').format(order.orderTime)}',
                    style: AppTypography.caption
                        .copyWith(color: context.butler.secondaryText),
                  ),
                  // 品項超過一筆時提示還有幾項，詳細內容在詳情頁展開
                  if (order.lineItems.length > 1)
                    Text(
                      '共 ${order.lineItems.length} 個品項',
                      style: AppTypography.caption
                          .copyWith(color: context.butler.secondaryText),
                    ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: <Widget>[
                      Text(
                        'NT\$${order.finalAmount.toStringAsFixed(0)}',
                        style: AppTypography.body,
                      ),
                      // 待評價只用一個實色小圓點提示，實際填寫在詳情頁進行，
                      // 避免清單上出現可點按鈕跟卡片本身的點擊行為打架。
                      if (order.canReview) ...<Widget>[
                        const SizedBox(width: AppSpacing.xs),
                        const _PendingReviewDot(),
                      ],
                    ],
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

/// 待評價提示點。
///
/// 只做視覺提示、不可點；點整張卡片會進詳情頁，那裡才是撰寫評價的入口。
class _PendingReviewDot extends StatelessWidget {
  const _PendingReviewDot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '尚未評價',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      ),
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
