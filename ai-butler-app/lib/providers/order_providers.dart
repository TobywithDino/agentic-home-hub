import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// 我的諮詢單 + 我的訂單（Requirement 15.1）。
final orderInboxProvider = FutureProvider<OrderInbox>((ref) {
  return ref.watch(orderRepositoryProvider).fetchInbox();
});
