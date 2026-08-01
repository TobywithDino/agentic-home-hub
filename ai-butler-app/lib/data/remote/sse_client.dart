/// 依平台選擇支援串流的 http client。
///
/// Web 走 Fetch API（`sse_client_web.dart`），原生走標準 http client
/// （`sse_client_io.dart`）。條件 import 讓原生 build 不會被拉進 web-only 的程式碼。
library;

export 'sse_client_io.dart' if (dart.library.js_interop) 'sse_client_web.dart';
