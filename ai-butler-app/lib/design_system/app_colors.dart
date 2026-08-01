import 'package:flutter/material.dart';

/// 語意色票（Requirement 17.1-2、17.7、19.3）
///
/// 調性取自「AI 智慧管家」參考視覺：暖米白底 + 管家綠主色。
/// 標註 `對比` 者為已驗證的對比度（相對 [background]），由
/// `test/design_system/app_colors_contrast_test.dart` 持續守住。
class AppColors {
  AppColors._();

  // === 11 組語意色票（淺色）===

  /// 管家綠。主要動作、選取態、品牌識別。對比 4.67:1（可作正文）
  static const Color primary = Color(0xFF2F7D5D);

  /// 主色淺底。選取態與標籤底色，不作文字色。
  static const Color primaryContainer = Color(0xFFDCEFE4);

  /// 暖橘。次要動作與活動標籤底色，不作正文（對比 3.08:1）。
  static const Color secondary = Color(0xFFC97B3C);

  /// 暖橘的文字安全版。對比 4.56:1
  static const Color secondaryText = Color(0xFFA75F27);

  /// 管家高亮、AI 標記。裝飾用途，不作正文。
  static const Color accent = Color(0xFFF2B544);

  /// 暖米白底。明度 97%（Requirement 17.2）
  /// 改為標準淺色白底（使用者反饋：整體色調選用預設淺色）
  static const Color background = Color(0xFFF9FAFB);

  /// 卡片與輸入框表面。
  static const Color surface = Color(0xFFFFFFFF);

  /// 區塊分隔底色。
  static const Color surfaceVariant = Color(0xFFF3F4F6);

  /// 正文主色。對比 13.91:1
  static const Color textPrimary = Color(0xFF2A2724);

  /// 正文次色。對比 5.52:1
  static const Color textSecondary = Color(0xFF6B635A);

  /// 邊框與分隔線。
  static const Color border = Color(0xFFE5E7EB);

  // === 狀態色（皆為文字安全）===

  /// 對比 4.80:1
  static const Color success = Color(0xFF2E7D32);

  /// 對比 5.98:1
  static const Color warning = Color(0xFF8A5200);

  /// 對比 5.26:1
  static const Color error = Color(0xFFC62828);

  /// 中性狀態（未知訂單狀態用，Requirement 15.6）
  static const Color neutral = Color(0xFF6B635A);

  // === 狀態填色（僅作底色，不作文字）===

  static const Color successSurface = Color(0xFFE3F1E4);
  static const Color warningSurface = Color(0xFFFBEFD9);
  static const Color errorSurface = Color(0xFFFAE4E4);
  static const Color neutralSurface = Color(0xFFEDE8E0);

  // === 7 組服務類別色票（Requirement 17.7，皆 ≥3:1）===

  /// service_id → 類別色。key 為 `cms_homepage_service.type` 的兩位數字代碼。
  static const Map<String, Color> categoryColors = <String, Color>{
    '01': Color(0xFF2F7D5D), // 一般居家清潔  對比 4.67:1
    '02': Color(0xFF2A6F97), // 家電清洗      對比 5.15:1
    '03': Color(0xFF8A5A2B), // 包裹寄送      對比 5.50:1
    '06': Color(0xFFB5462F), // 餐廳訂位      對比 5.06:1
    '09': Color(0xFFC2410C), // 美食外送      對比 4.85:1
    '10': Color(0xFF5B5BD6), // 水電修繕      對比 5.02:1
    '11': Color(0xFF7C3AED), // 商城購物      對比 5.33:1
  };

  /// 類別色的淺底版本，用於圖示襯底。
  static const Map<String, Color> categorySurfaces = <String, Color>{
    '01': Color(0xFFDCEFE4),
    '02': Color(0xFFDBEAF4),
    '03': Color(0xFFF0E4D6),
    '06': Color(0xFFF7E2DC),
    '09': Color(0xFFFAE3D6),
    '10': Color(0xFFE3E3F8),
    '11': Color(0xFFEDE2FB),
  };

  /// 取類別色，未知代碼回退主色（不拋例外，Requirement 7.18 的同類容錯）。
  static Color categoryColor(String serviceType) =>
      categoryColors[_pad(serviceType)] ?? primary;

  /// 取類別淺底色，未知代碼回退主色淺底。
  static Color categorySurface(String serviceType) =>
      categorySurfaces[_pad(serviceType)] ?? primaryContainer;

  /// 附件 JSON 同時出現 `1` 與 `01` 兩種寫法，統一補零後比對。
  static String _pad(String raw) {
    final trimmed = raw.trim();
    return trimmed.length == 1 ? '0$trimmed' : trimmed;
  }

  // === 深色色票（Requirement 20.1，P2）===

  static const Color darkBackground = Color(0xFF15130F);
  static const Color darkSurface = Color(0xFF201D18);
  static const Color darkSurfaceVariant = Color(0xFF2B2721);
  static const Color darkTextPrimary = Color(0xFFF2EDE4);
  static const Color darkTextSecondary = Color(0xFFB8AFA2);
  static const Color darkBorder = Color(0xFF3A342C);
  static const Color darkPrimary = Color(0xFF7FCBA6);
}
