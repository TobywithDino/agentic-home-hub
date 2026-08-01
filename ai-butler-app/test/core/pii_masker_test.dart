import 'package:ai_butler_app/core/utils/pii_masker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/generators.dart';

void main() {
  group('遮罩範例', () {
    test('手機保留前 2 與末 3 碼', () {
      expect(PiiMasker.maskMobile('0912345678'), '09*****678');
    });
    test('Email 保留 @ 前 2 字元與完整網域', () {
      expect(PiiMasker.maskEmail('abcdef@example.com'), 'ab****@example.com');
    });
    test('姓名保留首字', () {
      expect(PiiMasker.maskName('王小明'), '王**');
    });
    test('null 與空字串', () {
      expect(PiiMasker.maskMobile(null), '');
      expect(PiiMasker.maskEmail(null), '');
    });
  });

  group('屬性 P9：遮罩不洩漏、不改長度、不拋例外', () {
    test('maskMobile 長度不變', () {
      forEachSeed((random, seed) {
        final gen = Gen(random);
        for (var i = 0; i < casesPerSeed; i++) {
          final input = gen.boolean() ? gen.mobile() : gen.text(maxLen: 30);
          final masked = PiiMasker.maskMobile(input);
          expect(masked.length, input.length, reason: 'seed=$seed');
        }
      });
    });

    test('maskEmail 長度不變', () {
      forEachSeed((random, seed) {
        final gen = Gen(random);
        for (var i = 0; i < casesPerSeed; i++) {
          final input = gen.boolean() ? gen.email() : gen.text(maxLen: 30);
          final masked = PiiMasker.maskEmail(input);
          expect(masked.length, input.length, reason: 'seed=$seed');
        }
      });
    });

    test('任意輸入不拋例外', () {
      forEachSeed((random, seed) {
        final gen = Gen(random);
        for (var i = 0; i < casesPerSeed; i++) {
          final input = gen.text(maxLen: 40);
          expect(() => PiiMasker.maskMobile(input), returnsNormally);
          expect(() => PiiMasker.maskEmail(input), returnsNormally);
          expect(() => PiiMasker.maskName(input), returnsNormally);
        }
      });
    });
  });
}
