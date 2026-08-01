import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/core/utils/pii_masker.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:ai_butler_app/features/account/change_password_screen.dart';
import 'package:ai_butler_app/features/account/edit_contact_screen.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/account_providers.dart';
import 'package:ai_butler_app/providers/session_providers.dart';
import 'package:ai_butler_app/providers/theme_providers.dart';
import 'package:ai_butler_app/router/routes.dart';

/// 個人帳戶資訊頁（Requirement 3）。
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(memberProfileProvider);
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('個人帳戶')),
      body: AsyncValueWidget<MemberProfile>(
        value: profileAsync,
        onRetry: () => ref.invalidate(memberProfileProvider),
        data: (profile) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: <Widget>[
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(profile.name, style: AppTypography.title),
              subtitle: Text(
                '手機：${PiiMasker.maskMobile(profile.mobile)}\n'
                'Email：${PiiMasker.maskEmail(profile.email)}\n'
                'ID：${PiiMasker.accountIdSuffix(authState.session?.inbrAccountId)}',
              ),
              isThreeLine: true,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('編輯聯絡資訊'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EditContactScreen(profile: profile),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('變更密碼'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChangePasswordScreen(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('主題設定'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showThemePicker(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('登出'),
              onTap: () => _confirmLogout(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showThemePicker(BuildContext context, WidgetRef ref) async {
    final current = ref.read(themeNotifierProvider);
    final choice = await showDialog<AppThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('選擇主題'),
        children: <Widget>[
          for (final mode in AppThemeMode.values)
            RadioListTile<AppThemeMode>(
              value: mode,
              groupValue: current,
              title: Text(switch (mode) {
                AppThemeMode.system => '跟隨系統',
                AppThemeMode.light => '淺色',
                AppThemeMode.dark => '深色',
              }),
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
    if (choice != null) {
      await ref.read(themeNotifierProvider.notifier).setMode(choice);
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確定要登出嗎？'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('登出')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authNotifierProvider.notifier).logout();
      if (context.mounted) context.go(Routes.login);
    }
  }
}
