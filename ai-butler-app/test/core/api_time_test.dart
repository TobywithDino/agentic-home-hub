import 'package:flutter_test/flutter_test.dart';

import 'package:ai_butler_app/core/utils/api_time.dart';

void main() {
  group('ApiTime.tryParse 一律轉成本地時區', () {
    test('帶 Z 的 UTC 字串轉為本地時間', () {
      // 後端實際回傳格式（PostgreSQL timestamptz）
      final parsed = ApiTime.tryParse('2026-08-01T18:18:45.558837Z');

      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isFalse, reason: '必須轉成本地時間才不會顯示錯 8 小時');
      // 同一瞬間：與原字串的 UTC 值相等
      expect(
        parsed.toUtc(),
        DateTime.utc(2026, 8, 1, 18, 18, 45, 558, 837),
      );
    });

    test('帶 +00:00 偏移的字串同樣正確', () {
      final parsed = ApiTime.tryParse('2026-08-01T08:55:49.948702+00:00');

      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isFalse);
      expect(parsed.toUtc(), DateTime.utc(2026, 8, 1, 8, 55, 49, 948, 702));
    });

    test('沒有時區標記時視為 UTC，而不是本地時間', () {
      final naive = ApiTime.tryParse('2026-08-01T18:18:45');
      final explicit = ApiTime.tryParse('2026-08-01T18:18:45Z');

      expect(naive, isNotNull);
      expect(naive, explicit, reason: '後端存的是 timestamptz，無標記時應當成 UTC');
    });

    test('負偏移不會被日期的 - 誤判', () {
      final parsed = ApiTime.tryParse('2026-08-01T18:18:45-08:00');

      expect(parsed, isNotNull);
      expect(parsed!.toUtc(), DateTime.utc(2026, 8, 2, 2, 18, 45));
    });

    test('null / 空字串 / 非字串回傳 null', () {
      expect(ApiTime.tryParse(null), isNull);
      expect(ApiTime.tryParse(''), isNull);
      expect(ApiTime.tryParse('   '), isNull);
      expect(ApiTime.tryParse(12345), isNull);
      expect(ApiTime.tryParse('not a date'), isNull);
    });

    test('parseOr 在解析失敗時使用 fallback', () {
      final fallback = DateTime(2026, 1, 1);
      expect(ApiTime.parseOr(null, fallback: fallback), fallback);
      expect(
        ApiTime.parseOr('2026-08-01T18:18:45Z', fallback: fallback),
        isNot(fallback),
      );
    });
  });
}
