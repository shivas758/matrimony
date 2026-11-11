import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../services/phone_auth_gateway.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/common.dart';
import 'otp_flow.dart';
import 'otp_screen.dart';

/// Step 1 of login/signup: the mobile number (SPEC §9.11 Gandharva 1).
/// Both known and new numbers go through the same button — the OTP screen
/// finds out which it is. With Firebase phone auth (SPEC §9.19 A) Android
/// may verify the number by itself; then the OTP screen is skipped.
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

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
    });
    final phone = _phone.text.trim();
    final auth = context.read<AuthState>();
    final gateway = context.read<PhoneAuthGateway>();
    final nav = Navigator.of(context);
    try {
      final request = await requestOtp(auth, gateway, phone);
      if (!mounted) return;
      switch (request) {
        case OtpCodeNeeded(:final sent, :final session):
          await nav.push(
            MaterialPageRoute(builder: (_) => OtpScreen(phone: phone, initial: sent, firebase: session)),
          );
        case OtpAutoVerified(:final result):
          continueAfterVerify(nav, phone, result);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } on PhoneAuthFailure catch (e) {
      if (mounted) setState(() => _error = phoneAuthMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPad = MediaQuery.paddingOf(context).top;

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
                padding: EdgeInsets.fromLTRB(24, topPad + 28, 24, 52),
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
                ),
                child: Column(
                  children: [
                    // The tile is wine too: a gold rim sets it off the header.
                    const AppLogo(size: 136, onDark: true),
                    const SizedBox(height: 18),
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
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                S.phoneTitle,
                                style: theme.textTheme.titleLarge?.copyWith(color: AppColors.wine),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                S.phoneBody,
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.telephoneNumberNational],
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
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
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                child: Text(
                  S.phoneFooter,
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
