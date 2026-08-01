import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/design_system/app_typography.dart';
import 'package:ai_butler_app/design_system/theme_extensions.dart';
import 'package:ai_butler_app/providers/session_providers.dart';
import 'package:ai_butler_app/router/routes.dart';

/// 登入畫面（Requirement 1）。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await ref.read(authNotifierProvider.notifier).login(
          account: _accountController.text.trim(),
          password: _passwordController.text,
        );
    if (ok && mounted) {
      final redirect = GoRouterState.of(context).uri.queryParameters['from'];
      context
          .go(redirect != null && redirect.isNotEmpty ? redirect : Routes.home);
    }
  }

  Future<void> _quickDemoLogin() async {
    final ok = await ref.read(authNotifierProvider.notifier).quickDemoLogin();
    if (ok && mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: AppSpacing.lg),
                const _ButlerBrandHeader(),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  controller: _accountController,
                  decoration: const InputDecoration(labelText: '帳號'),
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? '請輸入帳號' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '密碼',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? '請輸入密碼' : null,
                ),
                if (authState.errorMessage != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    authState.errorMessage!,
                    style: AppTypography.body
                        .copyWith(color: context.butler.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: authState.isLoading ? null : _submit,
                  child: authState.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('登入'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: authState.isLoading ? null : _quickDemoLogin,
                  child: const Text('demo 快速登入'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ButlerBrandHeader extends StatelessWidget {
  const _ButlerBrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.smart_toy_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('AI 智慧管家',
            style:
                AppTypography.headline.copyWith(color: context.scheme.primary)),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '登入後即可開始您的生活服務諮詢',
          style:
              AppTypography.body.copyWith(color: context.butler.secondaryText),
        ),
      ],
    );
  }
}
