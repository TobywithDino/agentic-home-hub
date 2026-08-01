import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/models/form_definition.dart';
import 'package:ai_butler_app/domain/models/topic_type.dart';

/// Mock 資料集（Requirement 21.2、21.5）。
///
/// 目標：離線就能走完「登入 → 首頁 → 類別 → 服務商列表篩選 → 詳情 →
/// 填單 → 送出 → 訂單」全程（design.md「Mock 資料集」）。
class MockSeedData {
  MockSeedData._();

  // === 服務類別（附錄 A）===
  static const List<ServiceCategory> categories = <ServiceCategory>[
    ServiceCategory(
        serviceId: 1, type: '01', name: '一般居家清潔', description: '居家清潔、深度打掃'),
    ServiceCategory(
        serviceId: 2, type: '02', name: '家電清洗', description: '冷氣、洗衣機清洗保養'),
    ServiceCategory(
        serviceId: 3, type: '03', name: '包裹寄送', description: '取件寄件、宅配到府'),
    ServiceCategory(
        serviceId: 6, type: '06', name: '餐廳訂位', description: '餐廳訂位與候位提醒'),
    ServiceCategory(
        serviceId: 9, type: '09', name: '美食外送', description: '美食外送到府'),
    ServiceCategory(
        serviceId: 10, type: '10', name: '水電修繕', description: '水電、五金、居家修繕'),
    ServiceCategory(
        serviceId: 11, type: '11', name: '商城購物', description: '生活選物、商城採購'),
  ];

  /// serviceId → 該類別的服務商清單。
  static final Map<int, List<VendorSummary>> vendorsByService =
      <int, List<VendorSummary>>{
    1: <VendorSummary>[
      _vendor(101, '晴天居家清潔', '深度打掃、到府估價', tags: ['提供女技師', '可指定時段']),
      _vendor(102, '潔淨管家', '整宅清潔、開荒清潔', tags: ['提供女技師', '可開發票']),
      _vendor(103, '小蜂清潔', '單點清潔、彈性排班', tags: ['彈性排班', '當日預約']),
    ],
    2: <VendorSummary>[
      _vendor(201, '涼風家電服務', '冷氣分離式清洗、除菌保養', tags: ['原廠認證', '提供保固']),
      _vendor(202, '樂活家電', '洗衣機／冰箱深層清洗', tags: ['環保清潔劑', '當日預約']),
    ],
    3: <VendorSummary>[
      _vendor(301, '快遞小舖', '同城快遞、隔日送達', tags: ['冷凍配送', '大型物件']),
      _vendor(302, '安心宅配', '大型家具宅配', tags: ['大型物件', '到付可']),
    ],
    6: <VendorSummary>[
      _vendor(601, '巷口小館', '合菜、聚餐首選', tags: ['可帶寵物', '有包廂']),
      _vendor(602, '海景鐵板燒', '約會、慶生場合', tags: ['無障礙設施', '可帶寵物']),
    ],
    9: <VendorSummary>[
      _vendor(901, '雲端便當', '中式便當快速外送', tags: ['素食選項', '30分鐘送達']),
      _vendor(902, '樂送美食', '多元餐廳集合外送', tags: ['免運費', '可預約時段']),
    ],
    10: <VendorSummary>[
      _vendor(1001, '安心水電行', '水電修繕、緊急搶修', tags: ['24H急修', '提供女技師']),
      _vendor(1002, '巧手修繕坊', '木工、五金、局部裝修', tags: ['免費估價', '到府服務']),
    ],
    11: <VendorSummary>[
      _vendor(1101, '生活選物社', '居家小物、季節選品', tags: ['免運', '隔日到貨']),
      _vendor(1102, '好物商城', '生活雜貨、日用品採購', tags: ['免運', '7天鑑賞']),
    ],
  };

