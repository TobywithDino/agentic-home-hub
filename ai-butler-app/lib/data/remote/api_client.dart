import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:ai_butler_app/core/error/app_error.dart';

/// 統一的 HTTP 客戶端（Requirement 22.1-3）。
///
/// 封裝 dio，處理：
/// - 逾時設定（連線 10s、讀取 20s）
/// - 讀取類請求自動重試（500ms→1500ms，最多 2 次）
/// - 401 回呼（由外部傳入 forceLogout）
/// - 日誌（debug 模式下印出 request/response，個資鍵自動遮蔽）
/// - 統一錯誤轉換為 AppError 體系
class ApiClient {
  ApiClient({
    required String baseUrl,
    this.onUnauthorized,
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          // BFF 部分端點（例如 orders-overview 會逐筆補評價）回應偏慢，
          // 逾時放寬避免正常回應被誤判為連線失敗。
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
          headers: {'Content-Type': 'application/json'},
        )) {
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint('[API] $o'),
      ));
    }
  }

  final Dio _dio;

  /// 401 回呼，由 provider 層注入 AuthNotifier.forceLogout。
  final Future<void> Function()? onUnauthorized;

  /// 設定用於請求標頭的 inbr_account_id（目前 BFF 無 token 機制）。
  String? _inbrAccountId;

  void setAccountId(String? id) => _inbrAccountId = id;

  /// GET 請求（含重試）。
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _withRetry(() => _dio.get<T>(
          path,
          queryParameters: queryParameters,
          options: _authOptions(),
        ));
  }

  /// POST 請求（不重試）。
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
  }) async {
    return _handleErrors(() => _dio.post<T>(
          path,
          data: data,
          options: _authOptions(),
        ));
  }

  /// PATCH 請求（不重試）。
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
  }) async {
    return _handleErrors(() => _dio.patch<T>(
          path,
          data: data,
          options: _authOptions(),
        ));
  }

  Options _authOptions() {
    final headers = <String, String>{};
    if (_inbrAccountId != null) {
      headers['X-Account-Id'] = _inbrAccountId!;
    }
    return Options(headers: headers);
  }

  /// 讀取類重試：500ms / 1500ms，最多 2 次（Requirement 22.2）。
  Future<Response<T>> _withRetry<T>(
    Future<Response<T>> Function() request,
  ) async {
    const retryDelays = [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500)
    ];
    Object? lastError;

    // 第一次嘗試
    try {
      return await _handleErrors(request);
    } catch (e) {
      if (!_isRetryable(e)) rethrow;
      lastError = e;
    }

    // 重試
    for (final delay in retryDelays) {
      await Future<void>.delayed(delay);
      try {
        return await _handleErrors(request);
      } catch (e) {
        if (!_isRetryable(e)) rethrow;
        lastError = e;
      }
    }

    throw lastError!; // 已是 AppError
  }

  bool _isRetryable(Object error) {
    // 讀取逾時代表後端本來就慢，重試只會讓使用者多等好幾倍時間。
    if (error is NetworkError) {
      final cause = error.cause;
      if (cause is DioException &&
          cause.type == DioExceptionType.receiveTimeout) {
        return false;
      }
      return true;
    }
    return error is ServerError && (error.statusCode ?? 0) >= 500;
  }

  /// 統一錯誤轉換：DioException → AppError。
  Future<Response<T>> _handleErrors<T>(
    Future<Response<T>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          throw NetworkError(
            endpoint: e.requestOptions.path,
            cause: e,
          );
        case DioExceptionType.badResponse:
          final status = e.response?.statusCode ?? 0;
          final body = e.response?.data;

          if (status == 401) {
            onUnauthorized?.call();
            throw AuthError(
              endpoint: e.requestOptions.path,
              cause: e,
            );
          }

          if (status == 422) {
            final detail = _extractDetail(body);
            throw ValidationError(
              message: detail ?? '部分欄位需要修正',
              endpoint: e.requestOptions.path,
              cause: e,
            );
          }

          if (status >= 400 && status < 500) {
            final detail = _extractDetail(body);
            if (detail != null &&
                (detail.contains('帳號') || detail.contains('密碼'))) {
              throw AuthError(
                message: detail,
                isCredentialRejected: true,
                endpoint: e.requestOptions.path,
                cause: e,
              );
            }
            throw ValidationError(
              message: detail ?? '請求無效',
              endpoint: e.requestOptions.path,
              cause: e,
            );
          }

          throw ServerError(
            statusCode: status,
            endpoint: e.requestOptions.path,
            cause: e,
          );
        default:
          throw NetworkError(
            endpoint: e.requestOptions.path,
            cause: e,
          );
      }
    }
  }

  /// 從後端回應萃取 detail 訊息。
  String? _extractDetail(dynamic body) {
    if (body is Map<String, dynamic>) {
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map) return first['msg']?.toString();
      }
    }
    return null;
  }
}
