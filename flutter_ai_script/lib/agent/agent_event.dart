/// Agent SSE 事件模型。
///
/// 這裡的 `type` 字串必須跟後端 `agent/schemas.py` 的 EventType 一致。
library;

import 'dart:convert';

sealed class AgentEvent {
  const AgentEvent();

  static AgentEvent? parse(String jsonLine) {
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(jsonLine) as Map<String, dynamic>;
    } on FormatException {
      return null; // 忽略壞掉的 frame,不要讓整個串流掛掉
    }

    return switch (map['type'] as String?) {
      'text_delta' => TextDelta(map['text'] as String? ?? ''),
      'tool_start' => ToolStart(map['name'] as String? ?? ''),
      'ui' => UiComponent(
          component: map['component'] as String? ?? '',
          payload: (map['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      'draft' => OrderDraftEvent.fromJson(map),
      'done' => const AgentDone(),
      'error' => AgentError(map['message'] as String? ?? '發生未知錯誤'),
      _ => null,
    };
  }
}

/// 助理文字的增量輸出,append 到當前訊息尾端。
final class TextDelta extends AgentEvent {
  final String text;
  const TextDelta(this.text);
}

/// 開始執行某個 tool,用來顯示「正在查詢餐廳…」之類的狀態。
final class ToolStart extends AgentEvent {
  final String name;
  const ToolStart(this.name);

  /// tool 名稱轉成給使用者看的文案。後端加新 tool 時記得補這裡。
  String get label => switch (name) {
        'search_restaurants' => '正在搜尋餐廳…',
        'get_available_slots' => '正在查可訂位時段…',
        'get_my_profile' => '正在讀取你的聯絡資訊…',
        'show_restaurant_list' => '整理結果中…',
        'propose_order' => '正在準備訂單…',
        _ => '處理中…',
      };
}

/// 要求 App 用原生元件渲染一段結構化內容。
final class UiComponent extends AgentEvent {
  final String component;
  final Map<String, dynamic> payload;
  const UiComponent({required this.component, required this.payload});
}

/// 訂單草稿就緒。這是「直接送出 / 教我操作」兩顆按鈕的觸發點。
final class OrderDraftEvent extends AgentEvent {
  final String draftId;
  final String service;
  final String summary;

  /// 欄位與既有下單 API 的 request body 一致,可以直接轉送。
  final Map<String, dynamic> payload;
  final DateTime expiresAt;

  const OrderDraftEvent({
    required this.draftId,
    required this.service,
    required this.summary,
    required this.payload,
    required this.expiresAt,
  });

  factory OrderDraftEvent.fromJson(Map<String, dynamic> map) => OrderDraftEvent(
        draftId: map['draft_id'] as String,
        service: map['service'] as String,
        summary: map['summary'] as String? ?? '',
        payload: (map['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          ((map['expires_at'] as num? ?? 0) * 1000).round(),
        ),
      );

  bool get expired => DateTime.now().isAfter(expiresAt);
}

final class AgentDone extends AgentEvent {
  const AgentDone();
}

final class AgentError extends AgentEvent {
  final String message;
  const AgentError(this.message);
}
