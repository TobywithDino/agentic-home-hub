import 'dart:async';

import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/services/butler_ai_service.dart';

/// Mock AI 管家（Requirement 12.14、13.10）。
///
/// 依關鍵字比對回傳腳本化回覆，打字機效果以 50ms 間隔逐段產出
/// （Requirement 12.4）。現場 demo 不需網路即可展示 AI 對話流程。
class MockButlerAiService implements ButlerAiService {
  @override
  Stream<ButlerChunk> send(String message) async* {
    // 模擬「思考中」延遲
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final lower = message.toLowerCase();
    final response = _matchResponse(lower);

    // 打字機效果：每 50ms 產出一小段文字（Requirement 12.4）
    final chars = response.text.split('');
    final buffer = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      buffer.write(chars[i]);
      // 每 3 個字元或到結尾時 yield 一次，模擬真實串流分段
      if ((i + 1) % 3 == 0 || i == chars.length - 1) {
        yield TextDelta(buffer.toString());
        buffer.clear();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    // 結構化卡片（如果有的話）
    for (final chunk in response.extras) {
      yield chunk;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    // 建議快捷選項
    yield SuggestionChips(response.chips);

    yield const Done();
  }

  @override
  Future<IntentResult> classify(String utterance) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final lower = utterance.toLowerCase();

    if (lower.contains('清潔') || lower.contains('打掃')) {
      return const IntentResult(serviceIds: [1], confidences: [0.92]);
    }
    if (lower.contains('冷氣') || lower.contains('家電')) {
      return const IntentResult(serviceIds: [2], confidences: [0.88]);
    }
    if (lower.contains('訂位') || lower.contains('餐廳')) {
      return const IntentResult(serviceIds: [6], confidences: [0.90]);
    }
    if (lower.contains('外送') || lower.contains('火鍋') || lower.contains('吃')) {
      return const IntentResult(serviceIds: [9], confidences: [0.85]);
    }
    if (lower.contains('修繕') || lower.contains('水電') || lower.contains('漏水')) {
      return const IntentResult(serviceIds: [10], confidences: [0.91]);
    }
    if (lower.contains('寄') || lower.contains('包裹')) {
      return const IntentResult(serviceIds: [3], confidences: [0.87]);
    }
    // 多意圖：「吃火鍋，順便叫人來整理家裡」
    if (lower.contains('火鍋') && lower.contains('整理')) {
      return const IntentResult(serviceIds: [9, 1], confidences: [0.82, 0.78]);
    }
    return const IntentResult(serviceIds: [], confidences: []);
  }

  @override
  Future<PrefillResult> prefill(
      String utterance, FormDefinition definition) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // 簡單的 demo 預填：把使用者描述塞到第一個詳答題
    final longTextTopic =
        definition.allTopics.where((t) => t.type.code == '02').firstOrNull;
    final filled = <int, Object?>{};
    if (longTextTopic != null) {
      filled[longTextTopic.topicId] = utterance;
    }
    return PrefillResult(
      filledFields: filled,
      summary: '已為您預填需求描述，請確認其餘欄位後送出。',
    );
  }

  @override
  Future<String> explainTopic(FormTopic topic) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return '「${topic.title}」${topic.remark.isNotEmpty ? '：${topic.remark}' : ''}\n\n'
        '範例填寫：根據您的需求，可以這樣填寫 —— '
        '例如描述具體的時間、地點、數量或特殊需求。';
  }

  _ScriptedResponse _matchResponse(String lower) {
    if (lower.contains('清潔') || lower.contains('打掃') || lower.contains('整理')) {
      return const _ScriptedResponse(
        text: '好的！我幫您找到居家清潔的服務商。您可以從列表中選擇合適的廠商，再填寫諮詢單告訴他們具體需求。',
        chips: ['查看清潔服務商', '我要預約時間', '有什麼注意事項？', '幫我填表單'],
        extras: [CategoryCard(serviceId: 1, name: '一般居家清潔')],
      );
    }
    if (lower.contains('冷氣') || lower.contains('家電')) {
      return const _ScriptedResponse(
        text: '家電清洗服務可以幫您處理冷氣、洗衣機等設備的深層清潔。我來推薦幾家口碑不錯的廠商。',
        chips: ['查看家電清洗廠商', '清洗冷氣要多久？', '費用大概多少？'],
        extras: [CategoryCard(serviceId: 2, name: '家電清洗')],
      );
    }
    if (lower.contains('訂位') || lower.contains('餐廳')) {
      return const _ScriptedResponse(
        text: '想訂位的話，請告訴我您的用餐人數、時間和偏好的料理類型，我幫您媒合合適的餐廳。',
        chips: ['2 位今晚 7 點', '4 位週五午餐', '有推薦的嗎？'],
        extras: [CategoryCard(serviceId: 6, name: '餐廳訂位')],
      );
    }
    if (lower.contains('外送') || lower.contains('火鍋') || lower.contains('吃')) {
      return const _ScriptedResponse(
        text: '美食外送服務為您送餐到府！您想吃什麼類型的料理呢？我可以推薦附近評價好的店家。',
        chips: ['火鍋外送', '便當', '隨便都好', '看看有什麼'],
        extras: [CategoryCard(serviceId: 9, name: '美食外送')],
      );
    }
    if (lower.contains('水電') || lower.contains('修繕') || lower.contains('漏水')) {
      return const _ScriptedResponse(
        text: '水電修繕需要盡快處理！我幫您找附近可服務的師傅，您可以上傳現場照片讓報價更準確。',
        chips: ['查看水電師傅', '緊急搶修', '上傳照片'],
        extras: [CategoryCard(serviceId: 10, name: '水電修繕')],
      );
    }
    // 預設回覆
    return const _ScriptedResponse(
      text: '好的，我幫您整理需求。請問您需要哪方面的生活服務呢？以下是我們提供的服務類別：',
      chips: ['居家清潔', '餐廳訂位', '水電修繕', '美食外送'],
      extras: [],
    );
  }
}

class _ScriptedResponse {
  const _ScriptedResponse(
      {required this.text, required this.chips, required this.extras});
  final String text;
  final List<String> chips;
  final List<ButlerChunk> extras;
}
