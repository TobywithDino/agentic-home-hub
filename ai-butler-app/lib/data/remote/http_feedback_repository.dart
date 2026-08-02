import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/core/utils/api_time.dart';
import 'package:ai_butler_app/data/remote/api_client.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 真實後端的 feedback（諮詢單）提交實作。
class HttpFeedbackRepository implements FeedbackRepository {
  HttpFeedbackRepository(this._client, {required this.getAccountId});

  final ApiClient _client;

  /// 取得當前登入者的 inbr_account_id，由外部注入。
  final String Function() getAccountId;

  @override
  Future<FeedbackReceipt> submit(FeedbackDraft draft) async {
    final accountId = getAccountId();

    // 產生 feedback_no：格式 FB + yyyyMMdd + 6 位序號
    final now = DateTime.now();
    final dateStr = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final seq =
        (now.millisecondsSinceEpoch % 1000000).toString().padLeft(6, '0');
    final feedbackNo = 'FB$dateStr$seq';

    final payload = <String, dynamic>{
      'feedback_no': feedbackNo,
      'service_id': draft.serviceId,
      'platform_code': FeedbackDraft.platformCode,
      'form_id': draft.formId,
      'feedback_content': draft.feedbackContent,
      'form_type': draft.formType,
      'contact_name': draft.contactName.isNotEmpty ? draft.contactName : null,
      'contact_mobile':
          draft.contactMobile.isNotEmpty ? draft.contactMobile : null,
      'contact_landline':
          draft.contactLandline.isNotEmpty ? draft.contactLandline : null,
      'contact_email':
          draft.contactEmail.isNotEmpty ? draft.contactEmail : null,
      'preferred_contact_time': draft.preferredContactTime,
      'contact_address_county': draft.contactAddressCounty.isNotEmpty
          ? draft.contactAddressCounty
          : null,
      'contact_address_district': draft.contactAddressDistrict.isNotEmpty
          ? draft.contactAddressDistrict
          : null,
      'contact_address_detail': draft.contactAddressDetail.isNotEmpty
          ? draft.contactAddressDetail
          : null,
      'description': draft.description.isNotEmpty ? draft.description : null,
      'inbr_account_id': accountId,
    };

    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.feedbacks,
      data: payload,
    );

    final body = response.data;
    if (body == null) {
      throw const ServerError(
        message: '建立諮詢單回應格式異常',
        endpoint: 'POST /app-api/feedbacks',
      );
    }

    return FeedbackReceipt(
      feedbackNo: body['feedback_no'] as String? ?? feedbackNo,
      // 後端回 UTC，統一轉本地時區再交給畫面顯示。
      createdAt: ApiTime.parseOr(body['cre_time']),
    );
  }
}
