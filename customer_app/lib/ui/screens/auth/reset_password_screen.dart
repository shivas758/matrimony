import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../widgets/common.dart';
import '../../widgets/password_field.dart';
import 'signup_screen.dart';

/// Forgot password, step 3 (after the one-time code with purpose `reset`):
/// the new password + confirmation → `POST /customer/auth/reset-password`
/// → logged in straight away (SPEC §9.24 C). A lapsed verification token
/// (`400 phone_not_verified`) leaves only "Start again".
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.phone, required this.verificationToken});

  final String phone;
  final String verificationToken;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The 15-minute verification token lapsed — only "Start again" helps.
  bool _expired = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _expired || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().resetPassword(
            phone: widget.phone,
            verificationToken: widget.verificationToken,
            newPassword: _password.text,
          );
      // Logged in: the root now shows Home underneath this route.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyMessage(e);
          _expired = e.code == 'phone_not_verified';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = !_busy && !_expired;

    return Scaffold(
      appBar: AppBar(title: const Text(S.resetTitle)),
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
                      Text(
                        S.resetBody,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 20),
                      VerifiedNumberCard(phone: widget.phone),
                      const SizedBox(height: 20),
                      PasswordField(
                        controller: _password,
                        label: S.newPassword,
                        helperText: S.passwordHelper,
                        autofocus: true,
                        enabled: enabled,
                        newPassword: true,
                        validator: validateNewPassword,
                      ),
                      const SizedBox(height: 14),
                      PasswordField(
                        controller: _confirm,
                        label: S.confirmPassword,
                        icon: Icons.lock_outline_rounded,
                        enabled: enabled,
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
                      if (_expired)
                        const StartAgainButton()
                      else
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy ? const ButtonSpinner() : const Text(S.saveAndLogIn),
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
