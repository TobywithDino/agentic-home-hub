import 'package:flutter/foundation.dart';

import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/core/utils/api_time.dart';
import 'package:ai_butler_app/data/remote/api_client.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 真實後端的訂單查詢實作。
///
/// BFF 端點 `GET /app-api/users/{id}/orders-overview` 一次回傳
/// feedbacks + orders，本實作將其拆為 ConsultationItem 與 OrderItem。
///
/// 解析一律走容錯路線（[_asString] / [_asInt] / [_asMap]）：後端欄位型別
/// 與預期不同時只讓該筆退化成預設值，不讓整頁變成錯誤畫面。
class HttpOrderRepository implements OrderRepository {
  HttpOrderRepository(this._client, {required this.getAccountId});

  final ApiClient _client;
  final String Function() getAccountId;

  static const String _endpoint = 'GET /app-api/users/{id}/orders-overview';

  @override
  Future<OrderInbox> fetchInbox() async {
    final accountId = getAccountId();
    if (accountId.isEmpty) {
      // 未登入或 session 尚未還原：回傳空清單而非錯誤畫面。
      return OrderInbox.empty;
    }

    final response = await _client.get<dynamic>(
      ApiEndpoints.ordersOverview(accountId),
    );

    final body = _asMap(response.data);
    if (body == null) {
      throw const ServerError(
        message: '訂單資料格式不符，請稍後再試',
        endpoint: _endpoint,
      );
    }

    try {
      return OrderInbox(
        consultations: _parseConsultations(body['feedbacks']),
        orders: _parseOrders(body['orders']),
      );
    } catch (error, stackTrace) {
      // 解析失敗要能一眼看出是「回應欄位跟預期不同」而不是 UI bug。
      debugPrint('[orders-overview] 解析失敗: $error\n$stackTrace');
      throw ServerError(
        message: '訂單資料解析失敗：$error',
        endpoint: _endpoint,
        cause: error,
      );
    }
  }

  List<ConsultationItem> _parseConsultations(dynamic raw) {
    final list = _asList(raw);
    final result = <ConsultationItem>[];
    for (final entry in list) {
      final map = _asMap(entry);
      if (map == null) continue;
      result.add(ConsultationItem(
        feedbackNo: _asString(map['feedback_no']),
        serviceName: _consultationTitle(map),
        submittedAt: _asDate(map['cre_time']),
        status: _feedbackStatusText(_asString(map['status'], fallback: '0')),
      ));
    }
    return result;
  }

  List<OrderItem> _parseOrders(dynamic raw) {
    final list = _asList(raw);
    final result = <OrderItem>[];
    for (final entry in list) {
      final map = _asMap(entry);
      if (map == null) continue;
      final lineItems = _parseLineItems(map['order_items']);
      result.add(OrderItem(
        recordId: _asInt(map['record_id']),
        serviceId: _asInt(map['service_id']),
        serviceVendorId: _asInt(map['service_vendor_id']),
        orderNo: _asString(map['order_no']),
        orderType: _asString(map['order_type']),
        orderStatus: _asString(map['order_status']),
        finalAmount: _asNum(map['final_amount']),
        orderTime: _asDate(map['order_time']),
        serviceName: lineItems.isNotEmpty ? lineItems.first.itemName : '服務訂單',
        contactMobile: _asString(map['contact_mobile']),
        commentStatus: _asString(map['comment_status'], fallback: '01'),
        review: _parseReview(map['review']),
        lineItems: lineItems,
        lineItemsTotal:
            _optionalNum(_asMap(map['order_items'])?['totalAmount']),
        depositAmount: _asNum(map['deposit_amount']),
        quoteNo: _asString(map['quote_no']),
        remark: _asString(map['remark']),
        depositTime: _optionalDate(map['deposit_time']),
        serviceTime: _optionalDate(map['service_time']),
        completeTime: _optionalDate(map['complete_time']),
        cancelTime: _optionalDate(map['cancel_time']),
      ));
    }
    return result;
  }

  /// 解析 `order_items` JSONB。
  ///
  /// 容忍三種形狀：`{"orderItems": [...]}`、直接是陣列、或 null。
  List<OrderLineItem> _parseLineItems(dynamic raw) {
    List<dynamic> items = const <dynamic>[];
    final asMap = _asMap(raw);
    if (asMap != null) {
      items = _asList(asMap['orderItems']);
    } else if (raw is List) {
      items = raw;
    }

    final result = <OrderLineItem>[];
    for (final entry in items) {
      final map = _asMap(entry);
      if (map == null) continue;
      result.add(OrderLineItem(
        itemName: _asString(map['itemName'], fallback: '未命名項目'),
        quantity: _optionalNum(map['quantity']),
        unit: _asString(map['unit']),
        unitPrice: _asNum(map['unitPrice']),
        itemAmount: _asNum(map['itemAmount']),
        attributes: _asList(map['attribute'])
            .map((a) => _asString(a))
            .where((a) => a.isNotEmpty)
            .toList(),
      ));
    }
    return result;
  }

  String _consultationTitle(Map<String, dynamic> feedback) {
    final name = _asString(feedback['contact_name']);
    return name.isNotEmpty ? name : '服務諮詢';
  }

  OrderReview? _parseReview(dynamic raw) {
    final map = _asMap(raw);
    if (map == null) return null;
    try {
      return OrderReview.fromJson(map);
    } catch (error) {
      debugPrint('[orders-overview] 評價解析失敗，忽略此筆: $error');
      return null;
    }
  }

  String _feedbackStatusText(String code) {
    return switch (code) {
      '0' => '未處理',
      '1' => '處理中',
      '2' => '已完成',
      _ => '未知',
    };
  }

  // === 容錯轉型工具 ===

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return null;
  }

  static List<dynamic> _asList(dynamic value) =>
      value is List ? value : const <dynamic>[];

  static String _asString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) return value.isEmpty ? fallback : value;
    return value.toString();
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static num _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime _asDate(dynamic value) => ApiTime.parseOr(value);

  /// 可為 null 的時間欄位（deposit_time / complete_time 等常為 null）。
  static DateTime? _optionalDate(dynamic value) => ApiTime.tryParse(value);

  /// 可為 null 的數值欄位（quantity / totalAmount 常為 null）。
  static num? _optionalNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }
}
