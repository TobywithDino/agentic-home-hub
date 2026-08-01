import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// 服務類別主檔（Requirement 4.7、4.16）。
final serviceCategoriesProvider = FutureProvider<List<ServiceCategory>>((ref) {
  return ref.watch(serviceCatalogRepositoryProvider).fetchCategories();
});
