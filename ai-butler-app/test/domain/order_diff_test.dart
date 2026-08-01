import 'package:flutter_test/flutter_test.dart';

import 'package:ai_butler_app/domain/logic/order_diff.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/models/order_update.dart';

OrderItem _order({
  int recordId = 1,
  String orderNo = 'ORD001',
  String orderStatus = '12',
  num finalAmount = 300,
  String quoteNo = '',
  String serviceName = '水電修繕',
}) {
  return OrderItem(
    recordId: recordId,
    orderNo: orderNo,
    orderType: '01',
    orderStatus: orderStatus,
    finalAmount: finalAmount,
    orderTime: DateTime(2026, 8, 1),
    serviceName: serviceName,
    quoteNo: quoteNo,
  );
}

ConsultationItem _consultation({
  String feedbackNo = 'FB001',
  String status = '未處理',
}) {
  return ConsultationItem(
    feedbackNo: feedbackNo,
    serviceName: '服務諮詢',
    submittedAt: DateTime(2026, 8, 1),
    status: status,
  );
}

void main() {
  group('OrderDiff', () {
    test('內容相同時沒有通知', () {
      final inbox = OrderInbox(orders: <OrderItem>[_order()]);

      final updates = OrderDiff.diff(previous: inbox, next: inbox);

      expect(updates, isEmpty);
    });

    test('新訂單會產生 newOrder 通知', () {
      final updates = OrderDiff.diff(
        previous: const OrderInbox(),
        next: OrderInbox(orders: <OrderItem>[_order(recordId: 7)]),
      );

      expect(updates, hasLength(1));
      expect(updates.single.kind, OrderUpdateKind.newOrder);
      expect(updates.single.orderNo, 'ORD001');
    });

    test('訂單狀態變動會帶出前後狀態文字', () {
      final updates = OrderDiff.diff(
        previous: OrderInbox(orders: <OrderItem>[_order(orderStatus: '12')]),
        next: OrderInbox(orders: <OrderItem>[_order(orderStatus: '80')]),
      );

      expect(updates, hasLength(1));
      expect(updates.single.kind, OrderUpdateKind.statusChanged);
      expect(updates.single.description, contains('已完成'));
    });

    test('報價單號從無到有視為商家已報價', () {
      final updates = OrderDiff.diff(
        previous: OrderInbox(orders: <OrderItem>[_order()]),
        next: OrderInbox(
          orders: <OrderItem>[_order(quoteNo: 'QT001', finalAmount: 1200)],
        ),
      );

      final quoted =
          updates.where((u) => u.kind == OrderUpdateKind.quoted).toList();
      expect(quoted, hasLength(1));
      expect(quoted.single.description, contains('QT001'));
      // 報價與金額變動不重複通知
      expect(
        updates.where((u) => u.kind == OrderUpdateKind.amountChanged),
        isEmpty,
      );
    });

    test('已報價後的金額調整單獨通知', () {
      final updates = OrderDiff.diff(
        previous: OrderInbox(
            orders: <OrderItem>[_order(quoteNo: 'QT001', finalAmount: 1200)]),
        next: OrderInbox(
            orders: <OrderItem>[_order(quoteNo: 'QT001', finalAmount: 1500)]),
      );

      expect(updates, hasLength(1));
      expect(updates.single.kind, OrderUpdateKind.amountChanged);
      expect(updates.single.description, contains('1500'));
    });

    test('新增諮詢單不通知（是使用者自己送出的）', () {
      final updates = OrderDiff.diff(
        previous: const OrderInbox(),
        next: OrderInbox(consultations: <ConsultationItem>[_consultation()]),
      );

      expect(updates, isEmpty);
    });

    test('諮詢單處理進度變動會通知', () {
      final updates = OrderDiff.diff(
        previous:
            OrderInbox(consultations: <ConsultationItem>[_consultation()]),
        next: OrderInbox(
          consultations: <ConsultationItem>[_consultation(status: '處理中')],
        ),
      );

      expect(updates, hasLength(1));
      expect(updates.single.kind, OrderUpdateKind.consultationProgress);
    });

    test('同一筆變更的 id 穩定，可用於去重', () {
      final previous = OrderInbox(orders: <OrderItem>[_order(orderStatus: '12')]);
      final next = OrderInbox(orders: <OrderItem>[_order(orderStatus: '80')]);

      final first = OrderDiff.diff(previous: previous, next: next);
      final second = OrderDiff.diff(previous: previous, next: next);

      expect(first.single.id, second.single.id);
    });
  });
}
