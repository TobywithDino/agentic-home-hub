import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 表單草稿的本機暫存（Requirement 8.9-13）。
///
/// 以 `form_id` 為 key，將作答值的 JSON 字串寫入 `shared_preferences`。
/// 1 秒 debounce 的計時邏輯由 Notifier/Screen 負責，本類只管讀寫。
class DraftStore {
  DraftStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'draft.form_';

  String _key(int formId) => '$_prefix$formId';

  /// 儲存草稿。[data] 為可 JSON 序列化的 Map（通常是 answers 的簡化版）。
  Future<void> save(int formId, Map<String, Object?> data) async {
    await _prefs.setString(_key(formId), jsonEncode(data));
  }

  /// 讀取草稿。回傳 null 代表沒有已存草稿。
  Map<String, Object?>? read(int formId) {
    final raw = _prefs.getString(_key(formId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 刪除草稿（送出成功或使用者選擇重新填寫時呼叫）。
  Future<void> delete(int formId) async {
    await _prefs.remove(_key(formId));
  }

  /// 是否存在該 form 的草稿。
  bool hasDraft(int formId) => _prefs.containsKey(_key(formId));
}
