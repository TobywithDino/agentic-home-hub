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
        for (var i = 0; i < usable.length; i++) _toTarget(usable[i], i),
      ],
      colorShadow: Colors.black,
      opacityShadow: 0.75,
      paddingFocus: 6,
      hideSkip: false,
      textSkip: '跳過導覽',
      alignSkip: Alignment.topRight,
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

  static TargetFocus _toTarget(TourStep step, int identify) {
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
          align: ContentAlign.bottom,
          builder: (context, controller) => _Bubble(
            step: step,
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
  const _Bubble({required this.step, this.onNext});

  final TourStep step;

  /// null 代表這一步只能靠點擊目標前進。
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
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
          Text(step.instruction, style: AppTypography.body),
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
