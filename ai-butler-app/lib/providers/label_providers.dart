import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// 單一標籤。
class ServiceLabel {
  const ServiceLabel({required this.id, required this.name});

  final int id;
  final String name;
}

/// 依服務類型取得可用標籤清單。
///
/// `serviceType` 為 null 時回傳所有通用標籤。
final labelsProvider = FutureProvider.autoDispose
    .family<List<ServiceLabel>, String?>((ref, serviceType) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.get<List<dynamic>>(
    ApiEndpoints.labels(serviceType: serviceType),
  );
  final data = response.data ?? [];
  return data.map((json) {
    final map = json as Map<String, dynamic>;
    return ServiceLabel(
      id: map['id'] as int? ?? 0,
      name: map['name'] as String? ?? '',
    );
  }).toList();
});