  static VendorSummary _vendor(
    int id,
    String name,
    String description, {
    List<String> tags = const <String>[],
  }) {
    return VendorSummary(
      vendorId: id,
      name: name,
      description: description,
      imgUrl: 'https://picsum.photos/seed/vendor$id/400/300',
      serviceTags: tags,
      counties: const <String>['01', '02'],
    );
  }

  static VendorDetail detailOf(VendorSummary v, int serviceId) {
    return VendorDetail(
      vendorId: v.vendorId,
      name: v.name,
      description: v.description,
      imgUrl: v.imgUrl,
      serviceTags: v.serviceTags,
      rating: v.rating,
      priceRangeMin: v.priceRangeMin,
      priceRangeMax: v.priceRangeMax,
      isAvailable: v.isAvailable,
      counties: v.counties,
      formId: v.vendorId, // demo 資料：一家服務商對應一份表單。
      serviceId: serviceId,
      introContent: '<p><b>${v.name}</b> 提供 ${v.description}，服務團隊皆經審核，'
          '到府前會先電話確認時間。</p>',
      noticeContent: '<p>1. 請保持聯絡電話暢通。</p><p>2. 現場如需追加項目將另行報價。</p>',
      termsContent: '<p>本服務條款依統一資訊平台規範，如需取消請於服務前一日告知。</p>',
    );
  }

  // === 縣市 / 行政區（僅取樣，足以 demo 連動選單）===
  static const List<(String code, String name)> counties = <(String, String)>[
    ('01', '臺北市'),
    ('02', '新北市'),
    ('03', '臺中市'),
  ];

  static const Map<String, List<(String code, String name)>> districtsByCounty =
      <String, List<(String, String)>>{
    '01': <(String, String)>[('001', '中正區'), ('002', '大安區')],
    '02': <(String, String)>[('001', '板橋區'), ('002', '新莊區')],
    '03': <(String, String)>[('001', '西區'), ('002', '北屯區')],
  };

  // === 涵蓋全部 10 種題型的表單定義 ===
  //
  // key 為 formId，與上面的 vendorId 一一對應（見 detailOf）。
  static FormDefinition formFor(int formId, {required int serviceId}) {
    final isQuotation = serviceId == 1 || serviceId == 2 || serviceId == 10;

    // 依服務類型回傳不同的題組內容（餐廳≠修繕≠清潔）
    final groups = switch (serviceId) {
      6 || 9 => _restaurantFormGroups,
      10 => _repairFormGroups,
      _ => _defaultFormGroups(isQuotation),
    };

    final name = switch (serviceId) {
      6 => '餐廳訂位諮詢單',
      9 => '美食外送諮詢單',
      10 => '水電修繕諮詢單',
      1 => '居家清潔諮詢單',
      2 => '家電清洗諮詢單',
      _ => '服務諮詢單',
    };

    return FormDefinition(
      formId: formId,
      serviceVendorId: formId,
      serviceId: serviceId,
      name: name,
      subType: isQuotation ? '2' : '1',
      introContent: '<p>請填寫以下資訊，服務團隊將盡快與您聯繫。</p>',
      noticeContent: '<p>填寫時間約 3 分鐘，可先儲存草稿。</p>',
      termsContent: '<p>送出即表示同意由服務商依填寫內容主動聯繫您。</p>',
      groups: groups,
    );
  }

