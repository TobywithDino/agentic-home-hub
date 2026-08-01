import 'package:flutter/material.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';

/// 輕量 HTML 渲染器（Requirement 6.4、6.6）。
///
/// 設計文件原規劃使用 `flutter_html`，但該套件不在離線 pub cache 中。
/// 命題附件的 HTML 內容只用到 `<p>`、`<b>`／`<strong>`、`<br>` 這幾個
/// 基本標籤，因此自製一個最小渲染器，行為明確且無第三方依賴風險。
///
/// TODO(followup): 待網路環境允許時，評估換回 `flutter_html` 以支援
/// 更複雜的排版；目前的實作已滿足 Requirement 6.6（略過 script/iframe）。
class SimpleHtmlView extends StatelessWidget {
  const SimpleHtmlView({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    final paragraphs = _parseParagraphs(html);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final paragraph in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text.rich(
              paragraph,
              style: AppTypography.body.copyWith(color: context.butler.secondaryText),
            ),
          ),
      ],
    );
  }

  /// 移除 script/iframe 內容（Requirement 6.6），將 `<p>` 拆成段落，
  /// `<br>` 轉換為換行，`<b>`／`<strong>` 轉換為粗體 span。
  static List<InlineSpan> _parseParagraphs(String rawHtml) {
    var sanitized = rawHtml
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<iframe[^>]*>.*?</iframe>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

    final blocks = sanitized
        .split(RegExp(r'</p>', caseSensitive: false))
        .map((b) => b.replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '').trim())
        .where((b) => b.isNotEmpty)
        .toList();

    if (blocks.isEmpty && sanitized.trim().isNotEmpty) {
      blocks.add(sanitized.trim());
    }

    return blocks.map(_parseInline).toList();
  }

  static InlineSpan _parseInline(String block) {
    final spans = <InlineSpan>[];
    final boldPattern = RegExp(
      r'<(b|strong)>(.*?)</\1>',
      caseSensitive: false,
      dotAll: true,
    );

    var lastEnd = 0;
    for (final match in boldPattern.allMatches(block)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: _stripTags(block.substring(lastEnd, match.start))));
      }
      spans.add(TextSpan(
        text: _stripTags(match.group(2) ?? ''),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < block.length) {
      spans.add(TextSpan(text: _stripTags(block.substring(lastEnd))));
    }
    return TextSpan(children: spans);
  }

  static String _stripTags(String text) => text.replaceAll(RegExp(r'<[^>]+>'), '');
}
