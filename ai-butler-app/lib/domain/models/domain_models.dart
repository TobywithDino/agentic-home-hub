import 'package:flutter/foundation.dart';

/// 登入成功後的身分憑證（Requirement 1.4、2.1）。
@immutable
class AuthSession {
  const AuthSession({
    required this.inbrAccountId,
    required this.accessToken,
    this.expiresAt,
  });

  /// 會員 UUID v7。
  final String inbrAccountId;
  final String accessToken;
  final DateTime? expiresAt;
}

/// 會員資訊（Requirement 3.3、3.5）。
@immutable
class MemberProfile {
  const MemberProfile({
    required this.name,
    required this.mobile,
    this.email = '',
    this.landline = '',
    this.addressDetail = '',
    this.countyCode = '',
    this.districtCode = '',
  });

  final String name;
  final String mobile;
  final String email;
  final String landline;
  final String addressDetail;
  final String countyCode;
  final String districtCode;

  MemberProfile copyWith({
    String? name,
    String? mobile,
    String? email,
    String? landline,
    String? addressDetail,
    String? countyCode,
    String? districtCode,
  }) {
    return MemberProfile(
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      landline: landline ?? this.landline,
      addressDetail: addressDetail ?? this.addressDetail,
      countyCode: countyCode ?? this.countyCode,
      districtCode: districtCode ?? this.districtCode,
    );
  }
}

/// 服務類別（`cms_homepage_service`，Requirement 4.7、附錄 A）。
@immutable
class ServiceCategory {
  const ServiceCategory({
    required this.serviceId,
    required this.type,
    required this.name,
    this.imgUrl = '',
    this.description = '',
    this.vendorCount,
  });

  final int serviceId;

  /// 兩位數字代碼，見附錄 A（'01'..'11'）。
  final String type;
  final String name;
  final String imgUrl;
  final String description;

  /// 該類別下的服務商筆數，用於 Service_Catalog_Screen（Requirement 4.16）。
  final int? vendorCount;
}

/// 服務商摘要（Vendor_List_Screen 用，Requirement 5.2）。
@immutable
class VendorSummary {
  const VendorSummary({
    required this.vendorId,
    required this.name,
    this.description = '',
    this.imgUrl = '',
    this.serviceTags = const <String>[],
    this.rating,
    this.priceRangeMin,
    this.priceRangeMax,
    this.isAvailable,
    this.counties = const <String>[],
  });

  final int vendorId;
  final String name;
  final String description;
  final String imgUrl;
  final List<String> serviceTags;

  /// 評分。null 表示後端未提供此欄位（Requirement 5.8、5.11）。
  final double? rating;
  final int? priceRangeMin;
  final int? priceRangeMax;

  /// 是否目前可服務。null 表示後端未提供此欄位。
  final bool? isAvailable;
  final List<String> counties;
}

/// 服務商詳情（Vendor_Detail_Screen 用，Requirement 6.2-4）。
@immutable
class VendorDetail extends VendorSummary {
  const VendorDetail({
    required super.vendorId,
    required super.name,
    super.description,
    super.imgUrl,
    super.serviceTags,
    super.rating,
    super.priceRangeMin,
    super.priceRangeMax,
    super.isAvailable,
    super.counties,
    required this.formId,
    required this.serviceId,
    this.introContent = '',
    this.noticeContent = '',
    this.termsContent = '',
  });

  final int formId;
  final int serviceId;
  final String introContent;
  final String noticeContent;
  final String termsContent;
}

/// 後端是否提供評分／價格／可服務狀態欄位（Requirement 5.8-11）。
///
/// 由第一次查詢的回應推導，`Vendor_Filter_Panel` 依此決定顯示哪些條件。
@immutable
class VendorCapabilities {
  const VendorCapabilities({
    this.hasRating = false,
    this.hasPriceRange = false,
    this.hasAvailability = false,
  });

  final bool hasRating;
  final bool hasPriceRange;
  final bool hasAvailability;

  static const VendorCapabilities none = VendorCapabilities();
}

