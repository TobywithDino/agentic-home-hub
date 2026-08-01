import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/features/account/account_screen.dart';
import 'package:ai_butler_app/features/auth/login_screen.dart';
import 'package:ai_butler_app/features/butler_chat/butler_chat_screen.dart';
import 'package:ai_butler_app/features/form/form_screen.dart';
import 'package:ai_butler_app/features/home/home_screen.dart';
import 'package:ai_butler_app/features/orders/order_detail_screen.dart';
import 'package:ai_butler_app/features/orders/order_list_screen.dart';
import 'package:ai_butler_app/features/vendor/vendor_detail_screen.dart';
import 'package:ai_butler_app/features/vendor/vendor_list_screen.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';
import 'package:ai_butler_app/providers/session_providers.dart';
import 'package:ai_butler_app/router/app_shell.dart';
import 'package:ai_butler_app/router/route_guard.dart';
import 'package:ai_butler_app/router/routes.dart';
import 'package:ai_butler_app/router/transitions.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 監聯登入狀態變化，驅動 [GoRouter] 重新計算 redirect（Requirement 2.5-9）。
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _ref.listen<AuthState>(authNotifierProvider, (previous, next) {
      if (previous?.isLoggedIn != next.isLoggedIn) {
        // 延遲通知讓 widget tree 在當前 frame 完成 dispose，
        // 避免 StatefulShellRoute 的 _dependents.isEmpty assertion。
        Future<void>.microtask(notifyListeners);
      }
    });
  }

  final Ref _ref;
}

/// 組裝路由表（Requirement 21.7）。以 [ref] 讀取 guestBrowsing 與登入狀態。
GoRouter buildAppRouter(Ref ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.home,
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final isLoggedIn = ref.read(authNotifierProvider).isLoggedIn;
      final guestBrowsing = ref.read(environmentConfigProvider).guestBrowsing;
      final path = state.matchedLocation;

      final result = RouteGuard.resolve(
        guestBrowsing: guestBrowsing,
        isLoggedIn: isLoggedIn,
        category: categoryOf(path),
      );

      switch (result.decision) {
        case GuardDecision.allow:
          return null;
        case GuardDecision.redirectToHome:
          return Routes.home;
        case GuardDecision.redirectToLogin:
          final from = Uri.encodeQueryComponent(state.uri.toString());
          return '${Routes.login}?from=$from';
      }
    },
    routes: <RouteBase>[
      GoRoute(
        path: Routes.login,
        pageBuilder: (context, state) => AppTransitions.fadeThrough(
            child: const LoginScreen(), state: state),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen()),
          ]),
          // AI 管家改成分頁（左邊數來第二個），對話內容在切換分頁時保留。
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(
                path: Routes.chat,
                builder: (context, state) => const ButlerChatScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(
                path: Routes.orders,
                builder: (context, state) => const OrderListScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(
                path: Routes.account,
                builder: (context, state) => const AccountScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: Routes.vendors,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final serviceIdRaw = state.uri.queryParameters['serviceId'];
          final keyword = state.uri.queryParameters['keyword'] ?? '';
          return AppTransitions.sharedAxis(
            state: state,
            child: VendorListScreen(
              serviceId:
                  serviceIdRaw == null ? null : int.tryParse(serviceIdRaw),
              keyword: keyword,
            ),
          );
        },
      ),
      GoRoute(
        path: '${Routes.vendors}/:vendorId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final vendorId = int.parse(state.pathParameters['vendorId']!);
          // 從哪個服務類型點進來就只顯示該類型的服務項目。
          final serviceType = state.uri.queryParameters['serviceType'];
          return AppTransitions.sharedAxis(
            state: state,
            child: VendorDetailScreen(
              vendorId: vendorId,
              serviceType: serviceType,
            ),
          );
        },
      ),
      GoRoute(
        path: '/forms/:formId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final formId = int.parse(state.pathParameters['formId']!);
          // service_id 由服務項目頁帶入，表單 API 本身不含此欄位。
          final serviceIdRaw = state.uri.queryParameters['serviceId'];
          return AppTransitions.modal(
            state: state,
            child: FormScreen(
              formId: formId,
              serviceId:
                  serviceIdRaw == null ? null : int.tryParse(serviceIdRaw),
            ),
          );
        },
      ),
      GoRoute(
        path: '/orders/detail/:orderNo',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final orderNo = state.pathParameters['orderNo']!;
          return AppTransitions.sharedAxis(
            state: state,
            child: OrderDetailScreen(orderNo: orderNo),
          );
        },
      ),
    ],
  );
}

/// 提供給 [MaterialApp.router] 使用的 provider。
final appRouterProvider = Provider<GoRouter>((ref) => buildAppRouter(ref));
