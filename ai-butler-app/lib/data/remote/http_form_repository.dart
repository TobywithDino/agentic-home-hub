import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/data/remote/api_client.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 真實後端的表單取得實作。
///
/// BFF (8100) 提供：
/// - `GET /app-api/forms/{form_id}/full` — 取得單一表單完整結構
///
/// 回傳格式：
/// ```json
/// {
///   "form": { "id": 9, "service_vendor_id": 1, ... },
///   "groups": [ { "id": 136, "form_id": 9, "name": "...", "sort": 0, ... } ],
///   "topics": [ { "id": 121, "form_group_id": 136, "type": "6", ... } ]
/// }
/// ```
/// topics 是平面陣列，每個 topic 用 `form_group_id` 關聯回所屬 group。
class HttpFormRepository implements FormRepository {
  HttpFormRepository(this._client);

  final ApiClient _client;

  @override
  Future<FormDefinition> fetchForm(int formId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/app-api/forms/$formId/full',
    );

    final body = response.data;
    if (body == null) {
      throw const ServerError(
        message: '表單資料回應為空',
        endpoint: 'GET /app-api/forms/{id}/full',
      );
    }

    return _mapFormDefinition(body);
  }

  FormDefinition _mapFormDefinition(Map<String, dynamic> json) {
    // BFF 回傳結構：form (主檔), groups (平面陣列), topics (平面陣列)
    final formJson = (json['form'] as Map<String, dynamic>?) ?? json;
    final rawGroups = (json['groups'] as List<dynamic>?) ?? [];
    final rawTopics = (json['topics'] as List<dynamic>?) ?? [];

    // 先把 topics 依 form_group_id 分組
    final topicsByGroup = <int, List<FormTopic>>{};
    for (final t in rawTopics) {
      final tMap = t as Map<String, dynamic>;
      final groupId = tMap['form_group_id'] as int? ?? 0;
      topicsByGroup.putIfAbsent(groupId, () => []);
      topicsByGroup[groupId]!.add(_mapTopic(tMap));
    }

    // 組裝 groups（每個 group 帶入對應的 topics）
    final groups = <FormGroup>[];
    for (final g in rawGroups) {
      final gMap = g as Map<String, dynamic>;
      final groupId = gMap['id'] as int? ?? 0;
      groups.add(FormGroup(
        id: groupId,
        name: gMap['name'] as String? ?? '',
        sort: gMap['sort'] as int? ?? 0,
        topics: topicsByGroup[groupId] ?? [],
      ));
    }

    // 若 rawGroups 為空但有 topics，建一個預設 group 放入所有 topics
    if (groups.isEmpty && rawTopics.isNotEmpty) {
      groups.add(FormGroup(
        id: 0,
        name: formJson['name'] as String? ?? '表單',
        sort: 0,
        topics: topicsByGroup.values.expand((t) => t).toList(),
      ));
    }

    return FormDefinition(
      formId: formJson['id'] as int? ?? 0,
      serviceVendorId: formJson['service_vendor_id'] as int? ?? 0,
      serviceId: formJson['service_id'] as int? ?? 0,
      name: formJson['name'] as String? ?? '',
      type: formJson['type'] as String? ?? '1',
      subType: formJson['sub_type'] as String? ?? '1',
      introContent: formJson['intro_content'] as String? ?? '',
      noticeContent: formJson['notice_content'] as String? ?? '',
      termsContent: formJson['terms_content'] as String? ?? '',
      groups: groups,
    );
  }

  FormTopic _mapTopic(Map<String, dynamic> json) {
    final rawOptions = (json['options'] as List<dynamic>?) ?? [];
    final options = rawOptions.map((o) {
      final oMap = o as Map<String, dynamic>;
      return TopicOption(
        id: oMap['id'] as int? ?? 0,
        optionName:
            oMap['option_name'] as String? ?? oMap['name'] as String? ?? '',
        unitPrice: (oMap['unit_price'] as num?)?.toInt() ?? 0,
        unit: oMap['unit'] as String? ?? '',
        isQuantity: oMap['is_quantity'] == '1' || oMap['is_quantity'] == true,
        minQuantity: (oMap['min_quantity'] as num?)?.toInt() ?? 1,
        maxQuantity: (oMap['max_quantity'] as num?)?.toInt() ?? 1,
        isQuotedSeparately: oMap['is_quoted_separately'] == '1' ||
            oMap['is_quoted_separately'] == true,
        remark: oMap['remark'] as String? ?? '',
        sort: (oMap['sort'] as num?)?.toInt() ?? 0,
      );
    }).toList();

    // BFF 回傳 "media" 欄位（非 "medias"）
    final rawMedias = (json['media'] as List<dynamic>?) ??
        (json['medias'] as List<dynamic>?) ??
        [];
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
      isNumberOnly:
          json['is_number_only'] == '1' || json['is_number_only'] == true,
      minMedias: (json['minimum_medias_upload'] as num?)?.toInt() ??
          (json['min_medias'] as num?)?.toInt(),
      maxMedias: (json['maximum_medias_upload'] as num?)?.toInt() ??
          (json['max_medias'] as num?)?.toInt(),
      specifiedMedias: (json['specified_medias_upload'] as num?)?.toInt() ??
          (json['specified_medias'] as num?)?.toInt(),
      startDateOffsetDays: (json['start_date_offset_days'] as num?)?.toInt(),
      endDateOffsetDays: (json['end_date_offset_days'] as num?)?.toInt(),
      options: options,
      medias: medias,
    );
  }
}
