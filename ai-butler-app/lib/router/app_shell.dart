import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/theme_extensions.dart';

/// 底部導覽外框（Requirement 4.14-15、18.5-6）。
///
/// 用 [StatefulShellRoute.indexedStack] 搭配這個 widget，讓 4 個分頁各自
/// 保留 Element 樹與滑動位置，切換不重建——這是修掉「切分頁卡卡的」的關鍵。
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<_TabSpec> _tabs = <_TabSpec>[
    _TabSpec(icon: Icons.home_outlined, selectedIcon: Icons.home, label: '首頁'),
    _TabSpec(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long,
        label: '訂單紀錄'),
    _TabSpec(
        icon: Icons.person_outline, selectedIcon: Icons.person, label: '個人'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // 再次點選目前分頁時回到該分頁的第一個畫面，符合一般 App 習慣。
          initialLocation: index == navigationShell.currentIndex,
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: context.butler.surfaceVariant,
        destinations: <NavigationDestination>[
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon,
                  color: Theme.of(context).colorScheme.primary),
              label: tab.label,
            ),
        ],
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
