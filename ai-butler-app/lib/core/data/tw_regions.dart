// GENERATED — 請勿手改。
// 來源：Database/database/縣市區域範例資料.json（sys_county / sys_district）
//
// code 必須與資料庫一致：feedback 的 contact_address_county /
// contact_address_district 存的就是這裡的 code。

import 'package:flutter/foundation.dart';

/// 縣市。
@immutable
class TwCounty {
  const TwCounty({required this.code, required this.name});

  final String code;
  final String name;
}

/// 行政區。
@immutable
class TwDistrict {
  const TwDistrict({
    required this.code,
    required this.countyCode,
    required this.name,
    required this.zip,
  });

  final String code;
  final String countyCode;
  final String name;
  final String zip;
}

/// 台灣縣市 / 行政區主檔（內建靜態資料）。
///
/// 後端沒有開放地區主檔查詢端點，且這份資料極少變動，
/// 因此內建在 App 內，避免每次開表單都要多打一支 API。
class TwRegions {
  TwRegions._();

  static const List<TwCounty> counties = <TwCounty>[
    TwCounty(code: '01', name: '台北市'),
    TwCounty(code: '02', name: '新北市'),
    TwCounty(code: '03', name: '基隆市'),
    TwCounty(code: '04', name: '桃園市'),
    TwCounty(code: '05', name: '新竹縣'),
    TwCounty(code: '06', name: '新竹市'),
    TwCounty(code: '07', name: '苗栗縣'),
    TwCounty(code: '08', name: '台中市'),
    TwCounty(code: '09', name: '南投縣'),
    TwCounty(code: '10', name: '彰化縣'),
    TwCounty(code: '11', name: '雲林縣'),
    TwCounty(code: '12', name: '嘉義縣'),
    TwCounty(code: '13', name: '嘉義市'),
    TwCounty(code: '14', name: '台南市'),
    TwCounty(code: '15', name: '高雄市'),
    TwCounty(code: '16', name: '屏東縣'),
    TwCounty(code: '17', name: '宜蘭縣'),
    TwCounty(code: '18', name: '花蓮縣'),
    TwCounty(code: '19', name: '台東縣'),
    TwCounty(code: '20', name: '澎湖縣'),
    TwCounty(code: '21', name: '金門縣'),
    TwCounty(code: '22', name: '連江縣'),
  ];

