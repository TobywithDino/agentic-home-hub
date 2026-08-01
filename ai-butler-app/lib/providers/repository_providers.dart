import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_butler_app/core/config/environment_config.dart';
import 'package:ai_butler_app/data/mock/mock_repositories.dart';
import 'package:ai_butler_app/data/remote/api_client.dart';
import 'package:ai_butler_app/data/remote/http_account_repository.dart';
import 'package:ai_butler_app/data/remote/http_auth_repository.dart';
import 'package:ai_butler_app/data/remote/http_feedback_repository.dart';
import 'package:ai_butler_app/data/remote/http_form_repository.dart';
import 'package:ai_butler_app/data/remote/http_order_repository.dart';
import 'package:ai_butler_app/data/remote/http_review_repository.dart';
import 'package:ai_butler_app/data/remote/http_vendor_repository.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 環境設定的單一來源。啟動時決定，執行期不變。
final environmentConfigProvider = Provider<EnvironmentConfig>((ref) {
  return EnvironmentConfig.fromEnvironment();
});

/// 共用的 ApiClient 實例（BFF, port 8100）。
final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return ApiClient(baseUrl: config.effectiveBaseUrl);
});

/// SharedPreferences provider — 啟動時由 main() 覆寫。
/// 放在這裡讓 repository_providers 和 session_providers 都能使用，
/// 避免循環 import。
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider 必須在 main() 以 ProviderScope.overrides 覆寫',
  );
});

/// 從本機儲存讀取已登入的 account id。
String _readAccountId(Ref ref) {
  try {
    final prefs = ref.read(sharedPreferencesProvider);
    return prefs.getString('session.inbr_account_id') ?? '';
  } catch (_) {
    return '';
  }
}

/// 7 個 Repository 的注入點（Requirement 21.4）。

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return switch (config.dataSource) {
    DataSource.mock => MockAuthRepository(),
    DataSource.remote => HttpAuthRepository(ref.watch(apiClientProvider)),
  };
});

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return switch (config.dataSource) {
    DataSource.mock => MockAccountRepository(),
    DataSource.remote => HttpAccountRepository(
        ref.watch(apiClientProvider),
        getAccountId: () => _readAccountId(ref),
      ),
  };
});

final serviceCatalogRepositoryProvider =
    Provider<ServiceCatalogRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return switch (config.dataSource) {
    DataSource.mock => MockServiceCatalogRepository(),
    DataSource.remote =>
      HttpServiceCatalogRepository(ref.watch(apiClientProvider)),
  };
});

final vendorRepositoryProvider = Provider<VendorRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return switch (config.dataSource) {
    DataSource.mock => MockVendorRepository(),
    DataSource.remote => HttpVendorRepository(ref.watch(apiClientProvider)),
  };
});

final formRepositoryProvider = Provider<FormRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return switch (config.dataSource) {
    DataSource.mock => MockFormRepository(),
    DataSource.remote => HttpFormRepository(ref.watch(apiClientProvider)),
  };
});

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return switch (config.dataSource) {
    DataSource.mock => MockFeedbackRepository(),
    DataSource.remote => HttpFeedbackRepository(
        ref.watch(apiClientProvider),
        getAccountId: () => _readAccountId(ref),
      ),
  };
});

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return switch (config.dataSource) {
    DataSource.mock => MockOrderRepository(),
    DataSource.remote => HttpOrderRepository(
        ref.watch(apiClientProvider),
        getAccountId: () => _readAccountId(ref),
      ),
  };
});

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return switch (config.dataSource) {
    DataSource.mock => MockReviewRepository(),
    DataSource.remote => HttpReviewRepository(
        ref.watch(apiClientProvider),
        getAccountId: () => _readAccountId(ref),
      ),
  };
});
