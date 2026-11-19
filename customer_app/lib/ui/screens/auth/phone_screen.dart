import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../services/customer_auth_service.dart';
import '../../../services/phone_auth_gateway.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'otp_flow.dart';
import 'otp_screen.dart';

/// Where a mobile-number step sends the person back to the login screen
/// (SPEC §9.24 C): an already registered number → log in with it; a number
/// with no account (Forgot password) → Create account with it.
class AuthDetour {
  const AuthDetour.login(this.phone) : toSignup = false;
  const AuthDetour.signup(this.phone) : toSignup = true;

  final String phone;

  /// True: open Create account with [phone]; false: back to Log in with it.
  final bool toSignup;
}

/// Step 1 of Create account and Forgot password: the mobile number, then
/// *Send OTP* (SPEC §9.24 C). The server checks the number before any SMS —
/// Create account: `409 phone_taken` ("already registered — log in with
/// your password", with *Log in with this number*); Forgot password:
/// `404 account_not_found` (with *Create account*). With Firebase phone auth
/// (SPEC §9.19 A) Android may verify the number by itself; then the OTP
/// screen is skipped.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key, required this.purpose, this.initialPhone, this.notice});

  final OtpPurpose purpose;

  /// The number typed on the login screen, if any.
  final String? initialPhone;

  /// A note above the form — "Set a password for this number first…" when
  /// the login found the number without a password.
  final String? notice;

  /// Opens the step for [purpose]; resolves with an [AuthDetour] when the
  /// person goes back to log in or on to Create account, else null.
  static Future<AuthDetour?> open(
    BuildContext context,
    OtpPurpose purpose, {
    String? phone,
    String? notice,
  }) =>
      Navigator.of(context).push<AuthDetour>(
        MaterialPageRoute(builder: (_) => PhoneScreen(purpose: purpose, initialPhone: phone, notice: notice)),
      );

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.initialPhone ?? '');
  bool _busy = false;
  String? _error;

  /// The server's code behind [_error] — `phone_taken` / `account_not_found`
  /// offer a way on.
  String? _errorCode;

  bool get _signup => widget.purpose == OtpPurpose.signup;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _errorCode = null;
    });
    final phone = _phone.text.trim();
    final auth = context.read<AuthState>();
    final gateway = context.read<PhoneAuthGateway>();
    final nav = Navigator.of(context);
    try {
      final request = await requestOtp(auth, gateway, phone, purpose: widget.purpose);
      if (!mounted) return;
      switch (request) {
        case OtpCodeNeeded(:final sent, :final session):
          await nav.push(
            MaterialPageRoute(
              builder: (_) => OtpScreen(phone: phone, initial: sent, purpose: widget.purpose, firebase: session),
            ),
          );
        case OtpAutoVerified(:final result):
          continueAfterVerify(nav, phone, widget.purpose, result);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyMessage(e);
          _errorCode = e.code;
        });
      }
    } on PhoneAuthFailure catch (e) {
      if (mounted) setState(() => _error = phoneAuthMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Back to the login screen with a way on for the number.
  void _detour(AuthDetour detour) {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop(detour);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = _phone.text.trim();
    final Widget? way = switch (_errorCode) {
      'phone_taken' when _signup => OutlinedButton.icon(
          onPressed: () => _detour(AuthDetour.login(phone)),
          icon: const Icon(Icons.login_rounded, size: 20),
          label: const Text(S.logInWithNumber),
        ),
      'account_not_found' when !_signup => OutlinedButton.icon(
          onPressed: () => _detour(AuthDetour.signup(phone)),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
          label: const Text(S.createAccount),
        ),
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _busy ? null : () => Navigator.of(context).maybePop()),
        title: Text(_signup ? S.createAccount : S.resetPhoneTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(color: AppColors.goldLight, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Icon(
                        _signup ? Icons.person_add_alt_1_rounded : Icons.lock_reset_rounded,
                        size: 38,
                        color: AppColors.wine,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _signup ? S.signupPhoneBody : S.resetPhoneBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (widget.notice != null) ...[
                      const SizedBox(height: 16),
                      NoticeCard(icon: Icons.key_rounded, title: widget.notice!, tint: AppColors.goldDark),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _phone,
                      autofocus: (widget.initialPhone ?? '').isEmpty,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.telephoneNumberNational],
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      onChanged: (_) {
                        // A different number: the old answer no longer applies.
                        if (_errorCode != null) {
                          setState(() {
                            _error = null;
                            _errorCode = null;
                          });
                        }
                      },
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: S.phone,
                        prefixIcon: Icon(Icons.phone_rounded),
                        prefixText: '+91 ',
                      ),
                      validator: (v) => (v ?? '').trim().length == 10 ? null : S.phoneInvalid,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      ErrorBanner(message: _error!),
                    ],
                    if (way != null) ...[
                      const SizedBox(height: 10),
                      way,
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy ? const SizedBox.shrink() : const Icon(Icons.sms_rounded, size: 20),
                      label: _busy ? const ButtonSpinner() : const Text(S.sendOtp),
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
