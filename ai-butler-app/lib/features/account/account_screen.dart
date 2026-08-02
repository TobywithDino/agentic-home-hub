import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/components/async_value_widget.dart';
import 'package:ai_butler_app/features/account/edit_contact_screen.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/account_providers.dart';
import 'package:ai_butler_app/providers/session_providers.dart';

/// 個人帳戶資訊頁。
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(memberProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('個人帳戶')),
      body: AsyncValueWidget<MemberProfile>(
        value: profileAsync,
        onRetry: () => ref.invalidate(memberProfileProvider),
        data: (profile) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: <Widget>[
            const SizedBox(height: AppSpacing.lg),
            // 頭像：實色圓形 + 白色人頭
            const Center(
              child: CircleAvatar(
                radius: 48,
                backgroundColor: Color(0xFF90A4AE),
                child: Icon(Icons.person, size: 52, color: Colors.white),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // 姓名
            Center(
              child: Text(
                profile.name.isNotEmpty ? profile.name : '未設定姓名',
                style: AppTypography.title,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // 手機
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: const Text('手機'),
              subtitle: Text(
                profile.mobile.isNotEmpty ? profile.mobile : '未設定',
              ),
            ),
            // Email
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('電子郵件'),
              subtitle: Text(
                profile.email.isNotEmpty ? profile.email : '未設定',
              ),
            ),
            const Divider(height: AppSpacing.lg),
            // 編輯資料
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改資料'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EditContactScreen(profile: profile),
                ),
              ),
            ),
            // 登出
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
      // 只清除 session，GoRouter 的 redirect 會自動導向登入頁
      await ref.read(authNotifierProvider.notifier).logout();
    }
  }
}
