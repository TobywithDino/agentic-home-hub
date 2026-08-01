import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// Vendor_List_Screen 的查詢條件狀態（Requirement 5）。
class VendorQueryNotifier extends Notifier<VendorQuery> {
  @override
  VendorQuery build() => const VendorQuery();

  void setQuery(VendorQuery query) => state = query;
}

final vendorQueryProvider =
    NotifierProvider<VendorQueryNotifier, VendorQuery>(VendorQueryNotifier.new);

final vendorSearchProvider =
    FutureProvider.autoDispose<ResultPage<VendorSummary>>((ref) {
  final query = ref.watch(vendorQueryProvider);
  return ref.watch(vendorRepositoryProvider).searchVendors(query);
});

final vendorDetailProvider =
    FutureProvider.autoDispose.family<VendorDetail, int>((ref, vendorId) {
  return ref.watch(vendorRepositoryProvider).fetchVendorDetail(vendorId);
});