enum VendorSortOption { recommended, ratingDesc, priceAsc }

/// 服務商查詢條件（Requirement 5.7-16）。
@immutable
class VendorQuery {
  const VendorQuery({
    this.serviceId,
    this.keyword = '',
    this.countyCode,
    this.districtCode,
    this.minRating,
    this.priceMin,
    this.priceMax,
    this.availableOnly = false,
    this.selectedTags = const <String>[],
    this.sort = VendorSortOption.recommended,
    this.page = 1,
    this.pageSize = 20,
  });

  /// null 表示不限類別（全部服務，Requirement 5.20）。
  final int? serviceId;
  final String keyword;
  final String? countyCode;
  final String? districtCode;
  final double? minRating;
  final int? priceMin;
  final int? priceMax;
  final bool availableOnly;
  final List<String> selectedTags;
  final VendorSortOption sort;
  final int page;
  final int pageSize;

  /// 生效篩選條件數量，供篩選按鈕上的角標顯示（Requirement 5.15）。
  int get activeFilterCount {
    var count = 0;
    if (keyword.trim().isNotEmpty) count++;
    if (countyCode != null && countyCode!.isNotEmpty) count++;
    if (minRating != null) count++;
    if (priceMin != null || priceMax != null) count++;
    if (availableOnly) count++;
    if (selectedTags.isNotEmpty) count++;
    return count;
  }

