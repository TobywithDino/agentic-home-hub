import 'package:flutter_riverpod/flutter_riverpod.dart';

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
