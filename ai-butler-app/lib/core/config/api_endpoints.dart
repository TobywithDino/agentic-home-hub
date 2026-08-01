/// 所有後端接點路徑集中在此（Requirement 21.7）
///
/// 隊友的 API 格式定稿後，只需要改這個檔案 + `lib/data/dto/`，
/// Domain 與畫面層完全不動。
/// 待確認的接點一律以 `// TODO(backend):` 標註（Requirement 21.6）。
class ApiEndpoints {
  ApiEndpoints._();

  // === 1. 登入 ===
  // POST /app-api/auth/login  body: {account, password}  回傳: {inbr_account_id}
  static const String login = '/app-api/auth/login';
  static const String logout = '/app-api/auth/logout'; // 尚無此接點，mock 處理

  // === 2-3. 會員資訊 ===
  // PATCH /app-api/users/{inbr_account_id}  body: 聯絡欄位
  static const String profile = '/app-api/users';
  static String updateUser(String inbrAccountId) =>
      '/app-api/users/$inbrAccountId';

  // === 5-6. 服務商 ===
  // GET /app-api/service-types/{service_type}/vendors
  static String vendorsByServiceType(String serviceType) =>
      '/app-api/service-types/$serviceType/vendors';

  // === 8. 建立 feedback（諮詢單） ===
  // POST /app-api/feedbacks
  static const String feedbacks = '/app-api/feedbacks';

  // === 9. 查看訂單（feedbacks + orders 合併） ===
  // GET /app-api/users/{inbr_account_id}/orders-overview
  static String ordersOverview(String inbrAccountId) =>
      '/app-api/users/$inbrAccountId/orders-overview';

  // === 10. 訂單評價 ===
  // POST /app-api/orders/{record_id}/review — 建立評價
  static String createReview(int recordId) =>
      '/app-api/orders/$recordId/review';

  // PATCH /app-api/users/{inbr_account_id}/orders/{record_id}/review — 修改評價
  static String updateReview(String inbrAccountId, int recordId) =>
      '/app-api/users/$inbrAccountId/orders/$recordId/review';

  // GET /app-api/services/{service_id}/reviews — 查看某服務的全部評價
  static String serviceReviews(int serviceId) =>
      '/app-api/services/$serviceId/reviews';

  // === 11. 照片預簽章上傳 ===
  // TODO(backend): 確認預簽章回應欄位（期望 {upload_url, file_id}）
  static const String mediaPresign = '/media/presign';

  // === 11. 推播 token 註冊 ===
  // TODO(backend): 確認推播管道（FCM/APNs 直連或走 Pinpoint/SNS）
  static const String pushTokens = '/notifications/tokens';

  // === AI 代理（後端轉呼 Bedrock） ===
  // TODO(backend): 確認是否提供串流回應（SSE），否則 App 端退回一次性回應
  static const String aiChat = '/ai/chat';
  static const String aiClassify = '/ai/classify';
  static const String aiPrefill = '/ai/prefill';

  // === 地區主檔 ===
  // TODO(backend): 確認縣市/行政區是由 API 提供或 App 內建靜態資料
  static const String counties = '/regions/counties';
  static String districts(String countyCode) =>
      '/regions/counties/$countyCode/districts';
}
