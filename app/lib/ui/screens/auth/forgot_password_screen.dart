import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../widgets/common.dart';
import 'login_screen.dart' show ErrorBanner;
import 'phone_otp_step.dart';

/// "Forgot password?" by OTP (SPEC §9.24 D), in two steps like signup:
/// 1. the mobile number → the reset code (`purpose: 'reset'`) → verified;
/// 2. the new password + confirm → `POST /auth/reset-password` → logged in,
///    exactly like a login (a temporary password is cleared too).
///
/// Under the code field, *Can't get the code? Ask the admin* files the old
/// admin request (`POST /auth/forgot-password`, settled with a temporary
/// password).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.phone = ''});

  /// The number typed on the login screen, if any.
  final String phone;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// The number of the last try — pre-fills step 1 when the agent comes back.
  late String _phone = widget.phone;

  /// Set once the number is verified: step 2 shows.
  String? _verificationToken;

  /// Why the agent was sent back to step 1.
  String? _phoneError;

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// The server's wording, except for the one refusal this flow words itself.
  static String _describe(ApiException e) =>
      e.code == 'account_not_found' ? S.noAccountForNumber : e.message;

  void _onVerified(String phone, String token) => setState(() {
        _phone = phone;
        _verificationToken = token;
        _phoneError = null;
        _error = null;
      });

  /// Back to step 1 (the number stays), optionally saying why.
  void _startAgain([String? message]) => setState(() {
        _verificationToken = null;
        _phoneError = message;
        _error = null;
        _password.clear();
        _confirm.clear();
      });

  /// "Can't get the code? Ask the admin": the old request, after a confirm.
  Future<void> _askAdmin(String phone) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.askAdminTitle),
        content: Text(S.askAdminBody(phone)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.forgotPasswordSend),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthService>().forgotPassword(phone);
      if (!mounted) return;
      showSnack(context, S.forgotPasswordSent);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final token = _verificationToken;
    if (token == null) {
      _startAgain();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().resetPassword(
            phone: _phone,
            phoneVerificationToken: token,
            newPassword: _password.text,
          );
      if (!mounted) return;
      showSnack(context, S.passwordResetDone);
      // Logged in: the root already shows the app underneath this screen.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'phone_not_verified') {
        // The 15-minute verification lapsed — a new code is needed.
        _startAgain(S.resetStartAgain);
      } else if (e.code == 'account_not_found') {
        _startAgain(S.noAccountForNumber);
      } else {
        setState(() => _error = e.fieldErrors?.values.firstOrNull ?? e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.resetPasswordTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _verificationToken == null ? _phoneStep() : _passwordStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _backToLogin(bool busy) => TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(),
        child: const Text(S.backToLogin),
      );

  Widget _phoneStep() => PhoneOtpStep(
        purpose: OtpPurpose.reset,
        header: const AuthStepHeader(step: 1, title: S.otpStepTitle, body: S.resetOtpBody),
        initialPhone: _phone,
        initialError: _phoneError,
        describeError: _describe,
        onVerified: _onVerified,
        codeHelp: (context, phone, busy) => Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('ask-admin'),
            onPressed: busy || _busy ? null : () => _askAdmin(phone),
            icon: const Icon(Icons.support_agent_rounded, size: 18),
            label: const Text(S.cantGetCode),
          ),
        ),
        footer: (context, busy) => _backToLogin(busy || _busy),
      );

  Widget _passwordStep() {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthStepHeader(
            step: 2,
            title: S.newPasswordStepTitle,
            body: S.newPasswordStepBody,
          ),
          const SizedBox(height: 14),
          VerifiedPhoneCard(phone: _phone, onChange: _busy ? null : _startAgain),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: S.newPassword,
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) {
              final n = (v ?? '').length;
              return n < 6 || n > 100 ? S.passwordLengthRule : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirm,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _busy ? null : _submit(),
            decoration: const InputDecoration(
              labelText: S.confirmPassword,
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            validator: (v) => v != _password.text ? S.passwordsDontMatch : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const ButtonSpinner() : const Text(S.saveAndLogin),
          ),
          const SizedBox(height: 8),
          _backToLogin(_busy),
        ],
      ),
    );
  }
}
