import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Step 3, new numbers only: just the name (SPEC §9.12). The account starts
/// as a guest and lands on Home; the agent is chosen later from Get started.
/// The verified phone is shown read-only; the verification token from the
/// OTP step travels with the request.
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
  bool _busy = false;
  String? _error;

  /// The 15-minute verification token lapsed — only "Start again" helps.
  bool _expired = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().signup(
            fullName: _name.text.trim(),
            phone: widget.phone,
            verificationToken: widget.verificationToken,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      S.signupBody,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 20),
                    // Verified number — read-only, with a tick.
                    SurfaceCard(
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
                                  '+91 ${widget.phone}',
                                  style: theme.textTheme.titleMedium?.copyWith(color: AppColors.wine),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.name],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: S.fullName,
                        helperText: S.fullNameHelper,
                        prefixIcon: Icon(Icons.person_rounded),
                      ),
                      validator: (v) => (v ?? '').trim().length < 2 ? S.fullNameInvalid : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 24),
                    if (_expired)
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text(S.startAgain),
                      )
                    else
                      FilledButton(
                        onPressed: _busy ? null : _submit,
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
    );
  }
}
