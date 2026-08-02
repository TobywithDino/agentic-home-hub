import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 導覽錨點的 id 規則。
///
/// 集中在一處，因為「掛錨點的畫面」跟「產生導覽步驟的 TourPlan」是不同檔案，
/// 兩邊用字串對齊。打錯字的話導覽會安靜地跳過那一步（`currentContext` 為
/// null），所以一律用這裡的函式產生，不要手寫字串。
class TourAnchorIds {
  const TourAnchorIds._();

  /// 首頁的服務類別磚。[serviceType] 要用補零後的兩位數代碼。
  static String homeCategory(String serviceType) => 'home.category.$serviceType';

  /// 服務商列表裡的某一張卡。
  static String vendorCard(int vendorId) => 'vendorList.vendor.$vendorId';

  /// 商家詳情頁底部的「填寫諮詢單」。
  static const String vendorDetailSubmit = 'vendorDetail.submit';

  /// 填單頁的某一題。
  static String formTopic(int topicId) => 'form.topic.$topicId';

  /// 填單頁的送出鈕。
  static const String formSubmit = 'form.submit';
}

/// 跨畫面共用的 [GlobalKey] 登記表。
///
/// 為什麼要有這一層：導覽會從首頁一路走到填單頁，橫跨四個畫面。若每個畫面
/// 自己持有 key，產生步驟的地方就拿不到別的畫面的錨點。放進 provider 讓全域
/// 共用一份，畫面只負責「把 key 掛上去」。
///
/// key 用 `putIfAbsent` 快取，同一個 id 永遠回同一個 key —— 每次 build 換新
/// key 的話，導覽跑到一半就會找不到原來的 widget。
class TourAnchors {
  final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  GlobalKey of(String id) => _keys.putIfAbsent(id, () => GlobalKey());

  /// 該錨點目前是否真的掛在畫面上。
  ///
  /// `currentContext` 為 null 代表 widget 還沒掛載（例如被捲出視野而
  /// ListView 尚未建構，或那個畫面根本不在前景）。
  bool isMounted(String id) => _keys[id]?.currentContext != null;
}

/// 全 App 共用一份。刻意不 autoDispose：導覽跨畫面時中間會有畫面被回收，
/// 登記表跟著消失的話後面的步驟就全部失效。
final tourAnchorsProvider = Provider<TourAnchors>((ref) => TourAnchors());
