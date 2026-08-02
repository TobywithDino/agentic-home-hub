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

  /// tool 名稱轉成給使用者看的文案。
  /// 來源是 agent_service/app/AiButler/tools.py 的 @tool(name=...)，加新 tool 時補這裡。
  String get label => switch (name) {
        'find_service_vendors' => '正在搜尋服務商…',
        'list_service_labels' => '正在查可用的篩選條件…',
        'show_vendor_list' => '整理結果中…',
        'list_vendor_services' => '正在查這家提供的服務…',
        'get_service_form' => '正在讀取表單題目…',
        'get_service_reviews' => '正在查評價…',
        'get_my_profile' => '正在讀取你的聯絡資訊…',
        'list_my_orders' => '正在查你的訂單…',
        'propose_submission' => '正在整理諮詢單…',
        'propose_review' => '正在整理評價內容…',
        'propose_profile_update' => '正在整理要修改的資料…',
        _ => '處理中…',
      };
}

/// 要求 App 用原生元件渲染一段結構化內容。
final class UiComponent extends AgentEvent {
  final String component;
  final Map<String, dynamic> payload;
  const UiComponent({required this.component, required this.payload});
}

/// 草稿就緒。這是「直接送出 / 教我操作」兩顆按鈕的觸發點。
///
/// 對應 agent_service/app/AiButler/schemas.py 的 OrderDraft.to_event_payload。
/// 有三種 [kind]：`feedback`(諮詢單) / `review`(訂單評價) / `profile`(個人資料)。
/// 只有 feedback 有 [formId]、[serviceId]，另兩種是 null。
final class OrderDraftEvent extends AgentEvent {
  final String draftId;
  final String kind;
  final String kindLabel;
  final String summary;

  /// 送出時要用的 HTTP method 與 bff_server 路徑。
  ///
  /// 草稿自己描述「該送去哪」，App 重播 method + path + payload 即可，
  /// 不用拿 kind 去 switch 出路徑 —— agent 新增草稿類型時前端不必跟著改。
  final String submitMethod;
  final String submitPath;

  /// 欄位與 [submitPath] 那支端點的 request body 一致,可以直接轉送。
  final Map<String, dynamic> payload;

  /// 只有諮詢單草稿才有；評價/個資草稿是 null。
  final int? serviceId;
  final int? formId;

  /// 服務類型代碼（`cms_homepage_service.type`），導覽藍圖用它對應。
  /// 評價/個資草稿沒有服務類型，是 null。
  final String? serviceType;
  final String serviceTypeLabel;

  final DateTime expiresAt;

  const OrderDraftEvent({
    required this.draftId,
    required this.kind,
    required this.kindLabel,
    required this.summary,
    required this.submitMethod,
    required this.submitPath,
    required this.payload,
    required this.expiresAt,
    this.serviceId,
    this.formId,
    this.serviceType,
    this.serviceTypeLabel = '',
  });

  factory OrderDraftEvent.fromJson(Map<String, dynamic> map) {
    final submit = (map['submit'] as Map?)?.cast<String, dynamic>() ?? const {};
    return OrderDraftEvent(
      draftId: map['draft_id'] as String,
      kind: map['kind'] as String? ?? 'feedback',
      kindLabel: map['kind_label'] as String? ?? '待確認內容',
      summary: map['summary'] as String? ?? '',
      submitMethod: submit['method'] as String? ?? 'POST',
      submitPath: submit['path'] as String? ?? '',
      payload: (map['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      serviceId: (map['service_id'] as num?)?.toInt(),
      formId: (map['form_id'] as num?)?.toInt(),
      serviceType: map['service_type'] as String?,
      serviceTypeLabel: map['service_type_label'] as String? ?? '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        ((map['expires_at'] as num? ?? 0) * 1000).round(),
      ),
    );
  }

  bool get expired => DateTime.now().isAfter(expiresAt);
}

final class AgentDone extends AgentEvent {
  const AgentDone();
}

final class AgentError extends AgentEvent {
  final String message;
  const AgentError(this.message);
}
