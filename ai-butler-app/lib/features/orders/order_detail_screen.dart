import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/logic/order_status_mapper.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/features/orders/review_screen.dart';
import 'package:ai_butler_app/providers/order_providers.dart';

/// 訂單／諮詢單詳情（Requirement 15.8-9）。
///
/// 訂單品項依 `mms_order_record.order_items` 的 JSON 結構逐項呈現
/// （品項名稱、單價/數量、attribute 補充說明、小計），最後對總額。
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderNo});

  final String orderNo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(orderInboxProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('訂單詳情')),
      body: AsyncValueWidget<OrderInbox>(
        value: inboxAsync,
        onRetry: () => ref.invalidate(orderInboxProvider),
        data: (inbox) {
          final matches =
              inbox.orders.where((o) => o.orderNo == orderNo).toList();
          if (matches.isEmpty) {
            // 可能是諮詢單編號（feedback_no），退化成顯示諮詢單資訊。
            final consultation = inbox.consultations
                .where((c) => c.feedbackNo == orderNo)
                .toList();
            if (consultation.isNotEmpty) {
              return _ConsultationDetail(item: consultation.first);
            }
            return const Center(child: Text('找不到此訂單'));
          }
          return _OrderDetail(order: matches.first);
        },
      ),
    );
  }
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({required this.order});

  final OrderItem order;

  @override
  Widget build(BuildContext context) {
    final statusView =
        OrderStatusMapper.map(order.orderType, order.orderStatus);
    final dateFormat = DateFormat('yyyy/MM/dd HH:mm');

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        // === 狀態摘要 ===
        _Section(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(statusView.categoryName, style: AppTypography.title),
                _StatusBadge(view: statusView),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (order.vendorName.isNotEmpty)
              _KeyValue(label: '服務商', value: order.vendorName),
            _KeyValue(label: '訂單編號', value: order.orderNo),
            _KeyValue(label: '成立時間', value: dateFormat.format(order.orderTime)),
            if (order.depositTime != null)
              _KeyValue(
                  label: '訂金支付', value: dateFormat.format(order.depositTime!)),
            if (order.serviceTime != null)
              _KeyValue(
                  label: '服務時間', value: dateFormat.format(order.serviceTime!)),
            if (order.completeTime != null)
              _KeyValue(
                  label: '完成時間', value: dateFormat.format(order.completeTime!)),
            if (order.cancelTime != null)
              _KeyValue(
                  label: '取消時間', value: dateFormat.format(order.cancelTime!)),
            if (order.quoteNo.isNotEmpty)
              _KeyValue(label: '報價單號', value: order.quoteNo),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // === 金額 ===
        _Section(
          children: <Widget>[
            const Text('金額', style: AppTypography.title),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'NT\$${_fmt(order.finalAmount)}',
              style: AppTypography.bodyLarge
                  .copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),

        if (order.remark.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _Section(
            children: <Widget>[
              const Text('備註', style: AppTypography.title),
              const SizedBox(height: AppSpacing.xs),
              Text(order.remark, style: AppTypography.body),
            ],
          ),
        ],

        // === 原始諮詢內容（vendor_data.content）===
        if (order.vendorDataContent.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _Section(
            children: <Widget>[
              const Text('內容', style: AppTypography.title),
              const SizedBox(height: AppSpacing.xs),
              Text(order.vendorDataContent, style: AppTypography.body),
            ],
          ),
        ],

        // === 評價 ===
        const SizedBox(height: AppSpacing.md),
        _Section(
          children: <Widget>[
            const Text('評價', style: AppTypography.title),
            const SizedBox(height: AppSpacing.xs),
            if (order.review != null) ...<Widget>[
              Row(
                children: <Widget>[
                  for (int i = 0; i < 5; i++)
                    Icon(
                      i < order.review!.overallRating
                          ? Icons.star
                          : Icons.star_border,
                      color: Colors.amber,
                      size: 18,
                    ),
                ],
              ),
              if (order.review!.reviewContent.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                Text(order.review!.reviewContent, style: AppTypography.body),
              ],
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton(
                onPressed: () => _openReview(context),
                child: const Text('修改評價'),
              ),
            ] else if (order.canReview) ...<Widget>[
              Text(
                '這筆訂單已完成，分享您的使用心得吧',
                style: AppTypography.body
                    .copyWith(color: context.butler.secondaryText),
              ),
              const SizedBox(height: AppSpacing.xs),
              FilledButton(
                onPressed: () => _openReview(context),
                child: const Text('撰寫評價'),
              ),
            ] else
              Text(
                order.commentStatus == '00' ? '此訂單無須評價' : '訂單完成後即可評價',
                style: AppTypography.body
                    .copyWith(color: context.butler.secondaryText),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  void _openReview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReviewScreen(order: order)),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: AppTypography.caption
                  .copyWith(color: context.butler.secondaryText),
            ),
          ),
          Expanded(child: Text(value, style: AppTypography.body)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: context.butler.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.view});

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

class _ConsultationDetail extends StatelessWidget {
  const _ConsultationDetail({required this.item});

  final ConsultationItem item;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: <Widget>[
        _Section(
          children: <Widget>[
            const Text('諮詢單', style: AppTypography.title),
            const SizedBox(height: AppSpacing.xs),
            _KeyValue(label: '單號', value: item.feedbackNo),
            _KeyValue(label: '服務', value: item.serviceName),
            _KeyValue(label: '狀態', value: item.status),
            _KeyValue(
              label: '送出時間',
              value: DateFormat('yyyy/MM/dd HH:mm').format(item.submittedAt),
            ),
          ],
        ),
      ],
    );
  }
}

String _fmt(num value) {
  if (value == value.roundToDouble()) {
    return NumberFormat('#,###').format(value.toInt());
  }
  return NumberFormat('#,##0.##').format(value);
}
