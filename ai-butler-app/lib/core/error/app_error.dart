/// App 統一錯誤模型（Requirement 22.4）
///
/// 所有失敗結果在 Data 層就轉成這四種類型，畫面層不需要認識 DioException。
sealed class AppError implements Exception {
  const AppError({required this.message, this.endpoint, this.cause});

  /// 給使用者看的訊息。
  final String message;

  /// 觸發錯誤的接點名稱，僅用於偵錯日誌（Requirement 21.11、22.9）。
  final String? endpoint;

  final Object? cause;

  @override
  String toString() => '$runtimeType(endpoint: $endpoint, message: $message)';
}

/// 連線逾時、DNS 失敗、裝置離線。可重試。
class NetworkError extends AppError {
  const NetworkError({
    super.message = '網路連線不穩，請確認後重試',
    super.endpoint,
    super.cause,
  });
}

/// 401 或憑證失效。需重新登入（Requirement 2.13）。
class AuthError extends AppError {
  const AuthError({
    super.message = '登入已逾期，請重新登入',
    super.endpoint,
    super.cause,
    this.isCredentialRejected = false,
  });

  /// true 表示帳密錯誤（登入時），false 表示既有 session 失效。
  final bool isCredentialRejected;
}

/// 後端回傳的欄位驗證錯誤。錯誤訊息需貼回對應欄位（Requirement 9.12）。
class ValidationError extends AppError {
  const ValidationError({
    super.message = '部分欄位需要修正',
    this.fieldErrors = const <String, String>{},
    super.endpoint,
    super.cause,
  });

  /// key 為欄位或 topic_id 的字串形式，value 為錯誤訊息。
  final Map<String, String> fieldErrors;
}

/// 5xx、回應格式不符、其他未預期狀況。
class ServerError extends AppError {
  const ServerError({
    super.message = '服務暫時無法回應，請稍後再試',
    super.endpoint,
    super.cause,
    this.statusCode,
  });

  final int? statusCode;
}

/// DTO 解析失敗（Requirement 21.11）。
///
/// 刻意讓它是明確的類型，這樣現場一看日誌就知道是「隊友的回應欄位跟預期不同」，
/// 而不是茫然地找 UI bug。
class DtoParseException implements Exception {
  const DtoParseException({
    required this.endpoint,
    required this.field,
    required this.reason,
  });

  final String endpoint;
  final String field;
  final String reason;

  @override
  String toString() =>
      'DtoParseException(endpoint: $endpoint, field: $field, reason: $reason)';
}
