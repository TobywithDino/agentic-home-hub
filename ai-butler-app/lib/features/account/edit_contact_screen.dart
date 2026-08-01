import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_butler_app/core/utils/validators.dart';
import 'package:ai_butler_app/design_system/app_spacing.dart';
import 'package:ai_butler_app/domain/models/domain_models.dart';
import 'package:ai_butler_app/providers/account_providers.dart';
import 'package:ai_butler_app/providers/repository_providers.dart';

/// 編輯聯絡資訊（Requirement 3.5-7、3.10-11）。
class EditContactScreen extends ConsumerStatefulWidget {
  const EditContactScreen({super.key, required this.profile});

  final MemberProfile profile;

  @override
  ConsumerState<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends ConsumerState<EditContactScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _emailController;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _mobileController = TextEditingController(text: widget.profile.mobile);
    _emailController = TextEditingController(text: widget.profile.email);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final updated = widget.profile.copyWith(
        name: _nameController.text.trim(),
        mobile: _mobileController.text.trim(),
        email: _emailController.text.trim(),
      );
      await ref.read(accountRepositoryProvider).updateContact(updated);
      ref.invalidate(memberProfileProvider);

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已更新聯絡資訊')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      setState(() => _submitError = '更新失敗，請稍後再試');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('編輯聯絡資訊')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '姓名'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '請輸入姓名' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _mobileController,
                decoration: const InputDecoration(labelText: '手機號碼'),
                keyboardType: TextInputType.phone,
                validator: (v) => Validators.isValidTaiwanMobile(v ?? '')
                    ? null
                    : '手機格式需為 09 開頭的 10 位數字',
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null ||
                        v.trim().isEmpty ||
                        Validators.isValidEmail(v))
                    ? null
                    : 'Email 格式不正確',
              ),
              if (_submitError != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(_submitError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton(onPressed: _submit, child: const Text('重試')),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('儲存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
