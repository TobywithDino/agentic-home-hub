/// 資料來源切換（Requirement 21.3-4）
enum DataSource {
  /// 本機 mock，離線可跑完整流程（Requirement 21.5）
  mock,

  /// 隊友的真實後端 API
  remote,
}

/// 環境設定。
///
/// 比賽現場切換到真實後端只需改啟動參數，不動任何程式碼：
/// ```
/// fvm flutter run \
///   --dart-define=DATA_SOURCE=remote \
///   --dart-define=AI_SOURCE=remote \
///   --dart-define=BASE_URL=https://xxx.execute-api.ap-northeast-1.amazonaws.com
/// ```
class EnvironmentConfig {
  const EnvironmentConfig({
    required this.dataSource,
    required this.aiSource,
    required this.baseUrl,
    required this.guestBrowsing,
  });

  /// 一般資料接點（登入、服務商、表單、訂單）的來源。
  final DataSource dataSource;

  /// AI 對話能力的來源，與 [dataSource] 獨立，
  /// 允許「資料走真實後端、AI 走 mock」這種現場混搭。
  final DataSource aiSource;

  /// 後端 base URL。[dataSource] 為 mock 時可為空字串。
  final String baseUrl;

  /// 預設的真實 API base URL（比賽現場用）。
  static const String defaultRemoteUrl = 'http://52.10.163.115:8100';

  /// 訪客瀏覽開關（Requirement 2.10，預設 false）。
  final bool guestBrowsing;

  static const String _dataSourceKey = 'DATA_SOURCE';
  static const String _aiSourceKey = 'AI_SOURCE';
  static const String _baseUrlKey = 'BASE_URL';
  static const String _guestBrowsingKey = 'GUEST_BROWSING';

  /// 從 `--dart-define` 讀取，未提供時預設走真實後端（比賽模式）。
  factory EnvironmentConfig.fromEnvironment() {
    return EnvironmentConfig(
      dataSource: _parseSource(
        const String.fromEnvironment(_dataSourceKey, defaultValue: 'remote'),
      ),
      aiSource: _parseSource(
        const String.fromEnvironment(_aiSourceKey, defaultValue: 'mock'),
      ),
      baseUrl: const String.fromEnvironment(_baseUrlKey, defaultValue: ''),
      guestBrowsing: const bool.fromEnvironment(
        _guestBrowsingKey,
        defaultValue: false,
      ),
    );
  }

  static DataSource _parseSource(String raw) =>
      raw.trim().toLowerCase() == 'remote'
          ? DataSource.remote
          : DataSource.mock;

  bool get usesMockData => dataSource == DataSource.mock;
  bool get usesMockAi => aiSource == DataSource.mock;

  /// 解析後實際使用的 base URL：若未提供則使用預設比賽 URL。
  String get effectiveBaseUrl =>
      baseUrl.trim().isEmpty ? defaultRemoteUrl : baseUrl;

  /// 設定是否自相矛盾（要求真實後端卻沒給 baseUrl 且無預設值）。
  /// 因為已有 defaultRemoteUrl，remote 模式下不會 misconfigured。
  bool get isMisconfigured => false;

  /// baseUrl 是否為 https（Requirement 11.1）。
  ///
  /// 允許 localhost 與比賽專用 IP 使用 http，方便現場對接。
  bool get hasSecureBaseUrl {
    if (baseUrl.trim().isEmpty) return true;
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return false;
    if (uri.scheme == 'https') return true;
    // 開發/比賽環境：允許 localhost 與指定 IP 使用 http
    return uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '10.0.2.2' ||
        uri.host == '52.10.163.115';
  }

  EnvironmentConfig copyWith({
    DataSource? dataSource,
    DataSource? aiSource,
    String? baseUrl,
    bool? guestBrowsing,
  }) {
    return EnvironmentConfig(
      dataSource: dataSource ?? this.dataSource,
      aiSource: aiSource ?? this.aiSource,
      baseUrl: baseUrl ?? this.baseUrl,
      guestBrowsing: guestBrowsing ?? this.guestBrowsing,
    );
  }
}
