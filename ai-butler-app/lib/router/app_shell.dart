import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/domain/models/order_update.dart';
import 'package:ai_butler_app/providers/order_providers.dart';

/// 底部導覽外框（Requirement 4.14-15、18.5-6）。
///
/// 用 [StatefulShellRoute.indexedStack] 搭配這個 widget，讓 3 個分頁各自
/// 保留 Element 樹與滑動位置，切換不重建。
///
/// 這裡同時是訂單更新通知的出口：訂單分頁上掛未讀紅點，並在收到新變更時
/// 跳一次 SnackBar，讓使用者在任何分頁都能得知後端資料變動。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  /// 順序需與 [buildAppRouter] 的 branches 一致。
  static const List<_TabSpec> _tabs = <_TabSpec>[
    _TabSpec(icon: Icons.home_outlined, selectedIcon: Icons.home, label: '首頁'),
    _TabSpec(
        icon: Icons.smart_toy_outlined,
        selectedIcon: Icons.smart_toy,
        label: 'AI 管家'),
    _TabSpec(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: '訂單紀錄'),
    _TabSpec(
        icon: Icons.person_outline, selectedIcon: Icons.person, label: '個人'),
  ];

  /// 訂單分頁在 branches 中的索引（AI 管家插在第二個之後往後移一位）。
  static const int _ordersTabIndex = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前景立刻補抓一次，不用等下一個輪詢週期。
    if (state == AppLifecycleState.resumed) {
      ref.read(orderInboxProvider.notifier).refreshNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = ref.watch(unreadOrderUpdateCountProvider);

    // 有新通知就提示一次；使用者已經在訂單分頁時不打擾（那裡會直接列出）。
    ref.listen<List<OrderUpdate>>(orderUpdatesProvider, (previous, next) {
      final previousIds =
          (previous ?? const <OrderUpdate>[]).map((u) => u.id).toSet();
      final fresh = next.where((u) => !previousIds.contains(u.id)).toList();
      if (fresh.isEmpty) return;
      if (widget.navigationShell.currentIndex == _ordersTabIndex) return;
      _showUpdateToast(fresh);
    });

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onDestinationSelected: (index) => widget.navigationShell.goBranch(
          index,
          // 再次點選目前分頁時回到該分頁的第一個畫面，符合一般 App 習慣。
          initialLocation: index == widget.navigationShell.currentIndex,
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: context.butler.surfaceVariant,
        destinations: <NavigationDestination>[
          for (int i = 0; i < _tabs.length; i++)
            NavigationDestination(
              icon: _withBadge(
                Icon(_tabs[i].icon),
                showCount: i == _ordersTabIndex ? unreadCount : 0,
              ),
              selectedIcon: _withBadge(
                Icon(_tabs[i].selectedIcon,
                    color: Theme.of(context).colorScheme.primary),
                showCount: i == _ordersTabIndex ? unreadCount : 0,
              ),
              label: _tabs[i].label,
            ),
        ],
      ),
    );
  }

  Widget _withBadge(Widget icon, {required int showCount}) {
    if (showCount <= 0) return icon;
    return Badge(
      label: Text(showCount > 99 ? '99+' : '$showCount'),
      child: icon,
    );
  }

  void _showUpdateToast(List<OrderUpdate> fresh) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final text = fresh.length == 1
        ? '${fresh.first.title}：${fresh.first.description}'
        : '訂單有 ${fresh.length} 項更新';

    messenger.showSnackBar(
      SnackBar(
        content: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '查看',
          onPressed: () => widget.navigationShell.goBranch(_ordersTabIndex),
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(
      {required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
