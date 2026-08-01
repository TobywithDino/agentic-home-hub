import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/error/app_error.dart';
import 'package:ai_butler_app/core/utils/validators.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// 變更密碼（Requirement 3.8-11）。
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await ref.read(accountRepositoryProvider).changePassword(
            oldPassword: _oldController.text,
            newPassword: _newController.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密碼已變更')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      setState(() => _submitError = error is AppError ? error.message : '變更失敗，請稍後再試');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('變更密碼')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _oldController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '目前密碼'),
                validator: (v) => (v == null || v.isEmpty) ? '請輸入目前密碼' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _newController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '新密碼'),
                validator: (v) => Validators.isValidPassword(v ?? '')
                    ? null
                    : '新密碼長度至少 8 個字元且包含英文字母與數字',
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: '確認新密碼'),
                validator: (v) =>
                    (v != _newController.text) ? '兩次輸入的密碼不一致' : null,
              ),
              if (_submitError != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(_submitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('確認變更'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
