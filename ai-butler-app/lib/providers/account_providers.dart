import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// 會員資訊（Requirement 3）。
final memberProfileProvider = FutureProvider<MemberProfile>((ref) {
  return ref.watch(accountRepositoryProvider).fetchProfile();
});
