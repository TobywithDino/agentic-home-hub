import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/data/mock/mock_seed_data.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/repositories/repositories.dart';

/// Mock 實作集合（Requirement 21.2、21.5）。
///
/// 每個方法加入短延遲，讓 skeleton 與載入態在 demo 時可被看見
/// （design.md「Mock 資料集」）。

Future<void> _simulateLatency([int ms = 350]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

class MockAuthRepository implements AuthRepository {
  /// demo 帳號：任何非空帳密皆可登入，但保留一組固定帳密方便現場示範
  /// 「demo 快速登入」按鈕（Requirement 1.9-10）。
  static const String demoAccount = 'demo';
  static const String demoPassword = 'demo1234';

  @override
  Future<AuthSession> login(
      {required String account, required String password}) async {
    await _simulateLatency();

    if (account.trim().isEmpty || password.trim().isEmpty) {
      throw const ValidationError(message: '帳號或密碼不可為空');
    }

    if (account != demoAccount || password != demoPassword) {
      // demo 模式下，非固定帳密视為帳密錯誤，用於現場演示錯誤狀態。
      throw const AuthError(message: '帳號或密碼錯誤', isCredentialRejected: true);
    }

    return const AuthSession(
      inbrAccountId: '0198a3f1-6e42-7d3a-9c1b-4f8e2a7d5c60',
      accessToken: 'mock-access-token',
    );
  }

  @override
  Future<void> logout() async => _simulateLatency(100);
}

class MockAccountRepository implements AccountRepository {
  MemberProfile _profile = const MemberProfile(
    name: '王小明',
    mobile: '0912345678',
    email: 'demo@example.com',
    countyCode: '01',
    districtCode: '001',
    addressDetail: '中正路 100 號',
  );

  @override
  Future<MemberProfile> fetchProfile() async {
    await _simulateLatency();
    return _profile;
  }

  @override
  Future<void> updateContact(MemberProfile profile) async {
    await _simulateLatency();
    _profile = profile;
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _simulateLatency();
    if (newPassword.length < 8) {
      throw const ValidationError(
        fieldErrors: <String, String>{'new_password': '新密碼長度至少 8 個字元'},
      );
    }
  }
}

class MockServiceCatalogRepository implements ServiceCatalogRepository {
  @override
  Future<List<ServiceCategory>> fetchCategories() async {
    await _simulateLatency();
    return MockSeedData.categories.map((c) {
      final count = MockSeedData.vendorsByService[c.serviceId]?.length ?? 0;
      return ServiceCategory(
        serviceId: c.serviceId,
        type: c.type,
        name: c.name,
        imgUrl: c.imgUrl,
        description: c.description,
        vendorCount: count,
      );
    }).toList(growable: false);
  }
}

class MockVendorRepository implements VendorRepository {
  @override
  Future<ResultPage<VendorSummary>> searchVendors(VendorQuery query) async {
    await _simulateLatency();

    List<VendorSummary> pool;
    if (query.serviceId == null) {
      pool = MockSeedData.vendorsByService.values.expand((v) => v).toList();
    } else {
      pool = List<VendorSummary>.of(
        MockSeedData.vendorsByService[query.serviceId] ??
            const <VendorSummary>[],
      );
    }

    if (query.keyword.trim().isNotEmpty) {
      final kw = query.keyword.trim();
      pool = pool
          .where((v) => v.name.contains(kw) || v.description.contains(kw))
          .toList();
    }
    // 標籤篩選
    if (query.selectedTags.isNotEmpty) {
      pool = pool.where((v) {
        return query.selectedTags.every((tag) => v.serviceTags.contains(tag));
      }).toList();
    }
    if (query.minRating != null) {
      pool = pool.where((v) => (v.rating ?? 0) >= query.minRating!).toList();
    }
    if (query.priceMin != null || query.priceMax != null) {
      pool = pool.where((v) {
        if (v.priceRangeMin == null) return false;
        if (query.priceMin != null && v.priceRangeMin! < query.priceMin!) {
          return false;
        }
        if (query.priceMax != null &&
            (v.priceRangeMax ?? v.priceRangeMin!) > query.priceMax!) {
          return false;
        }
        return true;
      }).toList();
    }
    if (query.availableOnly) {
      pool = pool.where((v) => v.isAvailable == true).toList();
    }

    switch (query.sort) {
      case VendorSortOption.ratingDesc:
        pool.sort((a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1));
      case VendorSortOption.priceAsc:
        pool.sort((a, b) =>
            (a.priceRangeMin ?? 1 << 30).compareTo(b.priceRangeMin ?? 1 << 30));
      case VendorSortOption.recommended:
        break;
    }

    final hasRating = pool.any((v) => v.rating != null);
    final hasPriceRange = pool.any((v) => v.priceRangeMin != null);
    final hasAvailability = pool.any((v) => v.isAvailable != null);

    final start = (query.page - 1) * query.pageSize;
    final end = (start + query.pageSize).clamp(0, pool.length);
    final items = start >= pool.length
        ? const <VendorSummary>[]
        : pool.sublist(start, end);

    return ResultPage<VendorSummary>(
      items: items,
      totalCount: pool.length,
      hasMore: end < pool.length,
      capabilities: VendorCapabilities(
        hasRating: hasRating,
        hasPriceRange: hasPriceRange,
        hasAvailability: hasAvailability,
      ),
    );
  }

  @override
  Future<VendorDetail> fetchVendorDetail(int vendorId) async {
    await _simulateLatency();
    for (final entry in MockSeedData.vendorsByService.entries) {
      for (final vendor in entry.value) {
        if (vendor.vendorId == vendorId) {
          return MockSeedData.detailOf(vendor, entry.key);
        }
      }
    }
    throw const ServerError(
        message: '找不到服務商', endpoint: 'mock:fetchVendorDetail');
  }
}

class MockFormRepository implements FormRepository {
  @override
  Future<FormDefinition> fetchForm(int formId) async {
    await _simulateLatency();
    for (final entry in MockSeedData.vendorsByService.entries) {
      for (final vendor in entry.value) {
        if (vendor.vendorId == formId) {
          return MockSeedData.formFor(formId, serviceId: entry.key);
        }
      }
    }
    // 找不到對應服務商時，仍回傳一份預設表單，避免 demo 卡死。
    return MockSeedData.formFor(formId, serviceId: 1);
  }
}

class MockFeedbackRepository implements FeedbackRepository {
  int _sequence = 0;

  @override
  Future<FeedbackReceipt> submit(FeedbackDraft draft) async {
    await _simulateLatency(500);
    _sequence++;
    final now = DateTime.now();
    final no = 'FB${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}${_sequence.toString().padLeft(3, '0')}';
    return FeedbackReceipt(feedbackNo: no, createdAt: now);
  }
}

class MockOrderRepository implements OrderRepository {
  @override
  Future<OrderInbox> fetchInbox() async {
    await _simulateLatency();
    return OrderInbox(
      consultations: MockSeedData.consultations,
      orders: MockSeedData.allOrderStatuses,
    );
  }
}

class MockReviewRepository implements ReviewRepository {
  final List<OrderReview> _reviews = [];
  int _sequence = 0;

  @override
  Future<OrderReview> createReview({
    required int recordId,
    required ReviewDraft draft,
  }) async {
    await _simulateLatency();
    _sequence++;
    final review = OrderReview(
      recordId: recordId,
      orderNo:
          'ORD${DateTime.now().year}${_sequence.toString().padLeft(4, '0')}',
      serviceVendorId: 1,
      serviceId: 17,
      inbrAccountId: draft.inbrAccountId,
      overallRating: draft.overallRating,
      ratingDetail: draft.ratingDetail,
      reviewContent: draft.reviewContent,
      media: draft.media,
      status: '01',
      creTime: DateTime.now(),
    );
    _reviews.add(review);
    return review;
  }

  @override
  Future<OrderReview> updateReview({
    required int recordId,
    required ReviewDraft draft,
  }) async {
    await _simulateLatency();
    final idx = _reviews.indexWhere((r) => r.recordId == recordId);
    final updated = OrderReview(
      recordId: recordId,
      orderNo: idx >= 0 ? _reviews[idx].orderNo : 'ORD0001',
      serviceVendorId: idx >= 0 ? _reviews[idx].serviceVendorId : 1,
      serviceId: idx >= 0 ? _reviews[idx].serviceId : 17,
      inbrAccountId: draft.inbrAccountId,
      overallRating: draft.overallRating,
      ratingDetail: draft.ratingDetail,
      reviewContent: draft.reviewContent,
      media: draft.media,
      status: '01',
      creTime: idx >= 0 ? _reviews[idx].creTime : DateTime.now(),
      updTime: DateTime.now(),
    );
    if (idx >= 0) {
      _reviews[idx] = updated;
    } else {
      _reviews.add(updated);
    }
    return updated;
  }

  @override
  Future<List<OrderReview>> fetchServiceReviews(int serviceId) async {
    await _simulateLatency();
    // 回傳預設的 mock 評價資料
    return [
      OrderReview(
        recordId: 1,
        orderNo: 'ORD20260101001',
        serviceVendorId: 1,
        serviceId: serviceId,
        inbrAccountId: '0198a3f1-6e42-7d3a-9c1b-4f8e2a7d5c60',
        overallRating: 5,
        ratingDetail: const {'service': 5, 'attitude': 5},
        reviewContent: '服務很好，準時到府，環境整理得很乾淨！',
        media: const [],
        status: '01',
        creTime: DateTime(2026, 6, 15),
      ),
      OrderReview(
        recordId: 2,
        orderNo: 'ORD20260201002',
        serviceVendorId: 1,
        serviceId: serviceId,
        inbrAccountId: '0198a3f1-6e42-7d3a-9c1b-000000000001',
        overallRating: 4,
        ratingDetail: const {'service': 4, 'attitude': 4},
        reviewContent: '整體不錯，但時間稍有延遲。',
        media: const [],
        status: '01',
        creTime: DateTime(2026, 7, 2),
      ),
      ..._reviews.where((r) => r.serviceId == serviceId),
    ];
  }
}
