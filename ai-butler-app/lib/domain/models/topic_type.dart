/// 表單題目類型（`pms_form_topic.type`）
///
/// 以命題附件的數字代碼為唯一識別（Requirement 21.14-15）。
/// 舊版 `form_field_model.dart` 用 `'text'`／`'select'` 這類自然語言字串，
/// 與 DB 對不上，欄位一改就靜默失敗，因此整批換掉。
enum TopicType {
  /// 01 簡答題
  shortText('01'),

  /// 02 詳答題
  longText('02'),

  /// 03 單選題
  singleChoice('03'),

  /// 04 複選題
  multiChoice('04'),

  /// 05 地區選單
  region('05'),

  /// 06 上傳照片
  photo('06'),

  /// 07 備註說明（唯讀，不收集作答值）
  notice('07'),

  /// 08 聯絡資料（含地址）
  contactWithAddress('08'),

  /// 09 日期題
  date('09'),

  /// 10 聯絡資料（不含地址）
  contactWithoutAddress('10'),

  /// 後端出現未知代碼時的兜底值（Requirement 7.18）
  unsupported('__');

  const TopicType(this.code);

  /// 兩位數字字串代碼，序列化時直接使用（Requirement 9.3）。
  final String code;

  /// 附件 JSON 同時出現 `1` 與 `01` 兩種寫法，統一補零後比對。
  static String normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.length == 1 ? '0$trimmed' : trimmed;
  }

  /// 由代碼解析，未知代碼回傳 [unsupported] 而非拋例外。
  ///
  /// 這是刻意的容錯：後端隨時可能新增題型，App 不該因此整頁掛掉，
  /// 而是渲染成「此題型尚未支援」並繼續渲染其餘題目。
  static TopicType fromCode(String? raw) {
    if (raw == null) return TopicType.unsupported;
    final normalized = normalize(raw);
    for (final type in values) {
      if (type.code == normalized) return type;
    }
    return TopicType.unsupported;
  }

  /// 是否為需要收集作答值的題型。
  bool get collectsAnswer =>
      this != TopicType.notice && this != TopicType.unsupported;

  /// 是否為以選項為作答值的題型。
  bool get isOptionBased =>
      this == TopicType.singleChoice || this == TopicType.multiChoice;

  /// 是否為聯絡資料題型。
  bool get isContact =>
      this == TopicType.contactWithAddress ||
      this == TopicType.contactWithoutAddress;

  /// 顯示用名稱，出現在偵錯與「尚未支援」提示卡上。
  String get label => switch (this) {
        TopicType.shortText => '簡答題',
        TopicType.longText => '詳答題',
        TopicType.singleChoice => '單選題',
        TopicType.multiChoice => '複選題',
        TopicType.region => '地區選單',
        TopicType.photo => '上傳照片',
        TopicType.notice => '備註說明',
        TopicType.contactWithAddress => '聯絡資料',
        TopicType.date => '日期題',
        TopicType.contactWithoutAddress => '聯絡資料（不含地址）',
        TopicType.unsupported => '未支援題型',
      };
}
