import 'package:http/http.dart' as http;

/// 原生平台（iOS / Android / desktop）用標準 http client，本身就支援串流。
http.Client createSseClient() => http.Client();
