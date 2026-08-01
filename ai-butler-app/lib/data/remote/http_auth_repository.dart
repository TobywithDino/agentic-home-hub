import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/data/remote/api_client.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 真實後端的登入實作。
///
/// BFF 目前無 token 機制，登入僅回傳 inbr_account_id，
/// 我們以 account_id 本身作為 accessToken 的替代欄位。
class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<AuthSession> login({
    required String account,
    required String password,
  }) async {
    if (account.trim().isEmpty || password.trim().isEmpty) {
      throw const ValidationError(message: '帳號或密碼不可為空');
    }

    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.login,
      data: {'account': account, 'password': password},
    );

    final body = response.data;
    if (body == null || body['inbr_account_id'] == null) {
      throw const ServerError(
        message: '登入回應格式異常',
        endpoint: 'POST /app-api/auth/login',
      );
    }

    final accountId = body['inbr_account_id'] as String;

    // 設定 client 的 account id 供後續請求使用
    _client.setAccountId(accountId);

    return AuthSession(
      inbrAccountId: accountId,
      // BFF 無 token，以 account_id 作為 session 識別
      accessToken: accountId,
    );
  }

  @override
  Future<void> logout() async {
    _client.setAccountId(null);
  }
}
