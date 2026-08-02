import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_butler_app/features/tour/tour_plan.dart';

/// 跨畫面導覽的三個導航段（首頁 → 服務商列表 → 商家詳情）。
///
/// 這幾段的關鍵性質是「必須靠點擊目標前進」：
/// `tutorial_coach_mark` 會攔截光圈區域的點擊，底下的 widget 收不到，
/// 所以導航是由 TourStep.onTap 執行的。若這種步驟同時給了「下一步」按鈕，
/// 使用者按了會跳步但畫面沒切換，導覽就錯位。TourRunner 靠 requiresTap
/// 決定要不要顯示那顆按鈕，所以這裡直接驗 requiresTap。
void main() {
  group('首頁段', () {
    test('要靠點擊前進，不是交棒點', () {
      var tapped = false;
      final steps = TourPlan.homeLeg(
        categoryAnchor: GlobalKey(),
        categoryName: '餐廳訂位',
        onTap: () => tapped = true,
      );

      expect(steps.length, 1);
      expect(steps.single.requiresTap, isTrue);
      expect(steps.single.handOff, isFalse);

      steps.single.onTap!();
      expect(tapped, isTrue);
    });

    test('文案帶出類別名稱，並告訴使用者以後怎麼自己來', () {
      final steps = TourPlan.homeLeg(
        categoryAnchor: GlobalKey(),
        categoryName: '餐廳訂位',
        onTap: () {},
      );

      expect(steps.single.instruction, contains('餐廳訂位'));
      // 導覽的目的是教他下次自己會用，不是只帶他點一次
      expect(steps.single.instruction, contains('以後'));
    });
  });

  group('服務商列表段', () {
    test('文案指出哪一家是管家推薦的', () {
      final steps = TourPlan.vendorListLeg(
        vendorAnchor: GlobalKey(),
        vendorName: '鳥花枝居酒屋',
        onTap: () {},
      );

      expect(steps.length, 1);
      expect(steps.single.instruction, contains('鳥花枝居酒屋'));
      expect(steps.single.requiresTap, isTrue);
    });
  });

  group('商家詳情段', () {
    test('要靠點擊前進', () {
      var tapped = false;
      final steps = TourPlan.vendorDetailLeg(
        submitAnchor: GlobalKey(),
        onTap: () => tapped = true,
      );

      expect(steps.length, 1);
      expect(steps.single.requiresTap, isTrue);
      steps.single.onTap!();
      expect(tapped, isTrue);
    });
  });

  test('導航段全部都是單步，不會一次彈兩個光圈', () {
    expect(
      TourPlan.homeLeg(
        categoryAnchor: GlobalKey(),
        categoryName: 'x',
        onTap: () {},
      ).length,
      1,
    );
    expect(
      TourPlan.vendorListLeg(
        vendorAnchor: GlobalKey(),
        vendorName: 'x',
        onTap: () {},
      ).length,
      1,
    );
    expect(
      TourPlan.vendorDetailLeg(submitAnchor: GlobalKey(), onTap: () {}).length,
      1,
    );
  });
}
