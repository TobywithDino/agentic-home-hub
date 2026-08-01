import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/data/remote/api_client.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 真實後端的會員資訊實作。
///
/// BFF 端點：
/// - `PATCH /app-api/users/{id}` — 更新聯絡資訊或密碼
/// - 取得 profile 也用同端點（BFF 未提供獨立 GET，
///   但 DB Access 有 `GET /users/{id}`，我們直接打 8000 或用 PATCH 回傳值）
class HttpAccountRepository implements AccountRepository {
  HttpAccountRepository(this._client, {required this.getAccountId});

  final ApiClient _client;
  final String Function() getAccountId;

  @override
  Future<MemberProfile> fetchProfile() async {
    final accountId = getAccountId();

    // BFF 的 PATCH 回傳完整 user，傳空 body 即可取得目前資料
    // 注意：如果 BFF 不允許空 PATCH，可改用 DB Access GET /users/{id}
    final response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.updateUser(accountId),
      data: <String, dynamic>{},
    );

    final body = response.data;
    if (body == null) {
      throw const ServerError(
        message: '取得會員資訊失敗',
        endpoint: 'PATCH /app-api/users/{id}',
      );
    }

    return _mapProfile(body);
  }

  @override
  Future<void> updateContact(MemberProfile profile) async {
    final accountId = getAccountId();

    final payload = <String, dynamic>{
      'contact_name': profile.name.isNotEmpty ? profile.name : null,
      'contact_mobile': profile.mobile.isNotEmpty ? profile.mobile : null,
      'contact_email': profile.email.isNotEmpty ? profile.email : null,
    };

    await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.updateUser(accountId),
      data: payload,
    );
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final accountId = getAccountId();

    if (newPassword.length < 8) {
      throw const ValidationError(
        fieldErrors: <String, String>{'new_password': '新密碼長度至少 8 個字元'},
      );
    }

    // BFF PATCH 端點接受 password 欄位即為改密碼
    await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.updateUser(accountId),
      data: <String, dynamic>{'password': newPassword},
    );
  }

  MemberProfile _mapProfile(Map<String, dynamic> json) {
    return MemberProfile(
      name: json['contact_name'] as String? ?? '',
      mobile: json['contact_mobile'] as String? ?? '',
      email: json['contact_email'] as String? ?? '',
    );
  }
}