  /// 餐廳/外送專用題組
  static const List<FormGroup> _restaurantFormGroups = <FormGroup>[
    FormGroup(id: 1, name: '訂位資訊', sort: 1, topics: <FormTopic>[
      FormTopic(
          topicId: 1,
          type: TopicType.date,
          title: '用餐日期',
          isRequired: true,
          sort: 1,
          startDateOffsetDays: 0,
          endDateOffsetDays: 30),
      FormTopic(
          topicId: 2,
          type: TopicType.shortText,
          title: '用餐人數',
          isRequired: true,
          sort: 2,
          isNumberOnly: true),
      FormTopic(
          topicId: 3,
          type: TopicType.singleChoice,
          title: '用餐時段',
          isRequired: true,
          sort: 3,
          options: <TopicOption>[
            TopicOption(id: 31, optionName: '午餐（11:30-14:00）'),
            TopicOption(id: 32, optionName: '晚餐（17:30-21:00）'),
          ]),
      FormTopic(
          topicId: 4,
          type: TopicType.longText,
          title: '特殊需求',
          remark: '如過敏食材、兒童座椅、慶生布置等',
          sort: 4),
    ]),
    FormGroup(id: 2, name: '聯絡資訊', sort: 2, topics: <FormTopic>[
      FormTopic(
          topicId: 5,
          type: TopicType.contactWithoutAddress,
          title: '聯絡人資料',
          isRequired: true,
          sort: 5),
    ]),
  ];

  /// 修繕專用題組
  static const List<FormGroup> _repairFormGroups = <FormGroup>[
    FormGroup(id: 1, name: '修繕需求', sort: 1, topics: <FormTopic>[
      FormTopic(
          topicId: 1,
          type: TopicType.singleChoice,
          title: '修繕類型',
          isRequired: true,
          sort: 1,
          options: <TopicOption>[
            TopicOption(id: 11, optionName: '水管漏水'),
            TopicOption(id: 12, optionName: '電路問題'),
            TopicOption(id: 13, optionName: '馬桶堵塞'),
            TopicOption(id: 14, optionName: '其他'),
          ]),
      FormTopic(
          topicId: 2,
          type: TopicType.singleChoice,
          title: '緊急程度',
          isRequired: true,
          sort: 2,
          options: <TopicOption>[
            TopicOption(id: 21, optionName: '一般排程（3 天內）'),
            TopicOption(id: 22, optionName: '盡快（24 小時內）'),
            TopicOption(
                id: 23, optionName: '緊急（今日內）', unitPrice: 500, unit: '元加急費'),
          ]),
      FormTopic(
          topicId: 3,
          type: TopicType.longText,
          title: '問題描述',
          remark: '描述狀況、位置、何時開始等',
          isRequired: true,
          sort: 3),
      FormTopic(
          topicId: 4,
          type: TopicType.photo,
          title: '現場照片',
          remark: '上傳照片有助於師傅備料與報價',
          sort: 4,
          minMedias: 0,
          maxMedias: 5),
    ]),
    FormGroup(id: 2, name: '服務地址與聯絡', sort: 2, topics: <FormTopic>[
      FormTopic(
          topicId: 5,
          type: TopicType.contactWithAddress,
          title: '聯絡資料與服務地址',
          isRequired: true,
          sort: 5),
      FormTopic(
          topicId: 6,
          type: TopicType.date,
          title: '希望到府日期',
          isRequired: true,
          sort: 6,
          startDateOffsetDays: 0,
          endDateOffsetDays: 14),
    ]),
  ];

