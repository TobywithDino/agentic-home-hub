import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/core/storage/draft_store.dart';
import 'package:ai_butler_app/domain/models/answer_value.dart';
import 'package:ai_butler_app/domain/models/form_answers.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// 表單定義（Requirement 7.1）。
final formDefinitionProvider =
    FutureProvider.autoDispose.family<FormDefinition, int>((ref, formId) {
  return ref.watch(formRepositoryProvider).fetchForm(formId);
});

/// 餐廳訂位可用容量上限。
///
/// 傳入 (serviceId, time)，回傳 `available_capacity`（int）；
/// API 失敗或 404 回傳 null 代表不限制。
/// serviceId 為 0 或 time 為空時不呼叫 API。
final capacityProvider = FutureProvider.autoDispose
    .family<int?, ({int serviceId, String time})>((ref, params) async {
  if (params.serviceId <= 0 || params.time.isEmpty) return null;
  final client = ref.watch(apiClientProvider);
  try {
    final resp = await client.get<dynamic>(
      ApiEndpoints.availableCapacity(params.serviceId),
      queryParameters: <String, dynamic>{'time': params.time},
    );
    final data = resp.data;
    if (data is Map<String, dynamic>) {
      final cap = data['available_capacity'];
      if (cap is int) return cap;
      if (cap is num) return cap.toInt();
    }
    return null;
  } catch (_) {
    return null;
  }
});

/// DraftStore provider。
final draftStoreProvider = Provider<DraftStore>((ref) {
  return DraftStore(ref.watch(sharedPreferencesProvider));
});

/// 單一表單的填寫狀態（依 formId 隔離，Requirement 8）。
class FormAnswersNotifier extends FamilyNotifier<FormAnswers, int> {
  @override
  FormAnswers build(int arg) => const FormAnswers();

  void setAnswer(int topicId, AnswerValue? value, {bool byUser = true}) {
    state = state.setAnswer(topicId, value, byUser: byUser);
  }

  void applyPrefill(Map<int, AnswerValue> prefill) {
    state = state.applyPrefill(prefill);
  }

  void reset() => state = state.clear();
}

final formAnswersProvider =
    NotifierProvider.family<FormAnswersNotifier, FormAnswers, int>(
  FormAnswersNotifier.new,
);
