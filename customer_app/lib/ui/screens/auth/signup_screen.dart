import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/password_field.dart';
import '../../widgets/terms_consent.dart';

/// Create account, step 3 (after the one-time code): the name and a
/// password + confirmation (SPEC §9.12 / §9.24 C). The account starts as a
/// guest and lands on Home; the agent is chosen later from Get started. The
/// verified phone is shown read-only; the verification token from the OTP
/// step travels with the request. *Create account* works only once the
/// Terms & Privacy box is ticked; the signup then says `accepted_terms: true`
/// (SPEC §9.22 C).
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.phone, required this.verificationToken});

  final String phone;
  final String verificationToken;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The Terms & Privacy checkbox (SPEC §9.22 C) — required to sign up.
  bool _agreed = false;

  /// The 15-minute verification token lapsed — only "Start again" helps.
  bool _expired = false;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      // "Done" on the keyboard before ticking the box.
      setState(() => _error = S.termsRequired);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().signup(
            fullName: _name.text.trim(),
            phone: widget.phone,
            password: _password.text,
            verificationToken: widget.verificationToken,
            acceptedTerms: true,
          );
      // The root now shows Home underneath this route.
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
      appBar: AppBar(title: const Text(S.signupTitle)),
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
                        S.signupBody,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 20),
                      VerifiedNumberCard(phone: widget.phone),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _name,
                        autofocus: true,
                        enabled: enabled,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          labelText: S.fullName,
                          helperText: S.fullNameHelper,
                          prefixIcon: Icon(Icons.person_rounded),
                        ),
                        validator: (v) => (v ?? '').trim().length < 2 ? S.fullNameInvalid : null,
                      ),
                      const SizedBox(height: 14),
                      PasswordField(
                        controller: _password,
                        label: S.password,
                        helperText: S.passwordHelper,
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
                      const SizedBox(height: 12),
                      TermsConsent(
                        value: _agreed,
                        enabled: enabled,
                        onChanged: (v) => setState(() {
                          _agreed = v;
                          if (v && _error == S.termsRequired) _error = null;
                        }),
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
                          // Only once the terms are accepted (SPEC §9.22 C).
                          onPressed: _busy || !_agreed ? null : _submit,
                          child: _busy ? const ButtonSpinner() : const Text(S.createAccount),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        S.signupNote,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
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

/// The number the one-time code checked — read-only, with a tick (Create
/// account and Forgot password).
class VerifiedNumberCard extends StatelessWidget {
  const VerifiedNumberCard({super.key, required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.yourNumber,
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline),
                ),
                Text(
                  '+91 $phone',
                  style: theme.textTheme.titleMedium?.copyWith(color: AppColors.wine),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Start again" — the 15-minute verification token lapsed (`400
/// phone_not_verified`): back to the login screen.
class StartAgainButton extends StatelessWidget {
  const StartAgainButton({super.key});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        icon: const Icon(Icons.restart_alt_rounded),
        label: const Text(S.startAgain),
      );
}
