import 'package:flutter/foundation.dart';

/// 訂單狀態顯示視圖（Requirement 15.5-7）。
@immutable
class OrderStatusView {
  const OrderStatusView({
    required this.categoryName,
    required this.statusLabel,
    required this.group,
  });

  /// order_type 對應的類別名稱（例如「服務訂單」）。
  final String categoryName;

  /// order_status 對應的顯示文字（例如「已完成」）。
  final String statusLabel;

  /// UI 用的分組，決定顏色與篩選（Requirement 15.13）。
  final OrderStatusGroup group;
}

enum OrderStatusGroup { inProgress, completed, cancelled }

/// 依 requirements.md 附錄 B 建表的訂單狀態對照（Requirement 15.5-7）。
///
/// 純函式，由屬性測試 P8 守住「對任意輸入皆有回傳、不拋例外」與
/// 「表列組合結果與附錄 B 一致」兩個性質。
class OrderStatusMapper {
  const OrderStatusMapper._();

  static const Map<String, String> _categoryNames = <String, String>{
    '01': '服務訂單',
    '02': '訂位',
    '03': '預約',
    '04': '其他',
    '05': '商品訂單',
    '06': '訂餐',
  };

  /// order_type '01' 專屬狀態流程。
  static const Map<String, ({String label, OrderStatusGroup group})> _type01 =
      <String, ({String label, OrderStatusGroup group})>{
    '11': (label: '待訂金支付', group: OrderStatusGroup.inProgress),
    '12': (label: '已支付訂金，待報價', group: OrderStatusGroup.inProgress),
    '13': (label: '已報價，待客戶同意', group: OrderStatusGroup.inProgress),
    '14': (label: '客戶已同意報價', group: OrderStatusGroup.inProgress),
    '15': (label: '已驗收，待尾款支付', group: OrderStatusGroup.inProgress),
    '80': (label: '已完成', group: OrderStatusGroup.completed),
    '90': (label: '已取消', group: OrderStatusGroup.cancelled),
    '98': (label: '部分退款', group: OrderStatusGroup.completed),
    '99': (label: '已退款', group: OrderStatusGroup.cancelled),
  };

  /// order_type '02' 專屬狀態流程。
  static const Map<String, ({String label, OrderStatusGroup group})> _type02 =
      <String, ({String label, OrderStatusGroup group})>{
    '01': (label: '待付款', group: OrderStatusGroup.inProgress),
    '02': (label: '待確認', group: OrderStatusGroup.inProgress),
    '03': (label: '已確認', group: OrderStatusGroup.inProgress),
    '04': (label: '進行中', group: OrderStatusGroup.inProgress),
    '70': (label: '已完成（預定時間後 3 小時）', group: OrderStatusGroup.completed),
    '80': (label: '已完成（7 天後核銷）', group: OrderStatusGroup.completed),
    '90': (label: '已取消', group: OrderStatusGroup.cancelled),
    '99': (label: '已退款', group: OrderStatusGroup.cancelled),
  };

  /// order_type '03'/'04'/'05'/'06' 共用狀態流程。
  static const Map<String, ({String label, OrderStatusGroup group})>
      _defaultFlow = <String, ({String label, OrderStatusGroup group})>{
    '01': (label: '待付款', group: OrderStatusGroup.inProgress),
    '02': (label: '待確認', group: OrderStatusGroup.inProgress),
    '03': (label: '已確認', group: OrderStatusGroup.inProgress),
    '04': (label: '進行中', group: OrderStatusGroup.inProgress),
    '80': (label: '已完成', group: OrderStatusGroup.completed),
    '90': (label: '已取消', group: OrderStatusGroup.cancelled),
    '99': (label: '已退款', group: OrderStatusGroup.cancelled),
  };

  static Map<String, ({String label, OrderStatusGroup group})> _flowFor(
    String orderType,
  ) {
    return switch (orderType) {
      '01' => _type01,
      '02' => _type02,
      '03' || '04' || '05' || '06' => _defaultFlow,
      _ => const <String, ({String label, OrderStatusGroup group})>{},
    };
  }

  /// 對任意 (orderType, orderStatus) 皆回傳非 null 結果，不拋例外
  /// （Requirement 15.6-7）。
  static OrderStatusView map(String orderType, String orderStatus) {
    final categoryName = _categoryNames[orderType] ?? '其他服務';
    final flow = _flowFor(orderType);
    final entry = flow[orderStatus];

    if (entry == null) {
      // 未知狀態碼：安全預設為「處理中」+ 中性分組，不可讓 App 崩潰。
      // 呼叫端（Repository 層）負責把原始狀態碼寫入偵錯日誌。
      return OrderStatusView(
        categoryName: categoryName,
        statusLabel: '處理中',
        group: OrderStatusGroup.inProgress,
      );
    }

    return OrderStatusView(
      categoryName: categoryName,
      statusLabel: entry.label,
      group: entry.group,
    );
  }

  /// 供偵錯日誌使用：判斷這組狀態碼是否為附錄 B 已知組合。
  static bool isKnownCombination(String orderType, String orderStatus) {
    final flow = _flowFor(orderType);
    return flow.containsKey(orderStatus);
  }
}
