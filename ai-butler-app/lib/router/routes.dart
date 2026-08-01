import 'package:ai_butler_app/router/route_guard.dart';

/// 路徑常數集中管理（Requirement 21.7）。
class Routes {
  Routes._();

  static const String login = '/login';
  static const String home = '/';
  static const String services = '/services';
  static const String orders = '/orders';
  static const String account = '/account';

  static const String vendors = '/vendors';

  /// 服務商詳情。
  ///
  /// [serviceType] 帶入使用者當前瀏覽的服務類型，詳情頁只會列出該類型的
  /// 服務項目；不帶則列出該商家全部服務。
  static String vendorDetail(int vendorId, {String? serviceType}) {
    if (serviceType == null || serviceType.isEmpty) return '/vendors/$vendorId';
    return '/vendors/$vendorId?serviceType=$serviceType';
  }

  /// 諮詢單填寫頁。
  ///
  /// [serviceId] 必須從服務項目頁帶進來：BFF 的 `GET /app-api/forms/{id}/full`
  /// 回應的 `form` 物件沒有 `service_id` 欄位，只靠表單自己推不出來，
  /// 少帶就會用 0 送出 feedback。
  static String form(int formId, {int? serviceId}) {
    if (serviceId == null || serviceId == 0) return '/forms/$formId';
    return '/forms/$formId?serviceId=$serviceId';
  }

  static String orderDetail(String orderNo) => '/orders/detail/$orderNo';
  static const String chat = '/chat';
}

/// 路徑 → 路由分類（Requirement 2.5）。
///
/// 用「起始字串比對」而非精確比對，涵蓋 `/vendors/123` 這類帶參數路徑。
RouteCategory categoryOf(String path) {
  if (path == Routes.login) return RouteCategory.login;

  const authRequiredPrefixes = <String>[
    '/forms',
    '/orders',
    '/account',
  ];
  for (final prefix in authRequiredPrefixes) {
    if (path.startsWith(prefix)) return RouteCategory.authRequired;
  }

  // 首頁、服務分頁、服務商列表/詳情、對話畫面皆可訪客瀏覽（Requirement 2.5）。
  return RouteCategory.guestBrowsable;
}
