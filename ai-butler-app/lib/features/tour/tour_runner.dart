import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/features/tour/tour_step.dart';

/// 執行光圈導覽。
///
/// 包一層而不是讓畫面直接用 `TutorialCoachMark`，是為了把三件事集中處理：
///   1. 過濾掉錨點還沒掛載的步驟（不然套件會拿 null context 崩掉）
///   2. 統一泡泡樣式與文案（「下一步」/「我知道了」）
///   3. 交棒步驟結束後把控制權還給畫面
class TourRunner {
  const TourRunner._();

  /// 開始導覽。回傳 null 表示沒有任何可用步驟，呼叫端可據此決定要不要提示。
  static TutorialCoachMark? start(
    BuildContext context,
    List<TourStep> steps, {
    VoidCallback? onFinish,
  }) {
    // 錨點的 currentContext 為 null 代表那個 widget 還沒掛載（例如被捲出
    // 視野而 ListView 尚未建構）。套件會直接對 null 取 renderBox，
    // 所以要先濾掉，不能指望它容錯。
    final usable = steps
        .where((step) => step.anchorKey.currentContext != null)
        .toList(growable: false);

    if (usable.isEmpty) return null;

    // 點擊分派用的對照表。`onClickTarget` 是 TutorialCoachMark 的**全域**
    // callback（不是 TargetFocus 的欄位），所以要靠 identify 認出是哪一步。
    final byId = <int, TourStep>{
      for (var i = 0; i < usable.length; i++) i: usable[i],
    };

    final tutorial = TutorialCoachMark(
      targets: <TargetFocus>[
        for (var i = 0; i < usable.length; i++)
          _toTarget(usable[i], i, _alignFor(usable[i], MediaQuery.of(context))),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.75,
      paddingFocus: 6,
      hideSkip: false,
      textSkip: '跳過導覽',
      alignSkip: Alignment.topRight,
      // 聚焦前先把目標捲進視野。
      //
      // 套件不會自己捲動，目標在畫面邊緣時光圈會貼著邊、說明也擠在角落
      // （實測圈服務商列表最後幾張卡時就是這樣）。`beforeFocus` 支援
      // FutureOr，所以可以 await 捲動動畫結束再讓光圈定位，否則光圈會
      // 對著捲動前的舊座標挖洞。
      beforeFocus: (target) async {
        final anchorContext = byId[target.identify]?.anchorKey.currentContext;
        if (anchorContext == null) return;
        // 固定位置的元件（底部送出鈕、bottomNavigationBar）沒有可捲動祖先，
        // 先擋掉再呼叫，不要依賴 ensureVisible 的容錯行為。
        if (Scrollable.maybeOf(anchorContext) == null) return;
        await Scrollable.ensureVisible(
          anchorContext,
          // 0.35 讓目標偏上，下方留給說明泡泡
          alignment: 0.35,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      },
      onClickTarget: (target) {
        final step = byId[target.identify];
        // 純解說的步驟沒有 onTap，點了不做事（光圈本身也擋住點擊）
        step?.onTap?.call();
      },
      onFinish: onFinish,
      onSkip: () {
        onFinish?.call();
        return true;
      },
    );

    tutorial.show(context: context);
    return tutorial;
  }

  /// 泡泡要放目標的上面還是下面。
  ///
  /// 固定放下面的話，目標一靠近螢幕底部泡泡就會被切掉（實測在服務商列表
  /// 圈最後幾張卡時說明文字整段看不到）。
  ///
  /// `align` 是 [TargetContent] 的欄位，必須在建立 target 時就決定，不能等到
  /// 真正聚焦才算。而 `beforeFocus` 又會先捲動目標，所以「現在的座標」不能
  /// 直接用。因此分兩種情況：
  ///   - 目標在可捲動區域內 → `beforeFocus` 會把它捲到偏上，下方一定有空間
  ///   - 目標是固定位置的元件（底部的送出鈕、bottomNavigationBar）→ 捲不動，
  ///     要看它實際在哪
  static ContentAlign _alignFor(TourStep step, MediaQueryData media) {
    final anchorContext = step.anchorKey.currentContext;
    if (anchorContext == null) return ContentAlign.bottom;

    if (Scrollable.maybeOf(anchorContext) != null) return ContentAlign.bottom;

    final render = anchorContext.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return ContentAlign.bottom;

    final top = render.localToGlobal(Offset.zero).dy;
    final bottom = top + render.size.height;
    final spaceAbove = top - media.padding.top;
    final spaceBelow = (media.size.height - media.padding.bottom) - bottom;

    return spaceBelow >= spaceAbove ? ContentAlign.bottom : ContentAlign.top;
  }

  static TargetFocus _toTarget(
    TourStep step,
    int identify,
    ContentAlign align,
  ) {
    return TargetFocus(
      identify: identify,
      keyTarget: step.anchorKey,
      // 表單欄位是矩形，用圓形光圈會把旁邊的內容一起圈進來
      shape: ShapeLightFocus.RRect,
      radius: 8,
      // 只有「要使用者點」的步驟才讓光圈可點。
      // 純解說的步驟擋住點擊，避免他不小心改到管家已經填好的值。
      enableTargetTab: step.requiresTap,
      contents: <TargetContent>[
        TargetContent(
          align: align,
          builder: (context, controller) => _Bubble(
            step: step,
            align: align,
            // 導航步驟不給「下一步」：按了會跳步但畫面沒切換，導覽就錯位。
            onNext: step.requiresTap
                ? null
                : (step.handOff ? controller.skip : controller.next),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.step, required this.align, this.onNext});

  final TourStep step;

  /// 泡泡被放在目標的哪一側，決定要量哪一邊的剩餘空間。
  final ContentAlign align;

  /// null 代表這一步只能靠點擊目標前進。
  final VoidCallback? onNext;

  /// 泡泡最多能佔多高。
  ///
  /// 在 build 時量測而不是建立 target 時：`beforeFocus` 會先把目標捲進視野，
  /// 建立 target 那時的座標是舊的，用它算出來的高度會失準。
  double _maxHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final render = step.anchorKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return 240;

    final top = render.localToGlobal(Offset.zero).dy;
    final bottom = top + render.size.height;

    final available = align == ContentAlign.bottom
        ? (media.size.height - media.padding.bottom) - bottom
        : top - media.padding.top;

    // 扣掉光圈的 paddingFocus 與泡泡自己的 margin/padding。
    // 太小的話至少留一點高度，讓內容可以捲動而不是完全看不到。
    final usable = available - 56;
    return usable < 120 ? 120 : usable;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      constraints: BoxConstraints(maxHeight: _maxHeight(context)),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (step.title.isNotEmpty) ...<Widget>[
            Text(step.title, style: AppTypography.label),
            const SizedBox(height: AppSpacing.xxs),
          ],
          // 說明文字放進可捲動區並用 Flexible 包住：空間不夠時捲動文字，
          // 而不是把下面的按鈕/提示推出泡泡外面（那會讓使用者卡住）。
          Flexible(
            child: SingleChildScrollView(
              child: Text(step.instruction, style: AppTypography.body),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (onNext == null)
            // 導航步驟：明確告訴使用者要點哪裡才會前進，
            // 不然他會找不到「下一步」而卡住。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.touch_app_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  '點一下上面圈起來的地方',
                  style: AppTypography.caption.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onNext,
                child: Text(step.handOff ? '我知道了' : '下一步'),
              ),
            ),
        ],
      ),
    );
  }
}
