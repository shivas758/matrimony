import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../services/customer_auth_service.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/common.dart';
import '../../widgets/password_field.dart';
import 'phone_screen.dart';

/// The app's entry when logged out (SPEC §9.24 C): mobile number + password
/// → `POST /customer/auth/login`. No SMS. A wrong pair reads "Mobile number
/// or password is incorrect"; a number without a password yet (`409
/// password_not_set` — registered through the agent's web form, or by an app
/// older than 3.5.0) goes straight into Forgot password for that number.
/// *Create account* and *Forgot password?* open the one-time-code flows
/// ([PhoneScreen]).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final phone = _phone.text.trim();
    try {
      // Logged in: the root swaps to Home (or the blocked screen).
      await context.read<AuthState>().login(phone: phone, password: _password.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'password_not_set') {
        setState(() => _busy = false);
        await _open(OtpPurpose.reset, notice: S.setPasswordFirst);
        return;
      }
      setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Create account / Forgot password with the typed number (or [phone]);
  /// comes back here when the person wants to log in with a number instead,
  /// and moves on to Create account for a number without an account.
  Future<void> _open(OtpPurpose purpose, {String? phone, String? notice}) async {
    final typed = phone ?? _phone.text.trim();
    final detour = await PhoneScreen.open(context, purpose, phone: typed.isEmpty ? null : typed, notice: notice);
    if (detour == null || !mounted) return;
    if (detour.toSignup) return _open(OtpPurpose.signup, phone: detour.phone);
    setState(() {
      _phone.text = detour.phone;
      _password.clear();
      _error = null;
    });
    _passwordFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPad = MediaQuery.paddingOf(context).top;
    // A short phone keeps *Create account* in view: a smaller logo.
    final compact = MediaQuery.sizeOf(context).height < 700;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Wine brand header with the logo tile (it carries the name).
              Container(
                padding: EdgeInsets.fromLTRB(24, topPad + (compact ? 20 : 28), 24, compact ? 44 : 52),
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
                ),
                child: Column(
                  children: [
                    // The tile is wine too: a gold rim sets it off the header.
                    AppLogo(size: compact ? 104 : 136, onDark: true),
                    SizedBox(height: compact ? 12 : 18),
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
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.wineDeep.withValues(alpha: 0.10),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  S.loginTitle,
                                  style: theme.textTheme.titleLarge?.copyWith(color: AppColors.wine),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  S.loginBody,
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _phone,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.telephoneNumberNational],
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                                  decoration: const InputDecoration(
                                    labelText: S.phone,
                                    prefixIcon: Icon(Icons.phone_rounded),
                                    prefixText: '+91 ',
                                  ),
                                  validator: (v) => (v ?? '').trim().length == 10 ? null : S.phoneInvalid,
                                ),
                                const SizedBox(height: 14),
                                PasswordField(
                                  controller: _password,
                                  focusNode: _passwordFocus,
                                  label: S.password,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                  validator: (v) => (v ?? '').isEmpty ? S.passwordRequired : null,
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _busy ? null : () => _open(OtpPurpose.reset),
                                    child: const Text(S.forgotPassword),
                                  ),
                                ),
                                if (_error != null) ...[
                                  ErrorBanner(message: _error!),
                                  const SizedBox(height: 14),
                                ],
                                FilledButton.icon(
                                  onPressed: _busy ? null : _submit,
                                  icon: _busy ? const SizedBox.shrink() : const Icon(Icons.login_rounded, size: 20),
                                  label: _busy ? const ButtonSpinner() : const Text(S.logIn),
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    const Expanded(child: Divider()),
                                    // Capped: wraps instead of overflowing with large text.
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 200),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: Text(
                                          S.newHere,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                                        ),
                                      ),
                                    ),
                                    const Expanded(child: Divider()),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _busy ? null : () => _open(OtpPurpose.signup),
                                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                                  label: const Text(S.createAccount),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Text(
                  S.loginFooter,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
