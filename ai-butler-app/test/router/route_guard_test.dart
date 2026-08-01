import 'package:ai_butler_app/router/route_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/generators.dart';

void main() {
  group('屬性 P11：路由守衛決定性', () {
    test('已登入者永不被導向 Login', () {
      forEachSeed((random, seed) {
        final gen = Gen(random);
        for (var i = 0; i < casesPerSeed; i++) {
          final category = gen.oneOf(RouteCategory.values);
          final result = RouteGuard.resolve(
            guestBrowsing: gen.boolean(),
            isLoggedIn: true,
            category: category,
          );
          if (category != RouteCategory.login) {
            expect(result.decision, GuardDecision.allow, reason: 'seed=$seed');
          }
        }
      });
    });

    test('決策表驗證', () {
      expect(
        RouteGuard.resolve(guestBrowsing: false, isLoggedIn: false, category: RouteCategory.guestBrowsable).decision,
        GuardDecision.redirectToLogin,
      );
      expect(
        RouteGuard.resolve(guestBrowsing: true, isLoggedIn: false, category: RouteCategory.guestBrowsable).decision,
        GuardDecision.allow,
      );
      expect(
        RouteGuard.resolve(guestBrowsing: true, isLoggedIn: false, category: RouteCategory.authRequired).decision,
        GuardDecision.redirectToLogin,
      );
      expect(
        RouteGuard.resolve(guestBrowsing: false, isLoggedIn: true, category: RouteCategory.login).decision,
        GuardDecision.redirectToHome,
      );
    });
  });
}
