import 'package:flutter/foundation.dart';

/// 訂單／諮詢單的變更種類。
enum OrderUpdateKind {
  /// 新增了一筆訂單（通常是商家把諮詢轉成訂單）。
  newOrder,

  /// 訂單狀態變動。
  statusChanged,

  /// 商家完成報價。
  quoted,

  /// 金額變動。
  amountChanged,

  /// 諮詢單處理進度變動。
  consultationProgress,
}

/// 一則「資料庫有更新」的通知。
///
/// 由 `OrderDiff` 比對前後兩份 `OrderInbox` 產生，不是後端推播的產物——
/// 目前平台沒有推播管道，靠前景輪詢比對達成同等效果。
@immutable
class OrderUpdate {
  const OrderUpdate({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.occurredAt,
    this.orderNo = '',
    this.isRead = false,
  });

  /// 去重用的穩定識別碼：同一筆變更重複偵測到時不會重複通知。
  final String id;

  final OrderUpdateKind kind;
  final String title;
  final String description;
  final DateTime occurredAt;

  /// 對應的訂單編號（諮詢單則是 feedback_no），可用於導向詳情頁。
  final String orderNo;

  final bool isRead;

  OrderUpdate copyWith({bool? isRead}) => OrderUpdate(
        id: id,
        kind: kind,
        title: title,
        description: description,
        occurredAt: occurredAt,
        orderNo: orderNo,
        isRead: isRead ?? this.isRead,
      );
}
