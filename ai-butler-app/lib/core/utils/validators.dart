/// 帳戶相關的欄位格式驗證（Requirement 3.6-9）。
///
/// 與 `FormValidator`（動態諮詢單用）分開維護：兩者驗證的情境不同
/// （諮詢單聯絡資料 vs. 會員帳戶資訊），避免耦合造成互相牽制。
class Validators {
  Validators._();

  static final RegExp _mobilePattern = RegExp(r'^09\d{8}$');
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final RegExp _hasLetter = RegExp(r'[A-Za-z]');
  static final RegExp _hasDigit = RegExp(r'\d');

  /// 台灣手機格式：09 開頭、共 10 位數字（Requirement 3.6）。
  static bool isValidTaiwanMobile(String value) => _mobilePattern.hasMatch(value.trim());

  /// Email 需含 `@` 與網域部分（Requirement 3.7）。
  static bool isValidEmail(String value) => _emailPattern.hasMatch(value.trim());

  /// 新密碼需至少 8 個字元且包含英文字母與數字（Requirement 3.9）。
  static bool isValidPassword(String value) {
    return value.length >= 8 && _hasLetter.hasMatch(value) && _hasDigit.hasMatch(value);
  }
}
