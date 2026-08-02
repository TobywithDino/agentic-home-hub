import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/data/remote/api_client.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 真實後端的服務類別實作。
///
/// 只走 APP 端接點：對每個服務類型並行呼叫
/// `GET /app-api/service-types/{service_type}/vendors`，用回應裡的
/// `matched_services`（真實 `cms_homepage_service` 資料）統計服務商數與取代表圖。
///
/// 沒有廠商的類型不會出現在首頁。刻意不用 `/merchant-api/services`：
/// 那是商家後台接點，APP 端不該依賴。
class HttpServiceCatalogRepository implements ServiceCatalogRepository {
  HttpServiceCatalogRepository(this._client);

  final ApiClient _client;

  /// service type → 顯示名稱對照。
  ///
  /// 後端沒有「服務類型主檔」端點可查名稱，只能在前端維護這張表
  /// （對照 README 的 service type 定義）。未知代碼會顯示原始代碼而不隱藏。
  static const Map<String, String> _typeNames = <String, String>{
    '1': '一般居家清潔',
    '2': '家電清洗',
    '3': '包裹寄送',
    '6': '餐廳訂位',
    '9': '美食外送',
    '10': '水電修繕',
    '11': '商城購物',
  };

  @override
  Future<List<ServiceCategory>> fetchCategories() async {
    final futures = _typeNames.keys.map((type) async {
      try {
        final response = await _client.get<List<dynamic>>(
          ApiEndpoints.vendorsByServiceType(type),
        );
        return (type: type, vendors: response.data ?? const <dynamic>[]);
      } catch (_) {
        // 單一類型失敗不影響其他類型，該類型視為無廠商。
        return (type: type, vendors: const <dynamic>[]);
      }
    });

    final results = await Future.wait(futures);

    final categories = <ServiceCategory>[];
    for (final result in results) {
      // 沒有廠商的類型也要顯示：使用者需要看到平台提供哪些服務類型，
      // 點進去再由列表頁呈現「找不到符合條件的服務商」。

      // 從 matched_services 取第一張有效圖片當類別代表圖。
      String imgUrl = '';
      for (final vendor in result.vendors) {
        if (vendor is! Map) continue;
        final services = vendor['matched_services'];
        if (services is! List) continue;
        for (final service in services) {
          if (service is! Map) continue;
          final url = service['img_url'];
          if (url is String && url.isNotEmpty) {
            imgUrl = url;
            break;
          }
        }
        if (imgUrl.isNotEmpty) break;
      }

      categories.add(ServiceCategory(
        serviceId: int.tryParse(result.type) ?? 0,
        type: result.type,
        name: _typeNames[result.type] ?? '服務類型 ${result.type}',
        imgUrl: imgUrl,
        vendorCount: result.vendors.length,
      ));
    }

    return categories;
  }
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
    // 用 /app-api/vendors/{id}/services 取得該廠商的所有服務
    try {
      final response = await _client.get<List<dynamic>>(
        ApiEndpoints.vendorServices(vendorId),
      );
      final services = response.data ?? [];
      if (services.isNotEmpty) {
        final firstService = services.first as Map<String, dynamic>;
        return VendorDetail(
          vendorId: vendorId,
          name: firstService['name'] as String? ?? '',
          description: firstService['description'] as String? ?? '',
          imgUrl: firstService['img_url'] as String? ?? '',
          formId: firstService['form_id'] as int? ?? 0,
          serviceId: firstService['id'] as int? ?? 0,
          introContent: firstService['description'] as String? ?? '',
        );
      }
    } catch (_) {}

    // fallback: 遍歷 service-types 找 vendor
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
