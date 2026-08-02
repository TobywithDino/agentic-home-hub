/// 把 [TourStep] 清單跑成畫面上的光圈導覽。
///
/// 依賴 tutorial_coach_mark 1.3.3(pubspec 請鎖版號,不要用 ^):
///   dependencies:
///     tutorial_coach_mark: 1.3.3
library;

import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import 'tour.dart';

class TourRunner {
  TourRunner({required this.steps, this.onHandOff, this.onSkipped});

  final List<TourStep> steps;

  /// 走到交棒步驟、遮罩關掉的那一刻觸發。
  /// 這時候真正的送出按鈕已經可以點,使用者要自己按。
  final VoidCallback? onHandOff;

  final VoidCallback? onSkipped;

  TutorialCoachMark? _coach;

  /// 啟動導覽。
  ///
  /// 必須等第一帧畫完才能量測錨點位置,否則光圈會打在 (0,0)。
  void start(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      // 錨點沒掛上畫面的步驟直接跳過,避免導覽卡在找不到的目標上。
      final usable = steps.where((s) => TourAnchors.isMounted(s.anchorId)).toList();
      if (usable.isEmpty) {
        onSkipped?.call();
        return;
      }

      _coach = TutorialCoachMark(
        targets: usable.map(_toTarget).toList(),
        colorShadow: Colors.black,
        opacityShadow: 0.75,
        paddingFocus: 8,
        textSkip: '略過教學',
        alignSkip: Alignment.topRight,
        onSkip: () {
          onSkipped?.call();
          return true;
        },
        onFinish: () {
          // 正常情況下最後一步是交棒步驟,會走 _finishForHandOff;
          // 這裡是使用者一路點到底的保險。
          onHandOff?.call();
        },
      )..show(context: context);
    });
  }

  TargetFocus _toTarget(TourStep step) {
    return TargetFocus(
      identify: step.anchorId,
      keyTarget: TourAnchors.of(step.anchorId),
      shape: ShapeLightFocus.RRect,
      radius: 12,
      // 交棒步驟要關掉「點畫面任意處前進」,強迫使用者讀完說明再按按鈕,
      // 不然他會習慣性連點直接跳過最後一步。
      enableOverlayTab: !step.handOff,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          builder: (context, controller) => _Bubble(
            step: step,
            onNext: () {
              if (step.handOff) {
                // 關掉遮罩把控制權交還給使用者。
                controller.skip();
                onHandOff?.call();
              } else {
                controller.next();
              }
            },
          ),
        ),
      ],
    );
  }

  void dispose() {
    _coach?.finish();
    _coach = null;
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.step, required this.onNext});

  final TourStep step;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            step.instruction,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: step.handOff
                ? FilledButton(
                    onPressed: onNext,
                    child: const Text('好,我自己按'),
                  )
                : TextButton(
                    onPressed: onNext,
                    child: const Text('下一步'),
                  ),
          ),
        ],
      ),
    );
  }
}
