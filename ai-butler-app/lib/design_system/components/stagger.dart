import 'package:flutter/material.dart';

import 'package:ai_butler_app/design_system/app_motion.dart';

/// 列表項目漸進進場（Requirement 18.7）
///
/// 每項延遲不超過 40ms、整體不超過 400ms，延遲由
/// [AppMotion.staggerDelay] 統一算出。
///
/// controller 是 per-item 的，但因為只用在 `ListView.builder` 內，
/// 同時存在的數量受可視區域限制（通常 <10），不會出現「60 筆清單 60 個 ticker」
/// 的情況。動畫結束後 controller 停止，不再消耗每帧預算。
class StaggeredItem extends StatefulWidget {
  const StaggeredItem({
    super.key,
    required this.index,
    required this.itemCount,
    required this.child,
    this.enabled = true,
  });

  final int index;
  final int itemCount;
  final Widget child;

  /// 分頁載入的後續頁面不需要再播進場動畫，可關掉。
  final bool enabled;

  @override
  State<StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.decelerate,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final reduced = AppMotion.resolve(context, AppMotion.page) == Duration.zero;
    if (!widget.enabled || reduced) {
      _controller.value = 1;
      return;
    }

    Future<void>.delayed(
      AppMotion.staggerDelay(widget.index, widget.itemCount),
    ).then((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      // child 由外部傳入，避免每帧重建整個子樹（Requirement 18.11）
      child: widget.child,
      builder: (context, child) {
        final t = _curved.value;
        if (t >= 1) return child!;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}
