import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/core/storage/secure_session_store.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

final sessionStoreProvider = Provider<SecureSessionStore>((ref) {
  return SecureSessionStore(ref.watch(sharedPreferencesProvider));
});

/// 目前的登入狀態。null 代表未登入（Requirement 2.4-9）。
class AuthState {
  const AuthState({this.session, this.isLoading = false, this.errorMessage});

  final AuthSession? session;
  final bool isLoading;
  final String? errorMessage;

  bool get isLoggedIn => session != null;

  AuthState copyWith({
    AuthSession? session,
    bool clearSession = false,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      session: clearSession ? null : (session ?? this.session),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 驅動登入、登出與啟動時的 session 還原（Requirement 1、2）。
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // 啟動時嘗試從安全儲存還原 session（Requirement 2.2）。
    final stored = ref.read(sessionStoreProvider).read();
    return AuthState(session: stored);
  }

  Future<bool> login(
      {required String account, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final session = await ref.read(authRepositoryProvider).login(
            account: account,
            password: password,
          );
      await ref.read(sessionStoreProvider).save(session);
      state = AuthState(session: session);
      return true;
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: _messageOf(error));
      return false;
    }
  }

  /// 現場 demo 快速登入（Requirement 1.10）。
  Future<bool> quickDemoLogin() =>
      login(account: 'smarthome_user_aug2026', password: 'SmartHome2026!');

  Future<void> logout() async {
    await ref.read(sessionStoreProvider).clear();
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState();
  }

  /// 401 觸發的強制登出（Requirement 2.13），保留錯誤訊息供畫面顯示。
  Future<void> forceLogout({String? reason}) async {
    await ref.read(sessionStoreProvider).clear();
    state = AuthState(errorMessage: reason ?? '登入已逾期，請重新登入');
  }

  String _messageOf(Object error) {
    // AuthError / ValidationError / NetworkError / ServerError 的 message
    // 已是使用者可讀文字（Requirement 22.4-5）。
    if (error is AppError) return error.message;
    return '登入失敗，請稍後再試';
  }
}

final authNotifierProvider =
    NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
