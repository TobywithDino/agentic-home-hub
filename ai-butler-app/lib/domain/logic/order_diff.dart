import 'package:ai_butler_app/domain/logic/order_status_mapper.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/models/order_update.dart';

/// 比對兩份 [OrderInbox]，算出使用者需要被通知的變更。
///
/// 純函式、無副作用，方便單獨測試。刻意只回報「後端／商家造成的變化」：
/// 使用者自己的動作（例如剛送出諮詢單、剛送出評價）不該再通知自己，
/// 否則每次操作都會跳一則沒有資訊量的訊息。
class OrderDiff {
  const OrderDiff._();

  static List<OrderUpdate> diff({
    required OrderInbox previous,
    required OrderInbox next,
  }) {
    final updates = <OrderUpdate>[];

    final previousOrders = <int, OrderItem>{
      for (final order in previous.orders) order.recordId: order,
    };

    for (final order in next.orders) {
      final before = previousOrders[order.recordId];

      // 新訂單：商家把諮詢轉成訂單，使用者需要知道。
      if (before == null) {
        updates.add(OrderUpdate(
          id: 'order-new-${order.recordId}',
          kind: OrderUpdateKind.newOrder,
          title: '新訂單成立',
          description: '${order.serviceName}（${order.orderNo}）已建立，'
              '狀態：${_statusLabel(order)}',
          occurredAt: DateTime.now(),
          orderNo: order.orderNo,
        ));
        continue;
      }

      if (before.orderStatus != order.orderStatus) {
        updates.add(OrderUpdate(
          id: 'order-status-${order.recordId}-${order.orderStatus}',
          kind: OrderUpdateKind.statusChanged,
          title: '訂單狀態更新',
          description: '${order.serviceName}（${order.orderNo}）'
              '${_statusLabel(before)} → ${_statusLabel(order)}',
          occurredAt: DateTime.now(),
          orderNo: order.orderNo,
        ));
      }

      // 報價單號從無到有 = 商家報價完成。
      if (before.quoteNo.isEmpty && order.quoteNo.isNotEmpty) {
        updates.add(OrderUpdate(
          id: 'order-quote-${order.recordId}-${order.quoteNo}',
          kind: OrderUpdateKind.quoted,
          title: '商家已報價',
          description: '${order.serviceName} 報價單號 ${order.quoteNo}，'
              '金額 NT\$${_amount(order.finalAmount)}',
          occurredAt: DateTime.now(),
          orderNo: order.orderNo,
        ));
      } else if (before.finalAmount != order.finalAmount) {
        // 已報價的金額調整單獨提示，避免與報價通知重複。
        updates.add(OrderUpdate(
          id: 'order-amount-${order.recordId}-${order.finalAmount}',
          kind: OrderUpdateKind.amountChanged,
          title: '訂單金額更新',
          description: '${order.serviceName}（${order.orderNo}）'
              'NT\$${_amount(before.finalAmount)} → '
              'NT\$${_amount(order.finalAmount)}',
          occurredAt: DateTime.now(),
          orderNo: order.orderNo,
        ));
      }
    }

    // 諮詢單：只在處理狀態變動時通知（新增是使用者自己送出的，不通知）。
    final previousConsultations = <String, ConsultationItem>{
      for (final item in previous.consultations) item.feedbackNo: item,
    };
    for (final item in next.consultations) {
      final before = previousConsultations[item.feedbackNo];
      if (before == null) continue;
      if (before.status != item.status) {
        updates.add(OrderUpdate(
          id: 'feedback-status-${item.feedbackNo}-${item.status}',
          kind: OrderUpdateKind.consultationProgress,
          title: '諮詢單進度更新',
          description: '${item.feedbackNo} ${before.status} → ${item.status}',
          occurredAt: DateTime.now(),
          orderNo: item.feedbackNo,
        ));
      }
    }

    return updates;
  }

  static String _statusLabel(OrderItem order) =>
      OrderStatusMapper.map(order.orderType, order.orderStatus).statusLabel;

  static String _amount(num value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}
