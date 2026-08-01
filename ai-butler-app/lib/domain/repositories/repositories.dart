import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';

/// 7 組 Repository 抽象介面（Requirement 21.1）。
///
/// 每個介面各有一份 mock 實作（`data/mock/`）與一份 HTTP 實作
/// （`data/remote/`）。畫面層與 Notifier 只依賴這裡定義的型別，
/// 不知道資料究竟從哪裡來（Requirement 21.12）。

/// 1. 登入（對應後端「登入」）。
abstract interface class AuthRepository {
  Future<AuthSession> login(
      {required String account, required String password});
  Future<void> logout();
}

/// 2-3. 會員資訊（對應後端「設定會員資訊」）。
abstract interface class AccountRepository {
  Future<MemberProfile> fetchProfile();
  Future<void> updateContact(MemberProfile profile);
  Future<void> changePassword(
      {required String oldPassword, required String newPassword});
}

/// 4. 服務類別主檔。
abstract interface class ServiceCatalogRepository {
  Future<List<ServiceCategory>> fetchCategories();
}

/// 5-6. 服務商查詢（對應後端「尋找特定服務的廠商」）。
abstract interface class VendorRepository {
  Future<ResultPage<VendorSummary>> searchVendors(VendorQuery query);
  Future<VendorDetail> fetchVendorDetail(int vendorId);
}

/// 7. 表單定義。期望單一接點一次回傳完整結構（見 design.md 後端接點表 #7）。
abstract interface class FormRepository {
  Future<FormDefinition> fetchForm(int formId);
}

/// 8. 建立 feedback（對應後端「建立 feedback」）。
abstract interface class FeedbackRepository {
  Future<FeedbackReceipt> submit(FeedbackDraft draft);
}

/// 9. 查看訂單（對應後端「查看訂單」：feedbacks + orders 合併）。
abstract interface class OrderRepository {
  Future<OrderInbox> fetchInbox();
}
