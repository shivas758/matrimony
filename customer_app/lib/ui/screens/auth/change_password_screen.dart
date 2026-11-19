import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/password_field.dart';

/// More → **Change password** (current + new + confirm), or **Set a
/// password** (new + confirm only) for an account that has none yet
/// (`customer.has_password` false — SPEC §9.24 C) → `POST
/// /customer/auth/change-password`. A wrong current password (`401
/// bad_credentials`) reads "Current password is incorrect" and never logs
/// out.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen()),
      );

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Fixed while the screen is open: *Set a password* stays that until saved.
  late final bool _hasPassword;

  @override
  void initState() {
    super.initState();
    _hasPassword = context.read<AuthState>().customer?.hasPassword ?? true;
  }

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().changePassword(
            currentPassword: _hasPassword ? _current.text : null,
            newPassword: _password.text,
          );
      if (!mounted) return;
      showSnack(context, _hasPassword ? S.passwordChanged : S.passwordSet);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.isBadCredentials ? S.errCurrentPasswordWrong : friendlyMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _hasPassword ? S.changePassword : S.setPassword;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(color: AppColors.goldLight, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const Icon(Icons.password_rounded, size: 34, color: AppColors.wine),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _hasPassword ? S.changePasswordBody : S.setPasswordBody,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 24),
                      if (_hasPassword) ...[
                        PasswordField(
                          controller: _current,
                          label: S.currentPassword,
                          icon: Icons.key_rounded,
                          autofocus: true,
                          enabled: !_busy,
                          validator: (v) => (v ?? '').isEmpty ? S.passwordRequired : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      PasswordField(
                        controller: _password,
                        label: S.newPassword,
                        helperText: S.passwordHelper,
                        autofocus: !_hasPassword,
                        enabled: !_busy,
                        newPassword: true,
                        validator: validateNewPassword,
                      ),
                      const SizedBox(height: 14),
                      PasswordField(
                        controller: _confirm,
                        label: S.confirmPassword,
                        icon: Icons.lock_outline_rounded,
                        enabled: !_busy,
                        newPassword: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        validator: confirmPasswordValidator(_password),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        ErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy ? const ButtonSpinner() : const Text(S.savePassword),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
