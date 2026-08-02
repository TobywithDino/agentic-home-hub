import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:ai_butler_app/data/remote/sse_client.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/services/butler_ai_service.dart';

/// 真實 AI 管家：打 bff_server 的 `/app-api/butler/chat`（SSE）。
///
/// 為什麼不直接呼叫 AgentCore：
/// AgentCore Runtime 只接受 SigV4(IAM) 驗證，前端拿不到 AWS 憑證，也不該拿。
/// 所以 bff_server 用 EC2 instance role 代為呼叫，前端只看到一支普通 SSE 端點。
///
/// 為什麼用 http + fetch_client 而不是專案既有的 dio：
/// dio 在 Web 上走 XMLHttpRequest，不支援漸進式讀取 byte stream，
/// `ResponseType.stream` 在瀏覽器拿不到資料並拋例外（原生平台正常，
/// 所以會出現「curl 測得過、App 卻連線失敗」）。fetch_client 走 Fetch API
/// 的 ReadableStream 才有真串流。詳見 sse_client_web.dart。
///
/// session 的兩層記憶：
/// - `sessionId` 同一個聊天室固定不變 → agent 記得這段對話的前文
/// - `inbr_account_id` 區分使用者 → 跨 session 的長期偏好（AgentCore Memory）
class HttpButlerAiService implements ButlerAiService {
  HttpButlerAiService({
    required String baseUrl,
    required this.getAccountId,
    ButlerAiService? fallback,
    http.Client? client,
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _fallback = fallback,
        _client = client ?? createSseClient();

  final String _baseUrl;
  final http.Client _client;
  final String Function() getAccountId;

  /// `classify` / `prefill` / `explainTopic` 這三個能力目前由 agent 在對話中
  /// 一併完成，沒有獨立端點。傳入 mock 當備援，讓依賴它們的畫面不會壞掉。
  final ButlerAiService? _fallback;

  static const _uuid = Uuid();

  /// 模型思考加多次 tool 往返可能超過一分鐘，不能用一般 API 的 20 秒逾時。
  static const _timeout = Duration(minutes: 3);

  /// 同一個 service 實例代表同一個聊天室，session id 存在這裡。
  ///
  /// **由客戶端自己產生**，不依賴伺服器回的 `X-Session-Id`。
  /// 原因：瀏覽器預設不讓 JS 讀自訂回應標頭（要 CORS 的
  /// `Access-Control-Expose-Headers` 才行），Flutter Web 上讀到的是 null，
  /// 結果每輪都變成新對話、AI 管家完全沒有前文記憶。這個 bug 用 curl 測不出來。
  ///
  /// 「這是哪一段對話」本來就該由客戶端決定，不需要往返一趟才知道。
  String? _sessionId;

  /// AgentCore 要求 runtimeSessionId 至少 33 字元，太短會被拒絕。
  /// UUID v4 含連字號是 36 字元，加前綴後更長，不會踩到邊界。
  String _newSessionId() => 'app-${_uuid.v4()}';

  /// 開新對話（清掉聊天室時呼叫），下一次送出會用新的 session。
  void resetSession() => _sessionId = null;

  void dispose() => _client.close();

  @override
  Stream<ButlerChunk> send(String message) async* {
    final accountId = getAccountId();
    if (accountId.isEmpty) {
      yield const Failed('請先登入再使用 AI 管家');
      yield const Done();
      return;
    }

    // 第一輪就決定 session id 並固定下來，之後每輪都送同一個，
    // agent 才能從 AgentCore Memory 撈到這段對話的前文。
    _sessionId ??= _newSessionId();

    // 整個流程包在 try 裡：所有錯誤都轉成 Failed chunk。
    // 讓 stream 拋出例外的話，聊天室會走 onError 分支顯示「連線失敗」，
    // 使用者看不到具體原因，也失去我們寫好的錯誤訊息。
    var sawDone = false;
    try {
      final request = http.Request('POST', Uri.parse('$_baseUrl/app-api/butler/chat'))
        // fetch_client 把 persistentConnection 對應到 Fetch 的 keepalive，
        // 而 keepalive 是給「短命、可超出頁面生命週期」的請求用的，
        // 還有 64KiB 上限。SSE 是長時間開著的串流，關掉才符合語意。
        ..persistentConnection = false
        ..headers.addAll(<String, String>{
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(<String, dynamic>{
          'message': message,
          'inbr_account_id': accountId,
          'session_id': _sessionId,
        });

      final response = await _client.send(request).timeout(_timeout);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        if (kDebugMode) {
          debugPrint('[butler] HTTP ${response.statusCode}: $body');
        }
        yield Failed(_messageForStatus(response.statusCode));
        yield const Done();
        return;
      }

      // 伺服器若換了 session id 就以它為準（正常情況會跟送出的一致）。
      // Web 上這個標頭要 bff_server 設 expose_headers 才讀得到；
      // 讀不到也沒關係，id 是客戶端產生的，本來就已經固定。
      final assigned = response.headers['x-session-id'];
      if (assigned != null && assigned.isNotEmpty && assigned != _sessionId) {
        if (kDebugMode) debugPrint('[butler] 伺服器改用 session id: $assigned');
        _sessionId = assigned;
      }

      await for (final line in _sseLines(response.stream)) {
        for (final chunk in _mapEvent(line)) {
          if (chunk is Done) sawDone = true;
          yield chunk;
        }
      }
    } on TimeoutException {
      yield const Failed('AI 管家回應逾時，請重試');
    } catch (error, stack) {
      if (kDebugMode) debugPrint('[butler] 串流失敗: $error\n$stack');
      yield const Failed('連不上 AI 管家，請確認網路後重試');
    }

    // 伺服器沒送 done 就斷線時補一個，否則 UI 會一直停在串流中狀態
    if (!sawDone) yield const Done();
  }

  /// 把位元組流切成一行行的 SSE payload（去掉 `data: ` 前綴）。
  ///
  /// 不能假設一個 chunk 剛好是一筆事件 —— TCP 會任意切割，
  /// 所以要自己用緩衝區累積到換行才算一行。
  Stream<String> _sseLines(Stream<List<int>> byteStream) async* {
    var buffer = '';
    await for (final bytes in byteStream) {
      buffer += utf8.decode(bytes, allowMalformed: true);
      while (true) {
        final index = buffer.indexOf('\n');
        if (index < 0) break;
        final line = buffer.substring(0, index).trim();
        buffer = buffer.substring(index + 1);
        if (line.startsWith('data:')) {
          final payload = line.substring(5).trim();
          if (payload.isNotEmpty) yield payload;
        }
      }
    }
    final tail = buffer.trim();
    if (tail.startsWith('data:')) {
      final payload = tail.substring(5).trim();
      if (payload.isNotEmpty) yield payload;
    }
  }

  /// agent 事件協定 → app 的 ButlerChunk。
  ///
  /// 對應關係（agent_service/app/AiButler/schemas.py 為來源）：
  ///   text_delta → TextDelta
  ///   ui/vendor_list → 每個服務商一張 VendorCard
  ///   draft → PrefillCard（草稿摘要卡，點下去進表單）
  ///   done → Done
  ///   error → Failed
  ///   tool_start → 不對應（UI 沒有這個狀態，忽略即可）
  Iterable<ButlerChunk> _mapEvent(String jsonLine) {
    Map<String, dynamic> event;
    try {
      event = jsonDecode(jsonLine) as Map<String, dynamic>;
    } on FormatException {
      if (kDebugMode) debugPrint('[butler] 無法解析事件: $jsonLine');
      return const <ButlerChunk>[];
    }

    switch (event['type'] as String?) {
      case 'text_delta':
        final text = event['text'] as String? ?? '';
        return text.isEmpty
            ? const <ButlerChunk>[]
            : <ButlerChunk>[TextDelta(text)];

      case 'ui':
        return _mapUiComponent(event);

      case 'draft':
        return _mapDraft(event);

      case 'done':
        return const <ButlerChunk>[Done()];

      case 'error':
        return <ButlerChunk>[
          Failed(event['message'] as String? ?? 'AI 管家回應失敗'),
        ];

      case 'tool_start':
      default:
        return const <ButlerChunk>[];
    }
  }

  /// draft 事件 → 對應的確認卡。
  ///
  /// agent 有三種草稿（schemas.py 的 DraftKind）：
  ///   feedback → 諮詢單，有表單可以帶使用者去填，映射成 PrefillCard
  ///   review   → 訂單評價
  ///   profile  → 個人資料
  /// 後兩者沒有表單，映射成通用的 DraftCard。
  ///
  /// 不認得的 kind 一律走 DraftCard 而不是丟掉：agent 之後新增草稿類型時，
  /// 使用者至少還看得到摘要，不會整張卡片人間蒸發。
  Iterable<ButlerChunk> _mapDraft(Map<String, dynamic> event) {
    final payload =
        (event['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final kind = event['kind'] as String? ?? 'feedback';

    final submit = (event['submit'] as Map?)?.cast<String, dynamic>() ?? const {};

    if (kind == 'feedback') {
      final content =
          (payload['feedback_content'] as Map?)?.cast<String, dynamic>() ??
              const {};
      final formId = _asInt(event['form_id']) ?? _asInt(payload['form_id']);
      final serviceId =
          _asInt(event['service_id']) ?? _asInt(payload['service_id']);
      if (formId == null || serviceId == null) {
        if (kDebugMode) {
          debugPrint('[butler] feedback 草稿缺 form_id/service_id，已忽略');
        }
        return const <ButlerChunk>[];
      }
      return <ButlerChunk>[
        PrefillCard(
          serviceId: serviceId,
          formId: formId,
          filledCount: content.length,
          // agent 端已驗證必填題都齊了才會產生草稿，所以這裡是 0。
          remainingRequired: 0,
          summary: event['summary'] as String? ?? '已為你整理好表單內容',
          draftId: event['draft_id'] as String? ?? '',
          vendorId: _asInt(event['vendor_id']) ?? 0,
          serviceType: event['service_type'] as String? ?? '',
          answers: _parseFeedbackAnswers(content),
          payload: payload,
          submitMethod: submit['method'] as String? ?? 'POST',
          submitPath: submit['path'] as String? ?? '/app-api/feedbacks',
        ),
      ];
    }

    final draftId = event['draft_id'] as String?;
    final path = submit['path'] as String?;
    if (draftId == null || path == null) {
      if (kDebugMode) {
        debugPrint('[butler] $kind 草稿缺 draft_id/submit.path，已忽略');
      }
      return const <ButlerChunk>[];
    }

    return <ButlerChunk>[
      DraftCard(
        draftId: draftId,
        kind: kind,
        kindLabel: event['kind_label'] as String? ?? '待確認內容',
        summary: event['summary'] as String? ?? '',
        submitMethod: submit['method'] as String? ?? 'POST',
        submitPath: path,
        payload: payload,
      ),
    ];
  }

  /// `feedback_content` → `topic_id` 對答案文字。
  ///
  /// agent 端的結構是 `{"<topic_id>": {"title": ..., "value": ...}}`（見
  /// tools.py 的 propose_submission）。key 是字串化的 topic_id，
  /// 所以要 parse 回 int 才能對上 `FormTopic.topicId`。
  /// 解不出來的 key 直接跳過，不要讓一筆壞資料毀掉整張草稿。
  static Map<int, String> _parseFeedbackAnswers(Map<String, dynamic> content) {
    final out = <int, String>{};
    content.forEach((key, raw) {
      final topicId = int.tryParse(key);
      if (topicId == null) return;
      final value = raw is Map ? raw['value'] : raw;
      if (value == null) return;
      out[topicId] = value.toString();
    });
    return out;
  }

  Iterable<ButlerChunk> _mapUiComponent(Map<String, dynamic> event) {
    if (event['component'] != 'vendor_list') return const <ButlerChunk>[];

    final payload =
        (event['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final vendors = payload['vendors'];
    if (vendors is! List) return const <ButlerChunk>[];

    final cards = <ButlerChunk>[];
    for (final raw in vendors) {
      if (raw is! Map) continue;
      final vendor = raw.cast<String, dynamic>();
      final id = _asInt(vendor['id']) ?? _asInt(vendor['vendor_id']);
      if (id == null) continue;
      cards.add(VendorCard(
        vendorId: id,
        name: vendor['name'] as String? ?? '服務商',
        description: vendor['description'] as String? ?? '',
      ));
    }
    return cards;
  }

  static int? _asInt(Object? value) => switch (value) {
        int v => v,
        String v => int.tryParse(v),
        num v => v.toInt(),
        _ => null,
      };

  String _messageForStatus(int status) {
    if (status == 422) return '訊息格式有問題，請換個說法';
    if (status == 404) return 'AI 管家服務尚未上線（端點不存在）';
    if (status >= 500) return 'AI 管家暫時無法回應，請稍後再試';
    return 'AI 管家回應失敗（HTTP $status）';
  }

  // ---------------------------------------------------------------------
  // 以下三個能力目前沒有獨立端點：agent 在對話流程中就一併處理掉了
  // （它會自己呼叫 get_service_form、逐題問使用者、最後產生草稿）。
  // 保留 fallback 讓仍呼叫這些方法的畫面不會壞掉。
  // ---------------------------------------------------------------------

  @override
  Future<IntentResult> classify(String utterance) {
    final fallback = _fallback;
    if (fallback == null) {
      throw UnsupportedError('classify 需要 fallback 實作');
    }
    return fallback.classify(utterance);
  }

  @override
  Future<PrefillResult> prefill(String utterance, FormDefinition definition) {
    final fallback = _fallback;
    if (fallback == null) {
      throw UnsupportedError('prefill 需要 fallback 實作');
    }
    return fallback.prefill(utterance, definition);
  }

  @override
  Future<String> explainTopic(FormTopic topic) {
    final fallback = _fallback;
    if (fallback == null) {
      throw UnsupportedError('explainTopic 需要 fallback 實作');
    }
    return fallback.explainTopic(topic);
  }
}