  /// 通用題組（清潔、家電、寄件、商城等）
  static List<FormGroup> _defaultFormGroups(bool isQuotation) {
    return const <FormGroup>[
      FormGroup(
        id: 1,
        name: '需求說明',
        sort: 1,
        topics: <FormTopic>[
          FormTopic(
            topicId: 1,
            type: TopicType.shortText,
            title: '您的稱呼',
            isRequired: true,
            sort: 1,
          ),
          FormTopic(
            topicId: 2,
            type: TopicType.longText,
            title: '請描述您的需求',
            remark: '例如：想清潔的空間大小、家電種類、需要修繕的項目等',
            isRequired: true,
            sort: 2,
          ),
          FormTopic(
            topicId: 3,
            type: TopicType.singleChoice,
            title: '希望服務的緊急程度',
            isRequired: true,
            sort: 3,
            options: <TopicOption>[
              TopicOption(id: 31, optionName: '一般排程（3 天內）'),
              TopicOption(id: 32, optionName: '盡快（24 小時內）'),
              TopicOption(
                  id: 33, optionName: '緊急（今日內）', unitPrice: 300, unit: '元加值'),
            ],
          ),
          FormTopic(
            topicId: 4,
            type: TopicType.multiChoice,
            title: '需要的加值服務',
            remark: '可多選，將依所選項目試算金額',
            sort: 4,
            options: <TopicOption>[
              TopicOption(
                  id: 41, optionName: '基礎清潔', unitPrice: 800, unit: '元'),
              TopicOption(
                id: 42,
                optionName: '玻璃窗清潔',
                unitPrice: 200,
                unit: '元/面',
                isQuantity: true,
                minQuantity: 1,
                maxQuantity: 10,
              ),
              TopicOption(
                id: 43,
                optionName: '特殊污垢處理',
                unitPrice: 0,
                isQuotedSeparately: true,
                remark: '現場評估後報價',
              ),
            ],
          ),
          FormTopic(
            topicId: 5,
            type: TopicType.region,
            title: '服務地區',
            remark: '用於判斷服務商是否可服務此地區',
            isRequired: true,
            sort: 5,
          ),
          FormTopic(
            topicId: 6,
            type: TopicType.photo,
            title: '現場照片',
            remark: '有助於服務商提前準備工具與報價',
            sort: 6,
            minMedias: 1,
            maxMedias: 5,
          ),
          FormTopic(
            topicId: 7,
            type: TopicType.notice,
            title: '溫馨提醒',
            remark: '服務當日請保持現場動線暢通，並妥善收納貴重物品。',
            sort: 7,
          ),
        ],
      ),
      FormGroup(
        id: 2,
        name: '聯絡與時間',
        sort: 2,
        topics: <FormTopic>[
          FormTopic(
            topicId: 8,
            type: TopicType.contactWithAddress,
            title: '聯絡資料',
            isRequired: true,
            sort: 8,
          ),
          FormTopic(
            topicId: 9,
            type: TopicType.date,
            title: '希望服務日期',
            isRequired: true,
            sort: 9,
            startDateOffsetDays: 1,
            endDateOffsetDays: 30,
          ),
          FormTopic(
            topicId: 10,
            type: TopicType.contactWithoutAddress,
            title: '備用聯絡人（選填）',
            sort: 10,
          ),
        ],
      ),
    ];
  }

  // === 22 種訂單狀態各一筆（Requirement 15.5、附錄 B）===
  static final List<OrderItem> allOrderStatuses = <OrderItem>[
    for (final s in <String>[
      '11',
      '12',
      '13',
      '14',
      '15',
      '80',
      '90',
      '98',
      '99'
    ])
      _order('01', s),
    for (final s in <String>['01', '02', '03', '04', '70', '80', '90', '99'])
      _order('02', s),
    for (final s in <String>['01', '02', '03', '04', '80', '90', '99'])
      _order('03', s),
  ];

  static int _orderSeq = 0;

  static OrderItem _order(String type, String status) {
    _orderSeq++;
    return OrderItem(
      orderNo: 'ORD${type}_${status}_${_orderSeq.toString().padLeft(3, '0')}',
      orderType: type,
      orderStatus: status,
      finalAmount: 100 * _orderSeq,
      orderTime: DateTime(2026, 7, 20).add(Duration(hours: _orderSeq)),
      serviceName: categories[_orderSeq % categories.length].name,
      contactMobile: '0912345678',
    );
  }

  static final List<ConsultationItem> consultations = <ConsultationItem>[
    ConsultationItem(
      feedbackNo: 'FB20260728001',
      serviceName: '一般居家清潔',
      submittedAt: DateTime(2026, 7, 28, 10, 30),
      status: '未讀',
    ),
    ConsultationItem(
      feedbackNo: 'FB20260729002',
      serviceName: '水電修繕',
      submittedAt: DateTime(2026, 7, 29, 15, 0),
      status: '已受理',
    ),
  ];
}
