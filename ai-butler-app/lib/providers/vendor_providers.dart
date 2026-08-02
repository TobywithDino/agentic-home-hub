import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/config/api_endpoints.dart';
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

/// [vendorServicesProvider] 的查詢參數。
///
/// 需要自訂相等性：family provider 拿它當 key，若沒有 == / hashCode，
/// 每次 rebuild 都會被當成新的 key 而重複打 API。
@immutable
class VendorServicesQuery {
  const VendorServicesQuery({required this.vendorId, this.serviceType});

  final int vendorId;

  /// 服務類型代碼。null 代表不篩選（顯示該廠商全部服務）。
  final String? serviceType;

  @override
  bool operator ==(Object other) =>
      other is VendorServicesQuery &&
      other.vendorId == vendorId &&
      other.serviceType == serviceType;

  @override
  int get hashCode => Object.hash(vendorId, serviceType);
}

/// 取得某廠商底下的服務項目（用於服務切換）。
///
/// 帶 [VendorServicesQuery.serviceType] 時只回該類型：使用者是從某個服務
/// 類型點進來的，就只該看到那個類型的服務，不該混進該商家其他類型的項目。
final vendorServicesProvider = FutureProvider.autoDispose
    .family<List<VendorServiceItem>, VendorServicesQuery>((ref, query) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.get<List<dynamic>>(
    ApiEndpoints.vendorServices(query.vendorId, serviceType: query.serviceType),
  );
  final data = response.data ?? [];
  return data.map((json) {
    final map = json as Map<String, dynamic>;
    return VendorServiceItem(
      id: map['id'] as int? ?? 0,
      serviceVendorId: map['service_vendor_id'] as int? ?? query.vendorId,
      type: map['type'] as String? ?? '',
      name: map['name'] as String? ?? '',
      imgUrl: map['img_url'] as String? ?? '',
      description: map['description'] as String? ?? '',
      formId: map['form_id'] as int?,
    );
  }).toList();
});

/// 廠商底下的單一服務項目。
class VendorServiceItem {
  const VendorServiceItem({
    required this.id,
    required this.serviceVendorId,
    required this.type,
    required this.name,
    this.imgUrl = '',
    this.description = '',
    this.formId,
  });

  final int id;
  final int serviceVendorId;
  final String type;
  final String name;
  final String imgUrl;
  final String description;
  final int? formId;
}
