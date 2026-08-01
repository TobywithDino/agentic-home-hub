/// 跟後端 `POST /agent/chat` 對接的 SSE 客戶端。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'agent_event.dart';

class AgentClient {
  AgentClient({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;

  /// 每次請求現取 token,避免拿到過期的快取值。
  final Future<String> Function() tokenProvider;

  final http.Client _http;

  /// 送一則使用者訊息,回傳事件串流。
  ///
  /// 呼叫端要 listen 到 [AgentDone] 或 [AgentError] 才算一輪結束。
  Stream<AgentEvent> send({
    required String sessionId,
    required String message,
  }) async* {
    final token = await tokenProvider();
    final request = http.Request('POST', Uri.parse('$baseUrl/agent/chat'))
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode({'session_id': sessionId, 'message': message});

    final response = await _http.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      yield AgentError('伺服器錯誤 ${response.statusCode}: $body');
      return;
    }

    // 後端每個事件是單行 `data: {...}` 加一個空行,所以逐行解析就夠。
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;

      final event = AgentEvent.parse(payload);
      if (event == null) continue;

      yield event;
      if (event is AgentDone || event is AgentError) return;
    }
  }

  /// 教學模式重新進入畫面時,把草稿撈回來預填表單。
  Future<OrderDraftEvent> fetchDraft(String draftId) async {
    final token = await tokenProvider();
    final response = await _http.get(
      Uri.parse('$baseUrl/agent/draft/$draftId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw StateError('草稿不存在或已過期');
    }
    return OrderDraftEvent.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  void dispose() => _http.close();
}
