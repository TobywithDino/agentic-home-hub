import 'package:ai_butler_app/design_system/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/contrast.dart';

void main() {
  group('正文對比度 ≥ 4.5:1', () {
    for (final entry in <String, dynamic>{
      'textPrimary': AppColors.textPrimary,
      'textSecondary': AppColors.textSecondary,
      'primary': AppColors.primary,
      'success': AppColors.success,
      'warning': AppColors.warning,
      'error': AppColors.error,
    }.entries) {
      test('${entry.key} 對 background', () {
        expect(contrastRatio(entry.value, AppColors.background), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('類別色票對比度 ≥ 3:1', () {
    for (final entry in AppColors.categoryColors.entries) {
      test('類別 ${entry.key}', () {
        expect(contrastRatio(entry.value, AppColors.background), greaterThanOrEqualTo(3.0));
      });
    }
  });

  test('categoryColor 接受補零前後兩種寫法', () {
    expect(AppColors.categoryColor('1'), AppColors.categoryColor('01'));
    expect(AppColors.categoryColor('9'), AppColors.categoryColor('09'));
  });

  test('未知代碼回退主色', () {
    expect(AppColors.categoryColor('99'), AppColors.primary);
  });
}
