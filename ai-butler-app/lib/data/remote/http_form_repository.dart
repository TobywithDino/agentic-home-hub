import 'package:dio/dio.dart';

import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 真實後端的表單取得實作。
///
/// BFF (8100) 目前未暴露表單端點，但 DB Access API (8000) 提供：
/// - `GET /vendors/{service_vendor_id}/forms/full` — 取得廠商所有啟用表單
/// - `GET /forms/{form_id}/full` — 取得單一表單完整結構
///
/// 這裡直接呼叫 DB Access API 取得表單定義。
class HttpFormRepository implements FormRepository {
  HttpFormRepository({required this.dbAccessBaseUrl});

  /// DB Access API base URL（port 8000）。
  final String dbAccessBaseUrl;

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: dbAccessBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  @override
  Future<FormDefinition> fetchForm(int formId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/forms/$formId/full',
      );

      final body = response.data;
      if (body == null) {
        throw const ServerError(
          message: '表單資料回應為空',
          endpoint: 'GET /forms/{id}/full',
        );
      }

      return _mapFormDefinition(body);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw NetworkError(endpoint: 'GET /forms/$formId/full', cause: e);
      }
      throw ServerError(
        message: '取得表單失敗',
        endpoint: 'GET /forms/$formId/full',
        statusCode: e.response?.statusCode,
        cause: e,
      );
    }
  }

  FormDefinition _mapFormDefinition(Map<String, dynamic> json) {
    final groups = <FormGroup>[];
    final rawGroups = (json['groups'] as List<dynamic>?) ?? [];

    for (final g in rawGroups) {
      final gMap = g as Map<String, dynamic>;
      final topics = <FormTopic>[];
      final rawTopics = (gMap['topics'] as List<dynamic>?) ?? [];

      for (final t in rawTopics) {
        final tMap = t as Map<String, dynamic>;
        topics.add(_mapTopic(tMap));
      }

      groups.add(FormGroup(
        id: gMap['id'] as int? ?? 0,
        name: gMap['name'] as String? ?? '',
        sort: gMap['sort'] as int? ?? 0,
        topics: topics,
      ));
    }

    return FormDefinition(
      formId: json['id'] as int? ?? json['form_id'] as int? ?? 0,
      serviceVendorId: json['service_vendor_id'] as int? ?? 0,
      serviceId: json['service_id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '1',
      subType: json['sub_type'] as String? ?? '1',
      introContent: json['intro_content'] as String? ?? '',
      noticeContent: json['notice_content'] as String? ?? '',
      termsContent: json['terms_content'] as String? ?? '',
      groups: groups,
    );
  }

  FormTopic _mapTopic(Map<String, dynamic> json) {
    final rawOptions = (json['options'] as List<dynamic>?) ?? [];
    final options = rawOptions.map((o) {
      final oMap = o as Map<String, dynamic>;
      return TopicOption(
        id: oMap['id'] as int? ?? 0,
        optionName: oMap['option_name'] as String? ?? oMap['name'] as String? ?? '',
        unitPrice: (oMap['unit_price'] as num?)?.toInt() ?? 0,
        unit: oMap['unit'] as String? ?? '',
        isQuantity: oMap['is_quantity'] == '1' || oMap['is_quantity'] == true,
        minQuantity: (oMap['min_quantity'] as num?)?.toInt() ?? 1,
        maxQuantity: (oMap['max_quantity'] as num?)?.toInt() ?? 1,
        isQuotedSeparately: oMap['is_quoted_separately'] == '1' || oMap['is_quoted_separately'] == true,
        remark: oMap['remark'] as String? ?? '',
        sort: (oMap['sort'] as num?)?.toInt() ?? 0,
      );
    }).toList();

    final rawMedias = (json['medias'] as List<dynamic>?) ?? [];
    final medias = rawMedias.map((m) {
      final mMap = m as Map<String, dynamic>;
      return TopicMedia(
        id: mMap['id'] as int? ?? 0,
        imgUrl: mMap['img_url'] as String? ?? '',
        sort: (mMap['sort'] as num?)?.toInt() ?? 0,
      );
    }).toList();

    final typeCode = json['type'] as String? ?? '';

    return FormTopic(
      topicId: json['id'] as int? ?? json['topic_id'] as int? ?? 0,
      type: TopicType.fromCode(typeCode),
      title: json['title'] as String? ?? '',
      remark: json['remark'] as String? ?? '',
      isRequired: json['is_required'] == '1' || json['is_required'] == true,
      sort: (json['sort'] as num?)?.toInt() ?? 0,
      isNumberOnly: json['is_number_only'] == '1' || json['is_number_only'] == true,
      minMedias: (json['min_medias'] as num?)?.toInt(),
      maxMedias: (json['max_medias'] as num?)?.toInt(),
      specifiedMedias: (json['specified_medias'] as num?)?.toInt(),
      startDateOffsetDays: (json['start_date_offset_days'] as num?)?.toInt(),
      endDateOffsetDays: (json['end_date_offset_days'] as num?)?.toInt(),
      options: options,
      medias: medias,
    );
  }
}
