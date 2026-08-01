/// 日期題（type 09）的可選範圍換算（Requirement 7.16）。
///
/// 純函式，由屬性測試 P7 守住範圍封閉性。
class DateRangeResolver {
  const DateRangeResolver._();

  /// 以 [today] 為基準，回傳 `[today+start, today+end]` 的日期範圍（含端點）。
  ///
  /// 只取日期部分（去除時分秒），避免同一天因時間不同被誤判為範圍外。
  static ({DateTime start, DateTime end}) resolve({
    required DateTime today,
    required int startOffsetDays,
    required int endOffsetDays,
  }) {
    final base = DateTime(today.year, today.month, today.day);
    final normalizedEnd = endOffsetDays < startOffsetDays ? startOffsetDays : endOffsetDays;
    return (
      start: base.add(Duration(days: startOffsetDays)),
      end: base.add(Duration(days: normalizedEnd)),
    );
  }

  /// 判斷某天是否落在可選範圍內（含端點）。
  static bool isSelectable({
    required DateTime day,
    required DateTime today,
    required int startOffsetDays,
    required int endOffsetDays,
  }) {
    final range = resolve(
      today: today,
      startOffsetDays: startOffsetDays,
      endOffsetDays: endOffsetDays,
    );
    final normalizedDay = DateTime(day.year, day.month, day.day);
    return !normalizedDay.isBefore(range.start) && !normalizedDay.isAfter(range.end);
  }
}
