import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/common.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().login(
            phone: _phone.text.trim(),
            password: _password.text,
          );
      // The root widget swaps the screen once auth state changes.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Forgot password?" — asks for the number and files a request the admin
  /// settles with a temporary password (SPEC §4 Auth). No OTP, no email.
  Future<void> _forgotPassword() async {
    final phone = TextEditingController(text: _phone.text.trim());
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.forgotPassword),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(S.forgotPasswordBody),
              const SizedBox(height: 16),
              TextFormField(
                controller: phone,
                autofocus: true,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: S.phone,
                  prefixIcon: Icon(Icons.phone_rounded),
                  prefixText: '+91 ',
                ),
                validator: (v) =>
                    (v ?? '').trim().length == 10 ? null : 'Enter your 10-digit mobile number',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text(S.forgotPasswordSend),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthService>().forgotPassword(phone.text.trim());
      if (mounted) showSnack(context, S.forgotPasswordSent);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: AppColors.ivory,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Navy brand header with the icon and wordmark.
              Container(
                padding: EdgeInsets.fromLTRB(24, topPad + 28, 24, 52),
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
                ),
                child: Column(
                  children: [
                    const AppLogoMark(size: 118),
                    const SizedBox(height: 8),
                    const AppWordmark(onDark: true, size: 36),
                    const SizedBox(height: 14),
                    Text(
                      S.appIntro,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              // The form card overlaps the header's rounded bottom edge.
              Transform.translate(
                offset: const Offset(0, -28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navyDeep.withValues(alpha: 0.10),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                S.login,
                                style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sign in with your registered mobile number.',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                decoration: const InputDecoration(
                                  labelText: S.phone,
                                  prefixIcon: Icon(Icons.phone_rounded),
                                  prefixText: '+91 ',
                                ),
                                validator: (v) => (v ?? '').trim().length == 10
                                    ? null
                                    : 'Enter your 10-digit mobile number',
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _password,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: S.password,
                                  prefixIcon: const Icon(Icons.lock_rounded),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                    ),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                ErrorBanner(message: _error!),
                              ],
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                      )
                                    : const Text(S.login),
                              ),
                              const SizedBox(height: 4),
                              TextButton(
                                onPressed: _busy ? null : _forgotPassword,
                                child: const Text(S.forgotPassword),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(
                  children: [
                    Text(
                      'New agent?',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(220, 48)),
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SignupScreen()),
                              ),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: const Text(S.signup),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared by the signup screen.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
