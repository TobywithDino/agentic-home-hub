import 'package:ai_butler_app/domain/logic/order_status_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/generators.dart';

void main() {
  group('屬性 P8：狀態對照不拋錯', () {
    test('任意組合皆有回傳', () {
      forEachSeed((random, seed) {
        final gen = Gen(random);
        for (var i = 0; i < casesPerSeed; i++) {
          final type = gen.twoDigitCode();
          final status = gen.twoDigitCode();
          expect(() => OrderStatusMapper.map(type, status), returnsNormally);
          final view = OrderStatusMapper.map(type, status);
          expect(view.categoryName, isNotEmpty);
          expect(view.statusLabel, isNotEmpty);
        }
      });
    });

    test('未知 status 回退為「處理中」', () {
      final view = OrderStatusMapper.map('01', '77');
      expect(view.statusLabel, '處理中');
      expect(view.group, OrderStatusGroup.inProgress);
    });

    test('未知 type 回退為「其他服務」', () {
      final view = OrderStatusMapper.map('77', '01');
      expect(view.categoryName, '其他服務');
    });
  });
}
