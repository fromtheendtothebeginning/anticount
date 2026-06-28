import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/animated_dialog.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _newPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final ok = await context.read<AuthProvider>().resetPassword(
          username: _usernameCtrl.text,
          newPassword: _newPwdCtrl.text,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('密码已重置，请使用新密码登录'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } else {
      await showInfoDialog(
        context: context,
        title: '重置失败',
        content: context.read<AuthProvider>().error ?? '重置失败，请重试',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('重置密码')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '通过用户名验证身份后设置新密码',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                AppTextField(
                  controller: _usernameCtrl,
                  label: '用户名',
                  prefixIcon: const Icon(Icons.person_outline),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _newPwdCtrl,
                  label: '新密码',
                  hint: '至少 6 位',
                  obscureText: true,
                  prefixIcon: const Icon(Icons.lock_outline),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '请输入新密码';
                    if (v.length < 6) return '密码至少 6 位';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                AppButton(
                  label: '重置密码',
                  loading: _loading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
