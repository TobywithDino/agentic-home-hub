import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/skeletons.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';

/// 統一三態呈現（Requirement 22.6）。
///
/// 每個畫面用同一個包裝器處理 loading/data/error，避免有人漏做錯誤態
/// 或做出長相不一致的載入畫面。
class AsyncValueWidget<T> extends StatelessWidget {
  const AsyncValueWidget({
    super.key,
    required this.value,
    required this.data,
    this.skeleton,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  /// 載入中顯示的骨架版面。未提供時退回置中的進度指示器。
  final Widget? skeleton;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => DelayedLoader(
        skeleton: skeleton ?? const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => _ErrorState(error: error, onRetry: onRetry),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.wifi_off_rounded,
                size: 48, color: context.butler.secondaryText),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _messageOf(error),
              textAlign: TextAlign.center,
              style: AppTypography.body
                  .copyWith(color: context.butler.secondaryText),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: onRetry, child: const Text('重新載入')),
            ],
          ],
        ),
      ),
    );
  }

  String _messageOf(Object error) {
    final dynamicError = error as dynamic;
    try {
      final message = dynamicError.message;
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {
      // error 沒有 message 欄位，落到下方預設文字。
    }
    // debug 模式直接顯示原始錯誤，避免「服務暫時無法回應」蓋掉真正的原因
    // （例如 DTO 解析失敗）導致現場無從追查。
    if (kDebugMode) return '服務暫時無法回應\n($error)';
    return '服務暫時無法回應，請稍後再試';
  }
}

/// 空狀態版面（Requirement 5.5、15.11）。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48, color: context.butler.secondaryText),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body
                  .copyWith(color: context.butler.secondaryText),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
