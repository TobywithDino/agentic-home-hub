import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/data/remote/api_client.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 真實後端的訂單查詢實作。
///
/// BFF 端點 `GET /app-api/users/{id}/orders-overview` 一次回傳
/// feedbacks + orders，本實作將其拆為 ConsultationItem 與 OrderItem。
class HttpOrderRepository implements OrderRepository {
  HttpOrderRepository(this._client, {required this.getAccountId});

  final ApiClient _client;
  final String Function() getAccountId;

  @override
  Future<OrderInbox> fetchInbox() async {
    final accountId = getAccountId();

    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.ordersOverview(accountId),
    );

    final body = response.data;
    if (body == null) {
      throw const ServerError(
        message: '訂單總覽回應格式異常',
        endpoint: 'GET /app-api/users/{id}/orders-overview',
      );
    }

    // 解析 feedbacks
    final rawFeedbacks = (body['feedbacks'] as List<dynamic>?) ?? [];
    final consultations = rawFeedbacks.map((f) {
      final map = f as Map<String, dynamic>;
      return ConsultationItem(
        feedbackNo: map['feedback_no'] as String? ?? '',
        serviceName: _resolveServiceName(map['service_id']),
        submittedAt: DateTime.tryParse(map['cre_time'] as String? ?? '') ?? DateTime.now(),
        status: _feedbackStatusText(map['status'] as String? ?? '0'),
      );
    }).toList();

    // 解析 orders
    final rawOrders = (body['orders'] as List<dynamic>?) ?? [];
    final orders = rawOrders.map((o) {
      final map = o as Map<String, dynamic>;
      return OrderItem(
        orderNo: map['order_no'] as String? ?? '',
        orderType: map['order_type'] as String? ?? '',
        orderStatus: map['order_status'] as String? ?? '',
        finalAmount: (map['final_amount'] as num?) ?? 0,
        orderTime: DateTime.tryParse(map['order_time'] as String? ?? '') ?? DateTime.now(),
        serviceName: _resolveServiceName(map['service_id']),
        contactMobile: map['contact_mobile'] as String? ?? '',
      );
    }).toList();

    return OrderInbox(
      consultations: consultations,
      orders: orders,
    );
  }

  String _feedbackStatusText(String code) {
    return switch (code) {
      '0' => '未處理',
      '1' => '處理中',
      '2' => '已完成',
      _ => '未知',
    };
  }

  /// 將 service_id 對應為可讀名稱。
  /// BFF 未回傳 service name，暫以 service_type 對照。
  String _resolveServiceName(dynamic serviceId) {
    if (serviceId == null) return '服務諮詢';
    return '服務諮詢';
  }
}
