import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/services/butler_ai_service.dart';

/// 真實 AI 管家：打 bff_server 的 `/app-api/butler/chat`（SSE）。
///
/// 為什麼不直接呼叫 AgentCore：
/// AgentCore Runtime 只接受 SigV4(IAM) 驗證，前端拿不到 AWS 憑證，也不該拿。
/// 所以 bff_server 用 EC2 instance role 代為呼叫，前端只看到一支普通 SSE 端點。
///
/// session 的兩層記憶：
/// - `sessionId` 同一個聊天室固定不變 → agent 記得這段對話的前文
/// - `inbr_account_id` 區分使用者 → 跨 session 的長期偏好（AgentCore Memory）
class HttpButlerAiService implements ButlerAiService {
  HttpButlerAiService({
    required String baseUrl,
    required this.getAccountId,
    ButlerAiService? fallback,
    Dio? dio,
  })  : _fallback = fallback,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              // 串流會開很久，不能用一般的 receiveTimeout（20s）掐掉。
              // 模型思考 + 多次 tool 往返可能超過一分鐘。
              receiveTimeout: const Duration(minutes: 3),
            ));

  final Dio _dio;
  final String Function() getAccountId;

  /// `classify` / `prefill` / `explainTopic` 這三個能力目前由 agent 在對話中
  /// 一併完成，沒有獨立端點。傳入 mock 當備援，讓依賴它們的畫面不會壞掉。
  final ButlerAiService? _fallback;

  /// 同一個 service 實例代表同一個聊天室，所以 session id 存在這裡。
  /// 由伺服器在第一次回應時用 `X-Session-Id` 告知，之後每次都帶著走。
  String? _sessionId;

  /// 開新對話（清掉聊天室時呼叫），下一次送出會取得新的 session。
  void resetSession() => _sessionId = null;

  @override
  Stream<ButlerChunk> send(String message) async* {
    final accountId = getAccountId();
    if (accountId.isEmpty) {
      yield const Failed('請先登入再使用 AI 管家');
      yield const Done();
      return;
    }

    Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '/app-api/butler/chat',
        data: <String, dynamic>{
          'message': message,
          'inbr_account_id': accountId,
          if (_sessionId != null) 'session_id': _sessionId,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: <String, String>{'Accept': 'text/event-stream'},
        ),
      );
    } on DioException catch (error) {
      yield Failed(_messageOf(error));
      yield const Done();
      return;
    }

    // 伺服器可能產生新的 session id（首次對話或長度不足時），記下來延續對話
    final assigned = response.headers.value('x-session-id');
    if (assigned != null && assigned.isNotEmpty) {
      _sessionId = assigned;
    }

    final body = response.data;
    if (body == null) {
      yield const Failed('AI 管家沒有回應');
      yield const Done();
      return;
    }

    var sawDone = false;
    try {
      await for (final line in _sseLines(body.stream)) {
        for (final chunk in _mapEvent(line)) {
          if (chunk is Done) sawDone = true;
          yield chunk;
        }
      }
    } catch (error) {
      yield const Failed('連線中斷，請重試');
      yield const Done();
      return;
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
        return text.isEmpty ? const <ButlerChunk>[] : <ButlerChunk>[TextDelta(text)];

      case 'ui':
        return _mapUiComponent(event);

      case 'draft':
        final payload =
            (event['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
        final content =
            (payload['feedback_content'] as Map?)?.cast<String, dynamic>() ??
                const {};
        final formId = _asInt(event['form_id']) ?? _asInt(payload['form_id']);
        final serviceId =
            _asInt(event['service_id']) ?? _asInt(payload['service_id']);
        if (formId == null || serviceId == null) return const <ButlerChunk>[];
        return <ButlerChunk>[
          PrefillCard(
            serviceId: serviceId,
            formId: formId,
            filledCount: content.length,
            // agent 端已驗證必填題都齊了才會產生草稿，所以這裡是 0。
            remainingRequired: 0,
            summary: event['summary'] as String? ?? '已為你整理好表單內容',
          ),
        ];

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

  String _messageOf(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.connectionError =>
        '連不上 AI 管家，請確認網路後重試',
      DioExceptionType.receiveTimeout => 'AI 管家回應逾時，請重試',
      _ => 'AI 管家暫時無法回應，請稍後再試',
    };
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
