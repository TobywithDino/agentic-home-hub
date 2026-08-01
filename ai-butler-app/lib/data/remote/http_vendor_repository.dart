import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/data/remote/api_client.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 真實後端的服務類別實作。
///
/// BFF 目前沒有直接的「取得所有服務類別」端點，
/// 但從 vendors endpoint 文件得知可用的 service_type：
/// "1"=一般居家清潔, "2"=家電清洗, "3"=包裹寄送,
/// "6"=餐廳訂位, "9"=美食外送, "10"=水電修繕, "11"=商城購物
///
/// 暫時以硬編碼類別清單 + 呼叫 vendors API 取得各類別服務商數回傳。
class HttpServiceCatalogRepository implements ServiceCatalogRepository {
  HttpServiceCatalogRepository(this._client);

  final ApiClient _client;

  /// BFF 文件定義的服務類別。
  static const List<_CategoryDef> _knownCategories = [
    _CategoryDef(type: '1', name: '一般居家清潔'),
    _CategoryDef(type: '2', name: '家電清洗'),
    _CategoryDef(type: '3', name: '包裹寄送'),
    _CategoryDef(type: '6', name: '餐廳訂位'),
    _CategoryDef(type: '9', name: '美食外送'),
    _CategoryDef(type: '10', name: '水電修繕'),
    _CategoryDef(type: '11', name: '商城購物'),
  ];

  @override
  Future<List<ServiceCategory>> fetchCategories() async {
    // 並行呼叫所有類別的 vendors API 取得 vendorCount，大幅加速載入
    final futures = _knownCategories.map((cat) async {
      int vendorCount = 0;
      try {
        final response = await _client.get<List<dynamic>>(
          ApiEndpoints.vendorsByServiceType(cat.type),
        );
        vendorCount = response.data?.length ?? 0;
      } catch (_) {
        // 若某類別取得失敗，仍回傳該類別但數量為 0
      }
      return ServiceCategory(
        serviceId: int.tryParse(cat.type) ?? 0,
        type: cat.type,
        name: cat.name,
        vendorCount: vendorCount,
      );
    });

    return Future.wait(futures);
  }
}

class _CategoryDef {
  const _CategoryDef({required this.type, required this.name});
  final String type;
  final String name;
}

/// 真實後端的服務商查詢實作。
class HttpVendorRepository implements VendorRepository {
  HttpVendorRepository(this._client);

  final ApiClient _client;

  @override
  Future<ResultPage<VendorSummary>> searchVendors(VendorQuery query) async {
    // BFF 以 service_type 作為路徑參數，而 VendorQuery 以 serviceId 表達
    final serviceType = query.serviceId?.toString() ?? '1';

    final queryParams = <String, dynamic>{};
    if (query.selectedTags.isNotEmpty) {
      queryParams['labels'] = query.selectedTags.join(',');
    }

    final response = await _client.get<List<dynamic>>(
      ApiEndpoints.vendorsByServiceType(serviceType),
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    final data = response.data ?? [];
    final vendors =
        data.map((json) => _mapVendor(json as Map<String, dynamic>)).toList();

    // 關鍵字客端篩選（BFF 端未提供全文搜尋）
    var filtered = vendors;
    if (query.keyword.trim().isNotEmpty) {
      final kw = query.keyword.trim().toLowerCase();
      filtered = vendors
          .where((v) =>
              v.name.toLowerCase().contains(kw) ||
              v.description.toLowerCase().contains(kw))
          .toList();
    }

    // 分頁
    final start = (query.page - 1) * query.pageSize;
    final end = (start + query.pageSize).clamp(0, filtered.length);
    final items = start >= filtered.length
        ? <VendorSummary>[]
        : filtered.sublist(start, end);

    return ResultPage<VendorSummary>(
      items: items,
      totalCount: filtered.length,
      hasMore: end < filtered.length,
      capabilities: const VendorCapabilities(
        hasRating: false,
        hasPriceRange: false,
        hasAvailability: false,
      ),
    );
  }

  @override
  Future<VendorDetail> fetchVendorDetail(int vendorId) async {
    // 並行查詢所有類別，找到包含此 vendorId 的結果
    const types = ['1', '2', '3', '6', '9', '10', '11'];
    final futures = types.map((type) async {
      try {
        final response = await _client.get<List<dynamic>>(
          ApiEndpoints.vendorsByServiceType(type),
        );
        final data = response.data ?? [];
        for (final json in data) {
          final map = json as Map<String, dynamic>;
          if (map['id'] == vendorId) {
            return _mapVendorDetail(map, type);
          }
        }
      } catch (_) {}
      return null;
    });

    final results = await Future.wait(futures);
    final detail = results.firstWhere((d) => d != null, orElse: () => null);
    if (detail != null) return detail;

    throw const ServerError(
      message: '找不到服務商',
      endpoint: 'fetchVendorDetail',
    );
  }

  VendorSummary _mapVendor(Map<String, dynamic> json) {
    final services = (json['matched_services'] as List<dynamic>?) ?? [];
    final firstService = services.isNotEmpty
        ? services.first as Map<String, dynamic>
        : <String, dynamic>{};

    return VendorSummary(
      vendorId: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      imgUrl: firstService['img_url'] as String? ?? '',
      serviceTags: const <String>[],
    );
  }

  VendorDetail _mapVendorDetail(Map<String, dynamic> json, String serviceType) {
    final services = (json['matched_services'] as List<dynamic>?) ?? [];
    final firstService = services.isNotEmpty
        ? services.first as Map<String, dynamic>
        : <String, dynamic>{};

    return VendorDetail(
      vendorId: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      imgUrl: firstService['img_url'] as String? ?? '',
      formId: firstService['form_id'] as int? ?? 0,
      serviceId: firstService['id'] as int? ?? (int.tryParse(serviceType) ?? 0),
      introContent: firstService['description'] as String? ??
          json['description'] as String? ??
          '',
    );
  }
}
