/// 路由分類（Requirement 2.4-9）。
enum RouteCategory { login, guestBrowsable, authRequired }

/// 決策結果。
enum GuardDecision { allow, redirectToLogin, redirectToHome }

/// 未登入且被擋下時，是否記錄原目標路徑供登入後導回。
class RouteGuardResult {
  const RouteGuardResult(this.decision, {this.rememberTarget = false});

  final GuardDecision decision;
  final bool rememberTarget;
}

/// 純函式的路由守衛決策（Requirement 2.4-9）。
///
/// 由屬性測試 P11 守住：對任意 (guestBrowsing, isLoggedIn, category) 組合，
/// 必回傳唯一結果，且已登入者永不被導向 Login（除非目標本身是 Login，
/// 這種情況導向首頁避免登入頁對已登入者可見）。
class RouteGuard {
  const RouteGuard._();

  static RouteGuardResult resolve({
    required bool guestBrowsing,
    required bool isLoggedIn,
    required RouteCategory category,
  }) {
    // 已登入者任何時候都不會被導去 Login；若目標就是 Login，導回首頁。
    if (isLoggedIn) {
      if (category == RouteCategory.login) {
        return const RouteGuardResult(GuardDecision.redirectToHome);
      }
      return const RouteGuardResult(GuardDecision.allow);
    }

    // 未登入：Login 永遠可進。
    if (category == RouteCategory.login) {
      return const RouteGuardResult(GuardDecision.allow);
    }

    // 未登入 + guestBrowsing=false：任何非 Login 頁面都導去 Login。
    if (!guestBrowsing) {
      return const RouteGuardResult(GuardDecision.redirectToLogin, rememberTarget: true);
    }

    // 未登入 + guestBrowsing=true：可訪客瀏覽頁允許，需登入頁導去 Login。
    return switch (category) {
      RouteCategory.guestBrowsable => const RouteGuardResult(GuardDecision.allow),
      RouteCategory.authRequired =>
        const RouteGuardResult(GuardDecision.redirectToLogin, rememberTarget: true),
      RouteCategory.login => const RouteGuardResult(GuardDecision.allow),
    };
  }
}
