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
  static String vendorDetail(int vendorId) => '/vendors/$vendorId';
  static String form(int formId) => '/forms/$formId';
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
