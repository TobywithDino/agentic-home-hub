import 'package:flutter/foundation.dart';

import 'package:ai_butler_app/core/utils/api_time.dart';

/// 摘要生成狀態（`mms_review_summary_service.generate_status`）。
enum SummaryStatus {
  pending('00'),
  generating('01'),
  done('02'),
  failed('03'),
  unknown('__');

  const SummaryStatus(this.code);

  final String code;

  static SummaryStatus fromCode(String? raw) {
    if (raw == null) return SummaryStatus.unknown;
    for (final status in values) {
      if (status.code == raw) return status;
    }
    return SummaryStatus.unknown;
  }
}

/// 服務項目的評價 AI 摘要。
///
/// 對應 `GET /app-api/services/{service_id}/review-summary`。
/// 尚未生成過摘要時後端回 404，資料層會轉成 null（見 `ApiClient.getOptional`）。
@immutable
class ReviewSummary {
  const ReviewSummary({
    required this.serviceId,
    this.summaryContent = '',
    this.sourceReviewCount = 0,
    this.sourceAvgRating,
    this.aiModel = '',
    this.status = SummaryStatus.unknown,
    this.isStale = false,
    this.errorMessage = '',
    this.generateTime,
    this.latestReviewCreTime,
  });

  final int serviceId;

  /// 消費者版的純文字口碑摘要。
  final String summaryContent;

  /// 這份摘要涵蓋的評價筆數。
  final int sourceReviewCount;

  /// 這份摘要涵蓋評價的平均分。
  final double? sourceAvgRating;

  final String aiModel;
  final SummaryStatus status;

  /// true 代表有新評價還沒被納入這份摘要。
  final bool isStale;

  final String errorMessage;
  final DateTime? generateTime;
  final DateTime? latestReviewCreTime;

  /// 是否有可顯示的摘要內容。
  bool get hasContent =>
      status == SummaryStatus.done && summaryContent.trim().isNotEmpty;

  factory ReviewSummary.fromJson(Map<String, dynamic> json) {
    return ReviewSummary(
      serviceId: (json['service_id'] as num?)?.toInt() ?? 0,
      summaryContent: json['summary_content'] as String? ?? '',
      sourceReviewCount: (json['source_review_count'] as num?)?.toInt() ?? 0,
      sourceAvgRating: (json['source_avg_rating'] as num?)?.toDouble(),
      aiModel: json['ai_model'] as String? ?? '',
      status: SummaryStatus.fromCode(json['generate_status'] as String?),
      isStale: json['is_stale'] as bool? ?? false,
      errorMessage: json['error_message'] as String? ?? '',
      generateTime: ApiTime.tryParse(json['generate_time']),
      latestReviewCreTime: ApiTime.tryParse(json['latest_review_cre_time']),
    );
  }
}
