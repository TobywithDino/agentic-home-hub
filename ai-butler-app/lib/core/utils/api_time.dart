/// 後端時間字串 → 本地時間的統一解析入口。
///
/// 後端（PostgreSQL `timestamptz`）回傳的是 UTC，格式有兩種：
/// - `2026-08-01T18:18:45.558837Z`
/// - `2026-08-01T18:18:45.558837+00:00`
///
/// `DateTime.parse` 會保留 UTC 時區，而 `DateFormat.format()` 是照
/// DateTime 自己的時區輸出，直接格式化就會顯示 UTC 時間（台灣少 8 小時）。
/// 所有時間欄位都必須經過這裡轉成本地時間再顯示。
class ApiTime {
  ApiTime._();

  /// 解析後端時間字串並轉為本地時區。無法解析時回傳 null。
  ///
  /// 若字串沒有時區標記（沒有 `Z` 也沒有 `+HH:MM` / `-HH:MM`），
  /// 一律當成 UTC 處理——後端存的是 `timestamptz`，序列化時漏掉標記
  /// 的情況下把它當本地時間會憑空偏移 8 小時。
  static DateTime? tryParse(dynamic raw) {
    if (raw is DateTime) return raw.toLocal();
    if (raw is! String) return null;

    final value = raw.trim();
    if (value.isEmpty) return null;

    final normalized = _hasTimeZone(value) ? value : '${value}Z';
    return DateTime.tryParse(normalized)?.toLocal();
  }

  /// 解析失敗時回退到 [fallback]（預設為現在）。
  static DateTime parseOr(dynamic raw, {DateTime? fallback}) =>
      tryParse(raw) ?? fallback ?? DateTime.now();

  static bool _hasTimeZone(String value) {
    if (value.endsWith('Z') || value.endsWith('z')) return true;
    // 只看時間部分的偏移，避免把日期的 '-' 誤判成時區符號。
    final timeSeparator = value.indexOf('T');
    final timePart =
        timeSeparator == -1 ? value : value.substring(timeSeparator + 1);
    return timePart.contains('+') || timePart.contains('-');
  }
}
