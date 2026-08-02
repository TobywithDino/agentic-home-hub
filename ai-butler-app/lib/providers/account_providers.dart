import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';
import 'package:ai_butler_app/providers/session_providers.dart';

/// 會員資訊（Requirement 3）。
///
/// 同 [orderInboxProvider]：watch account id 讓登入/登出後自動重取，
/// 避免快取住未登入時的失敗結果。
final memberProfileProvider = FutureProvider<MemberProfile>((ref) {
  final accountId =
      ref.watch(authNotifierProvider.select((s) => s.session?.inbrAccountId));
  if (accountId == null || accountId.isEmpty) {
    return const MemberProfile(name: '', mobile: '');
  }
  return ref.watch(accountRepositoryProvider).fetchProfile();
});