  /// county code → 該縣市的行政區清單。
  static const Map<String, List<TwDistrict>> districtsByCounty =
      <String, List<TwDistrict>>{
    '01': <TwDistrict>[
      TwDistrict(code: '001', countyCode: '01', name: '中正區', zip: '100'),
      TwDistrict(code: '002', countyCode: '01', name: '大同區', zip: '103'),
      TwDistrict(code: '003', countyCode: '01', name: '中山區', zip: '104'),
      TwDistrict(code: '004', countyCode: '01', name: '萬華區', zip: '108'),
      TwDistrict(code: '005', countyCode: '01', name: '信義區', zip: '110'),
      TwDistrict(code: '006', countyCode: '01', name: '松山區', zip: '105'),
      TwDistrict(code: '007', countyCode: '01', name: '大安區', zip: '106'),
      TwDistrict(code: '008', countyCode: '01', name: '南港區', zip: '115'),
      TwDistrict(code: '009', countyCode: '01', name: '北投區', zip: '112'),
      TwDistrict(code: '010', countyCode: '01', name: '內湖區', zip: '114'),
      TwDistrict(code: '011', countyCode: '01', name: '士林區', zip: '111'),
      TwDistrict(code: '012', countyCode: '01', name: '文山區', zip: '116'),
    ],
    '02': <TwDistrict>[
      TwDistrict(code: '013', countyCode: '02', name: '板橋區', zip: '220'),
      TwDistrict(code: '014', countyCode: '02', name: '新莊區', zip: '242'),
      TwDistrict(code: '015', countyCode: '02', name: '泰山區', zip: '243'),
      TwDistrict(code: '016', countyCode: '02', name: '林口區', zip: '244'),
      TwDistrict(code: '017', countyCode: '02', name: '淡水區', zip: '251'),
      TwDistrict(code: '018', countyCode: '02', name: '金山區', zip: '208'),
      TwDistrict(code: '019', countyCode: '02', name: '八里區', zip: '249'),
      TwDistrict(code: '020', countyCode: '02', name: '萬里區', zip: '207'),
      TwDistrict(code: '021', countyCode: '02', name: '石門區', zip: '253'),
      TwDistrict(code: '022', countyCode: '02', name: '三芝區', zip: '252'),
      TwDistrict(code: '023', countyCode: '02', name: '瑞芳區', zip: '224'),
      TwDistrict(code: '024', countyCode: '02', name: '汐止區', zip: '221'),
      TwDistrict(code: '025', countyCode: '02', name: '平溪區', zip: '226'),
      TwDistrict(code: '026', countyCode: '02', name: '貢寮區', zip: '228'),
      TwDistrict(code: '027', countyCode: '02', name: '雙溪區', zip: '227'),
      TwDistrict(code: '028', countyCode: '02', name: '深坑區', zip: '222'),
      TwDistrict(code: '029', countyCode: '02', name: '石碇區', zip: '223'),
      TwDistrict(code: '030', countyCode: '02', name: '新店區', zip: '231'),
      TwDistrict(code: '031', countyCode: '02', name: '坪林區', zip: '232'),
      TwDistrict(code: '032', countyCode: '02', name: '烏來區', zip: '233'),
      TwDistrict(code: '033', countyCode: '02', name: '中和區', zip: '235'),
      TwDistrict(code: '034', countyCode: '02', name: '永和區', zip: '234'),
      TwDistrict(code: '035', countyCode: '02', name: '土城區', zip: '236'),
      TwDistrict(code: '036', countyCode: '02', name: '三峽區', zip: '237'),
      TwDistrict(code: '037', countyCode: '02', name: '樹林區', zip: '238'),
      TwDistrict(code: '038', countyCode: '02', name: '鶯歌區', zip: '239'),
      TwDistrict(code: '039', countyCode: '02', name: '三重區', zip: '241'),
      TwDistrict(code: '040', countyCode: '02', name: '蘆洲區', zip: '247'),
      TwDistrict(code: '041', countyCode: '02', name: '五股區', zip: '248'),
    ],
    '03': <TwDistrict>[
      TwDistrict(code: '042', countyCode: '03', name: '仁愛區', zip: '200'),
      TwDistrict(code: '043', countyCode: '03', name: '中正區', zip: '202'),
      TwDistrict(code: '044', countyCode: '03', name: '信義區', zip: '201'),
      TwDistrict(code: '045', countyCode: '03', name: '中山區', zip: '203'),
      TwDistrict(code: '046', countyCode: '03', name: '安樂區', zip: '204'),
      TwDistrict(code: '047', countyCode: '03', name: '暖暖區', zip: '205'),
      TwDistrict(code: '048', countyCode: '03', name: '七堵區', zip: '206'),
    ],
    '04': <TwDistrict>[
      TwDistrict(code: '049', countyCode: '04', name: '桃園區', zip: '330'),
      TwDistrict(code: '050', countyCode: '04', name: '中壢區', zip: '320'),
      TwDistrict(code: '051', countyCode: '04', name: '平鎮區', zip: '324'),
      TwDistrict(code: '052', countyCode: '04', name: '八德區', zip: '334'),
      TwDistrict(code: '053', countyCode: '04', name: '楊梅區', zip: '326'),
      TwDistrict(code: '054', countyCode: '04', name: '蘆竹區', zip: '338'),
      TwDistrict(code: '055', countyCode: '04', name: '龜山區', zip: '333'),
      TwDistrict(code: '056', countyCode: '04', name: '龍潭區', zip: '325'),
      TwDistrict(code: '057', countyCode: '04', name: '大溪區', zip: '335'),
      TwDistrict(code: '058', countyCode: '04', name: '大園區', zip: '337'),
      TwDistrict(code: '059', countyCode: '04', name: '觀音區', zip: '328'),
      TwDistrict(code: '060', countyCode: '04', name: '新屋區', zip: '327'),
      TwDistrict(code: '061', countyCode: '04', name: '復興區', zip: '336'),
    ],
    '05': <TwDistrict>[
      TwDistrict(code: '062', countyCode: '05', name: '竹北市', zip: '302'),
      TwDistrict(code: '063', countyCode: '05', name: '竹東鎮', zip: '310'),
      TwDistrict(code: '064', countyCode: '05', name: '新埔鎮', zip: '305'),
      TwDistrict(code: '065', countyCode: '05', name: '關西鎮', zip: '306'),
      TwDistrict(code: '066', countyCode: '05', name: '峨眉鄉', zip: '315'),
      TwDistrict(code: '067', countyCode: '05', name: '寶山鄉', zip: '308'),
      TwDistrict(code: '068', countyCode: '05', name: '北埔鄉', zip: '314'),
      TwDistrict(code: '069', countyCode: '05', name: '橫山鄉', zip: '312'),
    ],
    '06': <TwDistrict>[
    ],
    '07': <TwDistrict>[
    ],
    '08': <TwDistrict>[
    ],
    '09': <TwDistrict>[
    ],
    '10': <TwDistrict>[
    ],
    '11': <TwDistrict>[
    ],
    '12': <TwDistrict>[
    ],
    '13': <TwDistrict>[
    ],
    '14': <TwDistrict>[
      TwDistrict(code: '238', countyCode: '14', name: '山上區', zip: '743'),
      TwDistrict(code: '239', countyCode: '14', name: '新市區', zip: '744'),
      TwDistrict(code: '240', countyCode: '14', name: '安定區', zip: '745'),
    ],
    '15': <TwDistrict>[
      TwDistrict(code: '241', countyCode: '15', name: '楠梓區', zip: '811'),
      TwDistrict(code: '242', countyCode: '15', name: '左營區', zip: '813'),
      TwDistrict(code: '243', countyCode: '15', name: '鼓山區', zip: '804'),
      TwDistrict(code: '244', countyCode: '15', name: '三民區', zip: '807'),
      TwDistrict(code: '245', countyCode: '15', name: '鹽埕區', zip: '803'),
      TwDistrict(code: '246', countyCode: '15', name: '前金區', zip: '801'),
      TwDistrict(code: '247', countyCode: '15', name: '新興區', zip: '800'),
      TwDistrict(code: '248', countyCode: '15', name: '苓雅區', zip: '802'),
      TwDistrict(code: '249', countyCode: '15', name: '前鎮區', zip: '806'),
      TwDistrict(code: '250', countyCode: '15', name: '小港區', zip: '812'),
      TwDistrict(code: '251', countyCode: '15', name: '旗津區', zip: '805'),
      TwDistrict(code: '252', countyCode: '15', name: '鳳山區', zip: '830'),
      TwDistrict(code: '253', countyCode: '15', name: '大寮區', zip: '831'),
      TwDistrict(code: '254', countyCode: '15', name: '鳥松區', zip: '833'),
      TwDistrict(code: '255', countyCode: '15', name: '林園區', zip: '832'),
      TwDistrict(code: '256', countyCode: '15', name: '仁武區', zip: '814'),
      TwDistrict(code: '257', countyCode: '15', name: '大樹區', zip: '840'),
      TwDistrict(code: '258', countyCode: '15', name: '大社區', zip: '815'),
      TwDistrict(code: '259', countyCode: '15', name: '岡山區', zip: '820'),
      TwDistrict(code: '260', countyCode: '15', name: '路竹區', zip: '821'),
      TwDistrict(code: '261', countyCode: '15', name: '橋頭區', zip: '825'),
      TwDistrict(code: '262', countyCode: '15', name: '梓官區', zip: '826'),
      TwDistrict(code: '263', countyCode: '15', name: '彌陀區', zip: '827'),
      TwDistrict(code: '264', countyCode: '15', name: '永安區', zip: '828'),
      TwDistrict(code: '265', countyCode: '15', name: '燕巢區', zip: '824'),
      TwDistrict(code: '266', countyCode: '15', name: '田寮區', zip: '823'),
      TwDistrict(code: '267', countyCode: '15', name: '阿蓮區', zip: '822'),
      TwDistrict(code: '268', countyCode: '15', name: '茄萣區', zip: '852'),
      TwDistrict(code: '269', countyCode: '15', name: '湖內區', zip: '829'),
      TwDistrict(code: '270', countyCode: '15', name: '旗山區', zip: '842'),
      TwDistrict(code: '271', countyCode: '15', name: '美濃區', zip: '843'),
      TwDistrict(code: '272', countyCode: '15', name: '內門區', zip: '845'),
      TwDistrict(code: '273', countyCode: '15', name: '杉林區', zip: '846'),
      TwDistrict(code: '274', countyCode: '15', name: '甲仙區', zip: '847'),
      TwDistrict(code: '275', countyCode: '15', name: '六龜區', zip: '844'),
      TwDistrict(code: '276', countyCode: '15', name: '茂林區', zip: '851'),
      TwDistrict(code: '277', countyCode: '15', name: '桃源區', zip: '848'),
      TwDistrict(code: '278', countyCode: '15', name: '那瑪夏區', zip: '849'),
    ],
    '16': <TwDistrict>[
      TwDistrict(code: '279', countyCode: '16', name: '屏東市', zip: '900'),
      TwDistrict(code: '280', countyCode: '16', name: '潮州鎮', zip: '920'),
      TwDistrict(code: '281', countyCode: '16', name: '東港鎮', zip: '928'),
      TwDistrict(code: '282', countyCode: '16', name: '恆春鎮', zip: '946'),
      TwDistrict(code: '283', countyCode: '16', name: '萬丹鄉', zip: '913'),
      TwDistrict(code: '284', countyCode: '16', name: '長治鄉', zip: '908'),
      TwDistrict(code: '285', countyCode: '16', name: '麟洛鄉', zip: '909'),
      TwDistrict(code: '286', countyCode: '16', name: '九如鄉', zip: '904'),
      TwDistrict(code: '287', countyCode: '16', name: '里港鄉', zip: '905'),
      TwDistrict(code: '288', countyCode: '16', name: '鹽埔鄉', zip: '907'),
      TwDistrict(code: '289', countyCode: '16', name: '高樹鄉', zip: '906'),
      TwDistrict(code: '290', countyCode: '16', name: '萬巒鄉', zip: '923'),
      TwDistrict(code: '291', countyCode: '16', name: '內埔鄉', zip: '912'),
      TwDistrict(code: '292', countyCode: '16', name: '竹田鄉', zip: '911'),
      TwDistrict(code: '293', countyCode: '16', name: '新埤鄉', zip: '925'),
      TwDistrict(code: '294', countyCode: '16', name: '枋寮鄉', zip: '940'),
      TwDistrict(code: '295', countyCode: '16', name: '新園鄉', zip: '932'),
      TwDistrict(code: '296', countyCode: '16', name: '崁頂鄉', zip: '924'),
      TwDistrict(code: '297', countyCode: '16', name: '林邊鄉', zip: '927'),
      TwDistrict(code: '298', countyCode: '16', name: '南州鄉', zip: '926'),
      TwDistrict(code: '299', countyCode: '16', name: '佳冬鄉', zip: '931'),
      TwDistrict(code: '300', countyCode: '16', name: '琉球鄉', zip: '929'),
      TwDistrict(code: '301', countyCode: '16', name: '車城鄉', zip: '944'),
      TwDistrict(code: '302', countyCode: '16', name: '滿州鄉', zip: '947'),
      TwDistrict(code: '303', countyCode: '16', name: '枋山鄉', zip: '941'),
      TwDistrict(code: '304', countyCode: '16', name: '霧台鄉', zip: '902'),
      TwDistrict(code: '305', countyCode: '16', name: '瑪家鄉', zip: '903'),
      TwDistrict(code: '306', countyCode: '16', name: '泰武鄉', zip: '921'),
      TwDistrict(code: '307', countyCode: '16', name: '來義鄉', zip: '922'),
      TwDistrict(code: '308', countyCode: '16', name: '春日鄉', zip: '942'),
      TwDistrict(code: '309', countyCode: '16', name: '獅子鄉', zip: '943'),
      TwDistrict(code: '310', countyCode: '16', name: '牡丹鄉', zip: '945'),
      TwDistrict(code: '311', countyCode: '16', name: '三地門鄉', zip: '901'),
    ],
    '17': <TwDistrict>[
      TwDistrict(code: '312', countyCode: '17', name: '宜蘭市', zip: '260'),
      TwDistrict(code: '313', countyCode: '17', name: '羅東鎮', zip: '265'),
      TwDistrict(code: '314', countyCode: '17', name: '蘇澳鎮', zip: '270'),
      TwDistrict(code: '315', countyCode: '17', name: '頭城鎮', zip: '261'),
      TwDistrict(code: '316', countyCode: '17', name: '礁溪鄉', zip: '262'),
      TwDistrict(code: '317', countyCode: '17', name: '壯圍鄉', zip: '263'),
      TwDistrict(code: '318', countyCode: '17', name: '員山鄉', zip: '264'),
      TwDistrict(code: '319', countyCode: '17', name: '冬山鄉', zip: '269'),
      TwDistrict(code: '320', countyCode: '17', name: '五結鄉', zip: '268'),
      TwDistrict(code: '321', countyCode: '17', name: '三星鄉', zip: '266'),
      TwDistrict(code: '322', countyCode: '17', name: '大同鄉', zip: '267'),
      TwDistrict(code: '323', countyCode: '17', name: '南澳鄉', zip: '272'),
    ],
    '18': <TwDistrict>[
      TwDistrict(code: '324', countyCode: '18', name: '花蓮市', zip: '970'),
      TwDistrict(code: '325', countyCode: '18', name: '鳳林鎮', zip: '975'),
      TwDistrict(code: '326', countyCode: '18', name: '玉里鎮', zip: '981'),
      TwDistrict(code: '327', countyCode: '18', name: '新城鄉', zip: '971'),
      TwDistrict(code: '328', countyCode: '18', name: '吉安鄉', zip: '973'),
      TwDistrict(code: '329', countyCode: '18', name: '壽豐鄉', zip: '974'),
      TwDistrict(code: '330', countyCode: '18', name: '秀林鄉', zip: '972'),
      TwDistrict(code: '331', countyCode: '18', name: '光復鄉', zip: '976'),
      TwDistrict(code: '332', countyCode: '18', name: '豐濱鄉', zip: '977'),
      TwDistrict(code: '333', countyCode: '18', name: '瑞穗鄉', zip: '978'),
      TwDistrict(code: '334', countyCode: '18', name: '萬榮鄉', zip: '979'),
      TwDistrict(code: '335', countyCode: '18', name: '富里鄉', zip: '983'),
      TwDistrict(code: '336', countyCode: '18', name: '卓溪鄉', zip: '982'),
    ],
    '19': <TwDistrict>[
      TwDistrict(code: '337', countyCode: '19', name: '台東市', zip: '950'),
      TwDistrict(code: '338', countyCode: '19', name: '成功鎮', zip: '961'),
      TwDistrict(code: '339', countyCode: '19', name: '關山鎮', zip: '956'),
      TwDistrict(code: '340', countyCode: '19', name: '長濱鄉', zip: '962'),
      TwDistrict(code: '341', countyCode: '19', name: '海端鄉', zip: '957'),
      TwDistrict(code: '342', countyCode: '19', name: '池上鄉', zip: '958'),
      TwDistrict(code: '343', countyCode: '19', name: '東河鄉', zip: '959'),
      TwDistrict(code: '344', countyCode: '19', name: '鹿野鄉', zip: '955'),
      TwDistrict(code: '345', countyCode: '19', name: '延平鄉', zip: '953'),
      TwDistrict(code: '346', countyCode: '19', name: '卑南鄉', zip: '954'),
      TwDistrict(code: '347', countyCode: '19', name: '金峰鄉', zip: '964'),
      TwDistrict(code: '348', countyCode: '19', name: '大武鄉', zip: '965'),
      TwDistrict(code: '349', countyCode: '19', name: '達仁鄉', zip: '966'),
      TwDistrict(code: '350', countyCode: '19', name: '綠島鄉', zip: '951'),
      TwDistrict(code: '351', countyCode: '19', name: '蘭嶼鄉', zip: '952'),
      TwDistrict(code: '352', countyCode: '19', name: '太麻里鄉', zip: '963'),
    ],
    '20': <TwDistrict>[
      TwDistrict(code: '353', countyCode: '20', name: '馬公市', zip: '880'),
      TwDistrict(code: '354', countyCode: '20', name: '湖西鄉', zip: '885'),
      TwDistrict(code: '355', countyCode: '20', name: '白沙鄉', zip: '884'),
      TwDistrict(code: '356', countyCode: '20', name: '西嶼鄉', zip: '881'),
      TwDistrict(code: '357', countyCode: '20', name: '望安鄉', zip: '882'),
      TwDistrict(code: '358', countyCode: '20', name: '七美鄉', zip: '883'),
    ],
    '21': <TwDistrict>[
      TwDistrict(code: '359', countyCode: '21', name: '金城鎮', zip: '893'),
      TwDistrict(code: '360', countyCode: '21', name: '金湖鎮', zip: '891'),
      TwDistrict(code: '361', countyCode: '21', name: '金沙鎮', zip: '890'),
      TwDistrict(code: '362', countyCode: '21', name: '金寧鄉', zip: '892'),
      TwDistrict(code: '363', countyCode: '21', name: '烈嶼鄉', zip: '894'),
      TwDistrict(code: '364', countyCode: '21', name: '烏坵鄉', zip: '896'),
    ],
    '22': <TwDistrict>[
      TwDistrict(code: '365', countyCode: '22', name: '南竿鄉', zip: '209'),
      TwDistrict(code: '366', countyCode: '22', name: '北竿鄉', zip: '210'),
      TwDistrict(code: '367', countyCode: '22', name: '莒光鄉', zip: '211'),
      TwDistrict(code: '368', countyCode: '22', name: '東引鄉', zip: '212'),
    ],
  };

  /// 依 code 找縣市名稱，找不到回傳 null。
  static String? countyName(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final county in counties) {
      if (county.code == code) return county.name;
    }
    return null;
  }

  /// 依 code 找行政區名稱，找不到回傳 null。
  static String? districtName(String? countyCode, String? code) {
    if (countyCode == null || code == null) return null;
    for (final district in districtsOf(countyCode)) {
      if (district.code == code) return district.name;
    }
    return null;
  }

  /// 該縣市的行政區清單（無資料時回傳空清單）。
  static List<TwDistrict> districtsOf(String? countyCode) {
    if (countyCode == null || countyCode.isEmpty) {
      return const <TwDistrict>[];
    }
    return districtsByCounty[countyCode] ?? const <TwDistrict>[];
  }
}
