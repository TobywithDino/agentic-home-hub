import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// Web 用 Fetch API 版本的 client。
///
/// 為什麼不用預設的 `BrowserClient`：它走 XMLHttpRequest，只有整個回應收完
/// 才把資料交出來，拿不到逐段串流。`FetchClient` 走 Fetch API 的
/// ReadableStream，回應可以一邊收一邊吐字。
///
/// 刻意不開 `streamRequests`：那是「把 request body 當 stream 送」，
/// 依官方說明需要伺服器跑 HTTP/2 或 HTTP/3，而 bff_server 是純 HTTP/1.1，
/// 開了會讓請求直接失敗。我們只需要 response 串流，那是預設行為。
http.Client createSseClient() => FetchClient(mode: RequestMode.cors);
