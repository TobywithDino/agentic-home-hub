import 'package:ai_butler_app/core/config/api_endpoints.dart';
import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/data/remote/api_client.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// 真實後端的訂單評價實作。
///
/// BFF 端點：
/// - `POST /app-api/orders/{record_id}/review` — 建立評價
/// - `PATCH /app-api/users/{id}/orders/{record_id}/review` — 修改評價
/// - `GET /app-api/services/{service_id}/reviews` — 查看服務評價
class HttpReviewRepository implements ReviewRepository {
  HttpReviewRepository(this._client, {required this.getAccountId});

  final ApiClient _client;
  final String Function() getAccountId;

  @override
  Future<OrderReview> createReview({
    required int recordId,
    required ReviewDraft draft,
  }) async {
    final payload = <String, dynamic>{
      'inbr_account_id': draft.inbrAccountId,
      'overall_rating': draft.overallRating,
    };
    if (draft.ratingDetail.isNotEmpty) {
      payload['rating_detail'] = draft.ratingDetail;
    }
    if (draft.reviewContent.isNotEmpty) {
      payload['review_content'] = draft.reviewContent;
    }
    if (draft.media.isNotEmpty) {
      payload['media'] = draft.media;
    }

    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.createReview(recordId),
      data: payload,
    );

    final body = response.data;
    if (body == null) {
      throw const ServerError(
        message: '建立評價回應格式異常',
        endpoint: 'POST /app-api/orders/{record_id}/review',
      );
    }

    return OrderReview.fromJson(body);
  }

  @override
  Future<OrderReview> updateReview({
    required int recordId,
    required ReviewDraft draft,
  }) async {
    final accountId = draft.inbrAccountId.isNotEmpty
        ? draft.inbrAccountId
        : getAccountId();

    final payload = <String, dynamic>{};
    // 只送有需要修改的欄位
    payload['overall_rating'] = draft.overallRating;
    if (draft.ratingDetail.isNotEmpty) {
      payload['rating_detail'] = draft.ratingDetail;
    }
    if (draft.reviewContent.isNotEmpty) {
      payload['review_content'] = draft.reviewContent;
    }
    if (draft.media.isNotEmpty) {
      payload['media'] = draft.media;
    }

    final response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.updateReview(accountId, recordId),
      data: payload,
    );

    final body = response.data;
    if (body == null) {
      throw const ServerError(
        message: '修改評價回應格式異常',
        endpoint: 'PATCH /app-api/users/{id}/orders/{record_id}/review',
      );
    }

    return OrderReview.fromJson(body);
  }

  @override
  Future<List<OrderReview>> fetchServiceReviews(int serviceId) async {
    final response = await _client.get<List<dynamic>>(
      ApiEndpoints.serviceReviews(serviceId),
    );

    final data = response.data ?? [];
    return data
        .map((json) => OrderReview.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