  VendorQuery copyWith({
    int? serviceId,
    bool clearServiceId = false,
    String? keyword,
    String? countyCode,
    bool clearCounty = false,
    String? districtCode,
    bool clearDistrict = false,
    double? minRating,
    bool clearMinRating = false,
    int? priceMin,
    int? priceMax,
    bool clearPriceRange = false,
    bool? availableOnly,
    List<String>? selectedTags,
    VendorSortOption? sort,
    int? page,
    int? pageSize,
  }) {
    return VendorQuery(
      serviceId: clearServiceId ? null : (serviceId ?? this.serviceId),
      keyword: keyword ?? this.keyword,
      countyCode: clearCounty ? null : (countyCode ?? this.countyCode),
      districtCode: clearDistrict ? null : (districtCode ?? this.districtCode),
      minRating: clearMinRating ? null : (minRating ?? this.minRating),
      priceMin: clearPriceRange ? null : (priceMin ?? this.priceMin),
      priceMax: clearPriceRange ? null : (priceMax ?? this.priceMax),
      availableOnly: availableOnly ?? this.availableOnly,
      selectedTags: selectedTags ?? this.selectedTags,
      sort: sort ?? this.sort,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}

/// 分頁結果容器。
@immutable
class ResultPage<T> {
  const ResultPage({
    required this.items,
    required this.totalCount,
    required this.hasMore,
    this.capabilities = VendorCapabilities.none,
  });

  final List<T> items;
  final int totalCount;
  final bool hasMore;
  final VendorCapabilities capabilities;

  static ResultPage<T> empty<T>() =>
      ResultPage<T>(items: List<T>.empty(), totalCount: 0, hasMore: false);
}

/// 建立 feedback 前的草稿（Requirement 9.1）。
@immutable
class FeedbackDraft {
  const FeedbackDraft({
    required this.serviceId,
    required this.formId,
    required this.formType,
    required this.feedbackContent,
    this.contactName = '',
    this.contactMobile = '',
    this.contactLandline = '',
    this.contactEmail = '',
    this.preferredContactTime = '3',
    this.contactAddressCounty = '',
    this.contactAddressDistrict = '',
    this.contactAddressDetail = '',
    this.description = '',
  });

  final int serviceId;
  final int formId;
  final String formType;
  final Map<String, Object?> feedbackContent;
  final String contactName;
  final String contactMobile;
  final String contactLandline;
  final String contactEmail;

  /// 1 上午 / 2 下午 / 3 皆可
  final String preferredContactTime;
  final String contactAddressCounty;
  final String contactAddressDistrict;
  final String contactAddressDetail;
  final String description;

  static const String platformCode = '01';
}

@immutable
class FeedbackReceipt {
  const FeedbackReceipt({required this.feedbackNo, this.createdAt});

  final String feedbackNo;
  final DateTime? createdAt;
}

/// 我的諮詢單清單項目（Requirement 15.3）。
@immutable
class ConsultationItem {
  const ConsultationItem({
    required this.feedbackNo,
    required this.serviceName,
    required this.submittedAt,
    required this.status,
  });

  final String feedbackNo;
  final String serviceName;
  final DateTime submittedAt;

  /// 後端的處理狀態文字（例如「未讀」「已讀」「已受理」）。
  final String status;
}

/// 我的訂單清單項目（Requirement 15.4）。
@immutable
class OrderItem {
  const OrderItem({
    required this.orderNo,
    required this.orderType,
    required this.orderStatus,
    required this.finalAmount,
    required this.orderTime,
    this.serviceName = '',
    this.contactMobile = '',
  });

  final String orderNo;

  /// 兩位數字代碼，見附錄 B。
  final String orderType;
  final String orderStatus;
  final num finalAmount;
  final DateTime orderTime;
  final String serviceName;
  final String contactMobile;
}

@immutable
class OrderInbox {
  const OrderInbox({
    this.consultations = const <ConsultationItem>[],
    this.orders = const <OrderItem>[],
  });

  final List<ConsultationItem> consultations;
  final List<OrderItem> orders;

  static const OrderInbox empty = OrderInbox();
}

// === 訂單評價 ===

/// 建立/修改評價時的輸入資料。
@immutable
class ReviewDraft {
  const ReviewDraft({
    required this.inbrAccountId,
    required this.overallRating,
    this.ratingDetail = const <String, int>{},
    this.reviewContent = '',
    this.media = const <String>[],
  });

  final String inbrAccountId;

  /// 總評分 1~5。
  final int overallRating;

  /// 細項評分，例如 {"service": 5, "attitude": 4}。
  final Map<String, int> ratingDetail;

  /// 文字評價內容。
  final String reviewContent;

  /// 附加媒體 URL 列表。
  final List<String> media;
}

/// 後端回傳的完整評價物件。
@immutable
class OrderReview {
  const OrderReview({
    required this.recordId,
    required this.orderNo,
    required this.serviceVendorId,
    required this.serviceId,
    required this.inbrAccountId,
    required this.overallRating,
    this.ratingDetail = const <String, int>{},
    this.reviewContent = '',
    this.media = const <String>[],
    this.status = '01',
    this.isDeleted = false,
    this.creTime,
    this.updTime,
  });

  final int recordId;
  final String orderNo;
  final int serviceVendorId;
  final int serviceId;
  final String inbrAccountId;
  final int overallRating;
  final Map<String, int> ratingDetail;
  final String reviewContent;
  final List<String> media;

  /// '01' = 正常
  final String status;
  final bool isDeleted;
  final DateTime? creTime;
  final DateTime? updTime;

  factory OrderReview.fromJson(Map<String, dynamic> json) {
    return OrderReview(
      recordId: json['record_id'] as int? ?? 0,
      orderNo: json['order_no'] as String? ?? '',
      serviceVendorId: json['service_vendor_id'] as int? ?? 0,
      serviceId: json['service_id'] as int? ?? 0,
      inbrAccountId: json['inbr_account_id'] as String? ?? '',
      overallRating: json['overall_rating'] as int? ?? 0,
      ratingDetail: _parseRatingDetail(json['rating_detail']),
      reviewContent: json['review_content'] as String? ?? '',
      media: _parseStringList(json['media']),
      status: json['status'] as String? ?? '01',
      isDeleted: json['is_deleted'] as bool? ?? false,
      creTime: _parseDateTime(json['cre_time']),
      updTime: _parseDateTime(json['upd_time']),
    );
  }

  static Map<String, int> _parseRatingDetail(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
    }
    return const <String, int>{};
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const <String>[];
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    return null;
  }
}
