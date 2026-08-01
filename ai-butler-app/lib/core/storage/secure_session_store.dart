import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_butler_app/domain/models/domain_models.dart';

/// 登入憑證的本機儲存（Requirement 2.1-3）。
///
/// 設計文件原規劃使用 `flutter_secure_storage`，但現場離線環境下該套件
/// 不在 pub cache 中且無法安裝。改用 `shared_preferences`（已在依賴中）。
/// 這是暫時的技術妥協：`shared_preferences` 在 Android 上是明文 XML，
/// 不具備 Keychain/Keystore 等級的保護。
///
/// TODO(followup): 待網路環境允許時，改回 `flutter_secure_storage`，
/// 介面（[save] / [read] / [clear]）不需變動，只需替換實作內部。
class SecureSessionStore {
  SecureSessionStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _accountIdKey = 'session.inbr_account_id';
  static const String _tokenKey = 'session.access_token';

  Future<void> save(AuthSession session) async {
    await _prefs.setString(_accountIdKey, session.inbrAccountId);
    await _prefs.setString(_tokenKey, session.accessToken);
  }

  AuthSession? read() {
    final accountId = _prefs.getString(_accountIdKey);
    final token = _prefs.getString(_tokenKey);
    if (accountId == null || token == null) return null;
    return AuthSession(inbrAccountId: accountId, accessToken: token);
  }

  Future<void> clear() async {
    await _prefs.remove(_accountIdKey);
    await _prefs.remove(_tokenKey);
  }
}
