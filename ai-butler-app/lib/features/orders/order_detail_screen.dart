import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/domain/logic/order_status_mapper.dart';
import 'package:ai_butler_app/providers/order_providers.dart';

/// 訂單／諮詢單詳情（Requirement 15.8-9）。
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderNo});

  final String orderNo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(orderInboxProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('訂單詳情')),
      body: inboxAsync.when(
        data: (inbox) {
          final order = inbox.orders.where((o) => o.orderNo == orderNo).toList();
          if (order.isEmpty) {
            return const Center(child: Text('找不到此訂單'));
          }
          final item = order.first;
          final statusView = OrderStatusMapper.map(item.orderType, item.orderStatus);
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.orderNo, style: AppTypography.title),
                const SizedBox(height: AppSpacing.sm),
                Text('類別：${statusView.categoryName}'),
                Text('狀態：${statusView.statusLabel}'),
                Text('金額：NT\$${item.finalAmount}'),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('載入失敗：$error')),
      ),
    );
  }
}
