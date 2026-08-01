import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/config/environment_config.dart';
import 'package:ai_butler_app/data/mock/mock_butler_ai_service.dart';
import 'package:ai_butler_app/domain/services/butler_ai_service.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// AI 管家服務的注入點（Requirement 13.10）。
final butlerAiServiceProvider = Provider<ButlerAiService>((ref) {
  final config = ref.watch(environmentConfigProvider);
  return switch (config.aiSource) {
    DataSource.mock => MockButlerAiService(),
    // TODO(backend): 接上 BackendProxyButlerAiService（呼叫隊友後端，後端接 Bedrock）
    DataSource.remote => MockButlerAiService(),
  };
});
