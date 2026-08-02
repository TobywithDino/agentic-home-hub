import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/domain/logic/order_diff.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/domain/models/order_update.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';
import 'package:ai_butler_app/providers/session_providers.dart';

/// 輪詢間隔。平台沒有推播管道（`/notifications/tokens` 尚未實作），
/// 因此用前景輪詢達成「資料庫更新後使用者會收到通知」的效果。
const Duration kOrderPollInterval = Duration(seconds: 30);

/// 我的諮詢單 + 我的訂單（Requirement 15.1），並在背景輪詢後端變更。
///
/// 行為：
/// - 綁定登入中的 account id，登入/登出自動重載（未登入不打 API）
/// - 每 [kOrderPollInterval] 重新取一次，與上一份快照比對後產生通知
/// - App 進入背景時暫停輪詢，回到前景時立刻補抓一次
/// - 輪詢失敗只記 log，不把已顯示的資料換成錯誤畫面
class OrderInboxNotifier extends AsyncNotifier<OrderInbox> {
  Timer? _timer;
  OrderInbox? _snapshot;
  bool _isPolling = false;

  @override
  Future<OrderInbox> build() async {
    final accountId =
        ref.watch(authNotifierProvider.select((s) => s.session?.inbrAccountId));

    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });

    if (accountId == null || accountId.isEmpty) {
      _snapshot = null;
      return OrderInbox.empty;
    }

    final inbox = await ref.read(orderRepositoryProvider).fetchInbox();
    _snapshot = inbox;
    _startTimer();
    return inbox;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(kOrderPollInterval, (_) => _poll());
  }

  /// 供下拉重整與「回到前景」使用：立刻抓一次並重設輪詢節奏。
  Future<void> refreshNow() async {
    await _poll(force: true);
    _startTimer();
  }

  Future<void> _poll({bool force = false}) async {
    if (_isPolling) return;

    // 背景中不輪詢，省流量也避免無意義的失敗重試。
    if (!force) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    }

    _isPolling = true;
    try {
      final next = await ref.read(orderRepositoryProvider).fetchInbox();
      final previous = _snapshot;

      // 第一份快照不比對，否則首次載入會把所有既有訂單當成「新訂單」。
      if (previous != null) {
        final updates = OrderDiff.diff(previous: previous, next: next);
        if (updates.isNotEmpty) {
          ref.read(orderUpdatesProvider.notifier).add(updates);
        }
      }

      _snapshot = next;
      state = AsyncData<OrderInbox>(next);
    } catch (error) {
      debugPrint('[orderInbox] 輪詢失敗，保留現有資料: $error');
    } finally {
      _isPolling = false;
    }
  }
}

final orderInboxProvider =
    AsyncNotifierProvider<OrderInboxNotifier, OrderInbox>(
        OrderInboxNotifier.new);

/// 已偵測到的訂單變更通知（最新的排前面）。
class OrderUpdatesNotifier extends Notifier<List<OrderUpdate>> {
  /// 最多保留的通知數，避免長時間執行後無限成長。
  static const int _maxItems = 50;

  @override
  List<OrderUpdate> build() {
    // 換帳號時清空，不讓上一個使用者的通知殘留。
    ref.listen<String?>(
      authNotifierProvider.select((s) => s.session?.inbrAccountId),
      (previous, next) {
        if (previous != next) state = const <OrderUpdate>[];
      },
    );
    return const <OrderUpdate>[];
  }

  /// 加入新通知，已存在的 id 會被忽略（同一筆變更不重複通知）。
  void add(List<OrderUpdate> updates) {
    final existingIds = state.map((u) => u.id).toSet();
    final fresh = updates.where((u) => !existingIds.contains(u.id)).toList();
    if (fresh.isEmpty) return;

    final next = <OrderUpdate>[...fresh, ...state];
    state = next.length > _maxItems ? next.sublist(0, _maxItems) : next;
  }

  void markAllRead() {
    if (state.every((u) => u.isRead)) return;
    state = state.map((u) => u.copyWith(isRead: true)).toList();
  }

  void clear() => state = const <OrderUpdate>[];
}

final orderUpdatesProvider =
    NotifierProvider<OrderUpdatesNotifier, List<OrderUpdate>>(
        OrderUpdatesNotifier.new);

/// 未讀通知數，供底部導覽的紅點使用。
final unreadOrderUpdateCountProvider = Provider<int>((ref) {
  return ref.watch(orderUpdatesProvider).where((u) => !u.isRead).length;
});
