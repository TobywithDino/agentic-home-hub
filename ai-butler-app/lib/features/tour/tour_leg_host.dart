import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/features/tour/tour_runner.dart';
import 'package:ai_butler_app/features/tour/tour_session.dart';
import 'package:ai_butler_app/features/tour/tour_step.dart';

/// 導覽的診斷輸出。
///
/// **刻意不用 `kDebugMode` 包住。** 這個專案的 App 必須用 `--profile` 跑
/// （debug 模式會撞到 Flutter 自己的 mouse_tracker assert），而 `kDebugMode`
/// 在 profile 是 false —— 包起來等於在真正需要它的環境裡什麼都印不出來。
/// 導覽是使用者偶爾才觸發一次的動作，多幾行 log 沒有成本。
void tourLog(String message) => debugPrint('[tour] $message');

/// 在畫面上啟動屬於自己的那一段導覽。
///
/// 三個導航畫面（首頁／服務商列表／商家詳情）共用這支，不然同樣的
/// 「檢查是不是輪到我 → 等一個 frame → 啟動 → 標記已啟動」邏輯要寫三遍。
///
/// 呼叫時機是畫面的 `build` 裡（直接呼叫即可，內部會延到 frame 之後）。
/// 重複呼叫是安全的：`session.started` 會擋掉第二次。
///
/// [buildSteps] 回傳 null 表示「這一段跑不了」（例如目標不在畫面上），
/// 會直接結束整個 session。它延遲到真的要啟動時才呼叫，因為通常需要畫面
/// 已載入的資料（例如服務商名稱），提早算會拿到空值。
void maybeStartTourLeg({
  required WidgetRef ref,
  required BuildContext context,
  required TourLeg leg,
  required List<TourStep>? Function() buildSteps,
}) {
  final session = ref.read(tourSessionProvider);
  if (session == null || session.leg != leg || session.started) return;

  // 這裡**不能**直接改 provider。
  //
  // 這支是從畫面的 build 裡呼叫的，而 Riverpod 明確禁止在 build/initState
  // 之類的生命週期裡修改 provider（debug 模式會直接丟
  // 「Tried to modify a provider while the widget tree was building」）。
  // 所以連 markStarted 都要延到 frame 之後 —— 整段狀態變更都在 postFrame 裡。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;

    final notifier = ref.read(tourSessionProvider.notifier);

    // 同一個 frame 內 build 可能跑好幾次，排進多個 callback。
    // 它們會依序執行，所以第一個標記完之後，後面的在這裡就會被擋掉。
    final still = ref.read(tourSessionProvider);
    if (still == null || still.leg != leg || still.started) return;
    notifier.markStarted();

    final steps = buildSteps();
    if (steps == null) {
      notifier.finish();
      _notify(context, '導覽中斷：找不到要圈起來的位置');
      return;
    }

    tourLog('啟動 $leg，共 ${steps.length} 步');

    final tour = TourRunner.start(
      context,
      steps,
      // 導航段只有一步且靠點擊前進，走到 onFinish 幾乎都是使用者按了
      // 「跳過導覽」，所以整個 session 就結束，不要繼續在下一頁彈出來。
      onFinish: () => ref.read(tourSessionProvider.notifier).finish(),
    );

    // 錨點都還沒掛上（例如資料還在載入）→ 這一段跑不了。
    // 把 session 結束掉，而不是留著讓使用者卡在一個永遠不會出現的導覽裡。
    if (tour == null) {
      tourLog('$leg 的錨點都沒掛上（widget 還沒 mount），結束導覽');
      notifier.finish();
      _notify(context, '導覽中斷：畫面元件還沒準備好');
    }
  });
}

/// 導覽失敗時在畫面上說一聲。
///
/// 光是寫 log 不夠：這個專案的 App 跑在 `--profile`，使用者不一定開著
/// console。導覽默默不出現的話，看起來就只是「按了沒反應」。
void _notify(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}
