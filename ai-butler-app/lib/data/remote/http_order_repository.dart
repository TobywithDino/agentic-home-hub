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
      final rawFeedbacks = _asList(body['feedbacks']);

      // 取得表單名稱作為服務名稱——失敗不影響主流程，只是名稱 fallback。
      Map<int, String> serviceNames;
      try {
        serviceNames = await _fetchServiceNames(rawFeedbacks);
      } catch (_) {
        serviceNames = const <int, String>{};
      }

      return OrderInbox(
        consultations: _parseConsultations(rawFeedbacks, serviceNames),
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

  List<ConsultationItem> _parseConsultations(
    List<dynamic> raw,
    Map<int, String> serviceNames,
  ) {
    final result = <ConsultationItem>[];
    for (final entry in raw) {
      final map = _asMap(entry);
      if (map == null) continue;
      final serviceId = _asInt(map['service_id']);
      result.add(ConsultationItem(
        feedbackNo: _asString(map['feedback_no']),
        serviceName: serviceNames[serviceId] ?? '服務諮詢',
        submittedAt: _asDate(map['cre_time']),
        status: _feedbackStatusText(_asString(map['status'], fallback: '0')),
        feedbackContent: _parseFeedbackContent(map['feedback_content']),
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
        vendorName: _asString(map['vendor_name']),
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
        vendorDataContent: _parseVendorDataContent(map['vendor_data']),
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

  /// 批次呼叫 `/app-api/forms/{form_id}/full` 取得表單名稱作為服務名稱。
  ///
  /// feedback 一定有 `form_id`（建立時必填），用它去查表單名稱比
  /// `/services/{id}/form/full` 可靠（後者在 `form_id` 為 NULL 時會 404）。
  Future<Map<int, String>> _fetchServiceNames(List<dynamic> feedbacks) async {
    final formIds = <int>{};
    final serviceIdToFormId = <int, int>{};
    for (final entry in feedbacks) {
      final map = _asMap(entry);
      if (map == null) continue;
      final sid = _asInt(map['service_id']);
      final fid = _asInt(map['form_id']);
      if (sid > 0 && fid > 0) {
        formIds.add(fid);
        serviceIdToFormId[sid] = fid;
      }
    }

    // form_id → form name
    final formNameCache = <int, String>{};
    for (final fid in formIds) {
      try {
        final resp = await _client.get<dynamic>(
          '/app-api/forms/$fid/full',
        );
        final data = _asMap(resp.data);
        final form = _asMap(data?['form']);
        final name = _asString(form?['name']);
        if (name.isNotEmpty) {
          formNameCache[fid] = name;
        }
      } catch (_) {
        // 略過
      }
    }

    // service_id → form name
    final result = <int, String>{};
    for (final entry in serviceIdToFormId.entries) {
      final name = formNameCache[entry.value];
      if (name != null) {
        result[entry.key] = name;
      }
    }
    return result;
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

  /// 從 `vendor_data` JSONB 取出 `content` 欄位（接單時打包的可讀多行文字）。
  String _parseVendorDataContent(dynamic raw) {
    final map = _asMap(raw);
    if (map == null) return '';
    return _asString(map['content']);
  }

  /// 從 `feedback_content` JSONB 解析出可讀文字。
  ///
  /// 新版格式 `{answers: [...], form_id}` 會把每個答案的 `value` 串接；
  /// 舊版格式（直接是字串）直接回傳；其餘格式把最外層 key-value 展平。
  String _parseFeedbackContent(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    final map = _asMap(raw);
    if (map == null) return '';

    // 新版格式：{ answers: [...], form_id }
    final answers = _asList(map['answers']);
    if (answers.isNotEmpty) {
      final lines = <String>[];
      for (final ans in answers) {
        final ansMap = _asMap(ans);
        if (ansMap == null) continue;
        final title = _asString(ansMap['title']);
        final value = _asString(ansMap['value']);
        // 有些 answer 只有 optionIds / optionNames
        final optionNames = _asList(ansMap['optionNames']);
        if (title.isNotEmpty && value.isNotEmpty) {
          lines.add('$title：$value');
        } else if (title.isNotEmpty && optionNames.isNotEmpty) {
          lines.add('$title：${optionNames.map((o) => _asString(o)).join('、')}');
        } else if (value.isNotEmpty) {
          lines.add(value);
        }
      }
      return lines.join('\n');
    }

    // 舊版格式：{ data: [...] }
    final data = _asList(map['data']);
    if (data.isNotEmpty) {
      final lines = <String>[];
      for (final topic in data) {
        final topicMap = _asMap(topic);
        if (topicMap == null) continue;
        final title = _asString(topicMap['title']);
        final answerList = _asList(topicMap['answerList']);
        final values = answerList
            .map((a) => _asString(_asMap(a)?['value']))
            .where((v) => v.isNotEmpty)
            .toList();
        if (title.isNotEmpty && values.isNotEmpty) {
          lines.add('$title：${values.join('、')}');
        } else if (values.isNotEmpty) {
          lines.add(values.join('、'));
        }
      }
      return lines.join('\n');
    }

    // 退路：展平最外層 key-value
    final lines = <String>[];
    for (final entry in map.entries) {
      if (entry.key == 'form_id' || entry.key == 'calculations') continue;
      final text = _asString(entry.value);
      if (text.isNotEmpty) lines.add('${entry.key}：$text');
    }
    return lines.join('\n');
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
