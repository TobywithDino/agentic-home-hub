/// 個資顯示遮罩（Requirement 11.4-5）
///
/// 純函式，無 Flutter 依賴，由屬性測試 P9 守住三個性質：
/// 可見字元數上限、長度不變、任意輸入不拋例外。
///
/// 注意：這裡只做「顯示遮罩」。加密與 hash 一律由後端配 KMS 處理，
/// App 不實作加密演算法、不持有金鑰（Requirement 11.2-3）。
class PiiMasker {
  PiiMasker._();

  static const String maskChar = '*';

  /// 手機號碼遮罩，保留前 2 碼與末 3 碼。
  ///
  /// `0912345678` → `09*****678`
  /// 長度不足以同時保留前後段時，全部遮罩。
  static String maskMobile(String? raw) {
    final value = raw ?? '';
    if (value.isEmpty) return '';

    const headKeep = 2;
    const tailKeep = 3;

    if (value.length <= headKeep + tailKeep) {
      return maskChar * value.length;
    }

    final head = value.substring(0, headKeep);
    final tail = value.substring(value.length - tailKeep);
    final maskedLength = value.length - headKeep - tailKeep;
    return '$head${maskChar * maskedLength}$tail';
  }

  /// Email 遮罩，保留 @ 前 2 個字元與完整網域。
  ///
  /// `abcdef@example.com` → `ab****@example.com`
  static String maskEmail(String? raw) {
    final value = raw ?? '';
    if (value.isEmpty) return '';

    final atIndex = value.indexOf('@');
    // 沒有 @ 的輸入不視為 email，退化為全遮罩，維持長度不變。
    if (atIndex <= 0) return maskChar * value.length;

    final local = value.substring(0, atIndex);
    final domain = value.substring(atIndex);

    const headKeep = 2;
    if (local.length <= headKeep) {
      return '${maskChar * local.length}$domain';
    }

    final head = local.substring(0, headKeep);
    return '$head${maskChar * (local.length - headKeep)}$domain';
  }

  /// 市話遮罩，規則與手機相同。
  static String maskLandline(String? raw) => maskMobile(raw);

  /// 姓名遮罩，保留首字。`王小明` → `王**`
  static String maskName(String? raw) {
    final value = raw ?? '';
    if (value.isEmpty) return '';
    if (value.length == 1) return value;
    return '${value.substring(0, 1)}${maskChar * (value.length - 1)}';
  }

  /// 詳細地址遮罩，保留前 6 個字元。
  static String maskAddressDetail(String? raw) {
    final value = raw ?? '';
    if (value.isEmpty) return '';
    const headKeep = 6;
    if (value.length <= headKeep) return value;
    return '${value.substring(0, headKeep)}${maskChar * (value.length - headKeep)}';
  }

  /// 取 UUID 末 6 碼供帳戶頁顯示（Requirement 3.3）。
  static String accountIdSuffix(String? raw) {
    final value = (raw ?? '').replaceAll('-', '');
    if (value.isEmpty) return '';
    if (value.length <= 6) return value.toUpperCase();
    return value.substring(value.length - 6).toUpperCase();
  }

  /// 需要從偵錯日誌中排除的鍵名（Requirement 11.7）。
  static const Set<String> sensitiveKeys = <String>{
    'password',
    'old_password',
    'new_password',
    'access_token',
    'contact_name',
    'contact_mobile',
    'contact_landline',
    'contact_email',
    'contact_address_detail',
    'member_name',
    'member_phone',
    'member_email',
    'name',
    'mobile',
    'landline',
    'email',
    'address_detail',
  };

  /// 遞迴過濾 Map 中的個資鍵，供日誌攔截器使用。
  static Object? redact(Object? input) {
    if (input is Map) {
      return input.map<String, Object?>((key, value) {
        final keyName = key.toString();
        if (sensitiveKeys.contains(keyName.toLowerCase())) {
          return MapEntry(keyName, '[redacted]');
        }
        return MapEntry(keyName, redact(value));
      });
    }
    if (input is List) {
      return input.map(redact).toList();
    }
    return input;
  }
}
