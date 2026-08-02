import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_butler_app/domain/services/butler_ai_service.dart';
import 'package:ai_butler_app/features/tour/tour_session.dart';

/// 跨畫面導覽的狀態機。
///
/// `started` 旗標是防止重複彈光圈的關鍵：畫面的 build 會因為資料載入、
/// 捲動、鍵盤彈出而重跑好幾次，沒有它就會排進多個啟動 callback。
void main() {
  late ProviderContainer container;

  const card = PrefillCard(
    serviceId: 20,
    formId: 22,
    filledCount: 3,
    remainingRequired: 0,
    summary: '測試草稿',
    vendorId: 101,
    serviceType: '6',
  );

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  TourSession? read() => container.read(tourSessionProvider);
  TourSessionNotifier notifier() =>
      container.read(tourSessionProvider.notifier);

  test('一開始沒有進行中的導覽', () {
    expect(read(), isNull);
  });

  test('start 從首頁那一段開始，且尚未啟動', () {
    notifier().start(card);

    expect(read()!.leg, TourLeg.home);
    expect(read()!.started, isFalse);
    expect(read()!.card.vendorId, 101);
  });

  test('markStarted 只生效一次，重複呼叫不會改變狀態', () {
    notifier().start(card);
    notifier().markStarted();
    final first = read();

    notifier().markStarted();

    expect(read()!.started, isTrue);
    // 同一個實例，代表沒有多發一次狀態變更（否則畫面會重跑 listener）
    expect(read(), same(first));
  });

  test('advanceTo 會把 started 重置，否則下一段不會啟動', () {
    notifier().start(card);
    notifier().markStarted();

    notifier().advanceTo(TourLeg.vendorList);

    expect(read()!.leg, TourLeg.vendorList);
    expect(read()!.started, isFalse);
  });

  test('advanceTo 保留草稿內容', () {
    notifier().start(card);
    notifier().advanceTo(TourLeg.vendorDetail);

    expect(read()!.card.formId, 22);
    expect(read()!.card.serviceId, 20);
  });

  test('finish 清空，之後的 markStarted / advanceTo 不會復活它', () {
    notifier().start(card);
    notifier().finish();
    expect(read(), isNull);

    notifier().markStarted();
    notifier().advanceTo(TourLeg.vendorList);

    expect(read(), isNull);
  });

  test('完整走一遍三段導航', () {
    notifier().start(card);
    expect(read()!.leg, TourLeg.home);

    notifier().markStarted();
    notifier().advanceTo(TourLeg.vendorList);
    expect(read()!.leg, TourLeg.vendorList);

    notifier().markStarted();
    notifier().advanceTo(TourLeg.vendorDetail);
    expect(read()!.leg, TourLeg.vendorDetail);

    // 商家詳情那一段點下去後交棒給表單頁，session 結束
    notifier().finish();
    expect(read(), isNull);
  });

  group('服務類型正規化', () {
    // App 裡兩個資料來源的格式不一致：mock 是補零的 '06'，
    // 真實 API 是 '6'。導覽比對分類時兩邊都要正規化，否則接真實後端就中斷。
    test('一位數補零，兩位數不動', () {
      expect(PrefillCard.normalizeServiceType('6'), '06');
      expect(PrefillCard.normalizeServiceType('10'), '10');
      expect(PrefillCard.normalizeServiceType('11'), '11');
    });

    test('前後空白不影響', () {
      expect(PrefillCard.normalizeServiceType(' 6 '), '06');
    });

    test('agent 的未補零值能對上真實 API 的分類代碼', () {
      // agent 給 '6'，http_vendor_repository 產生的分類也是 '6'
      expect(
        PrefillCard.normalizeServiceType('6'),
        card.normalizedServiceType,
      );
    });

    test('agent 的未補零值也能對上 mock 的補零代碼', () {
      // mock_seed_data 產生的分類是 '06'
      expect(
        PrefillCard.normalizeServiceType('06'),
        card.normalizedServiceType,
      );
    });

    test('原始 serviceType 不被改動（打 API 要用未補零的）', () {
      expect(card.serviceType, '6');
    });
  });
}
