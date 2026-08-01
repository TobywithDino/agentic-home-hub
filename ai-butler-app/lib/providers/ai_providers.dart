import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/config/environment_config.dart';
import 'package:ai_butler_app/data/mock/mock_butler_ai_service.dart';
import 'package:ai_butler_app/data/remote/http_butler_ai_service.dart';
import 'package:ai_butler_app/domain/services/butler_ai_service.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// AI 管家服務的注入點（Requirement 13.10）。
///
/// `AI_SOURCE=remote` 時走 [HttpButlerAiService]，它打 bff_server 的
/// `/app-api/butler/chat`（SSE），由 bff_server 代為呼叫 AgentCore Runtime
/// —— 前端不需要也不應該持有 AWS 憑證。
///
/// mock 實例同時當 `classify` / `prefill` / `explainTopic` 的備援，
/// 因為那三個能力目前由 agent 在對話流程中一併完成，沒有獨立端點。
final butlerAiServiceProvider = Provider<ButlerAiService>((ref) {
  final config = ref.watch(environmentConfigProvider);

  return switch (config.aiSource) {
    DataSource.mock => MockButlerAiService(),
    DataSource.remote => HttpButlerAiService(
        baseUrl: config.effectiveBaseUrl,
        getAccountId: () => _readAccountId(ref),
        fallback: MockButlerAiService(),
      ),
  };
});

/// 從本機儲存讀取已登入的 account id。
///
/// 跟 repository_providers 的 `_readAccountId` 同一套做法：目前 BFF 沒有
/// token 機制，身分就是這個 UUID（見 steering 的「已知限制」）。
String _readAccountId(Ref ref) {
  try {
    final prefs = ref.read(sharedPreferencesProvider);
    return prefs.getString('session.inbr_account_id') ?? '';
  } catch (_) {
    return '';
  }
}
