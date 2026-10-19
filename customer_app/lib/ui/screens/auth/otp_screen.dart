import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../services/customer_auth_service.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'signup_screen.dart';

/// Step 2: the 6-digit code (SPEC §9.11 Gandharva 1). A known number logs in
/// straight away; a new one continues to [SignupScreen] with the
/// verification token.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phone, required this.initial});

  /// 10-digit number the code was sent to.
  final String phone;

  /// The send response — carries the mock code in test mode and the resend delay.
  final OtpSent initial;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  late OtpSent _sent = widget.initial;
  Timer? _timer;
  int _secondsLeft = 0;
  bool _busy = false;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCountdown(_sent.retryAfter);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _secondsLeft = seconds);
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft = _secondsLeft - 1);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context
          .read<AuthState>()
          .verifyOtp(phone: widget.phone, code: _code.text.trim());
      if (!mounted) return;
      switch (result) {
        case LoggedIn():
          // The root swaps to Home (or the blocked screen) underneath this route.
          Navigator.of(context).popUntil((r) => r.isFirst);
        case NeedsSignup(:final verificationToken):
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SignupScreen(phone: widget.phone, verificationToken: verificationToken),
            ),
          );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final sent = await context.read<AuthState>().sendOtp(widget.phone);
      if (!mounted) return;
      _code.clear();
      _sent = sent;
      _startCountdown(sent.retryAfter);
      showSnack(context, S.otpResent);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mockCode = _sent.mockCode;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _busy ? null : () => Navigator.of(context).pop()),
        title: const Text(S.otpTitle),
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
                      child: const Icon(Icons.sms_rounded, size: 38, color: AppColors.wine),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      S.otpSentTo,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '+91 ${widget.phone}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(color: AppColors.wine),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      textAlign: TextAlign.center,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 12,
                        color: AppColors.ink,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onFieldSubmitted: (_) => _verify(),
                      onChanged: (v) {
                        if (v.length == 6 && !_busy) _verify();
                      },
                      decoration: const InputDecoration(
                        labelText: S.otpCode,
                        floatingLabelAlignment: FloatingLabelAlignment.center,
                        counterText: '',
                      ),
                      validator: (v) => (v ?? '').trim().length == 6 ? null : S.otpInvalidLength,
                    ),
                    if (mockCode != null) ...[
                      const SizedBox(height: 14),
                      _TestModeHint(code: mockCode, onTap: () => setState(() => _code.text = mockCode)),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      ErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _verify,
                      child: _busy ? const ButtonSpinner() : const Text(S.verify),
                    ),
                    const SizedBox(height: 12),
                    if (_secondsLeft > 0)
                      Text(
                        S.resendIn(_secondsLeft),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                      )
                    else
                      TextButton.icon(
                        onPressed: _resending || _busy ? null : _resend,
                        icon: _resending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text(S.resendOtp),
                      ),
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text(S.changeNumber),
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

/// "Test mode — enter 123456" — shown only while the server runs the mock
/// OTP provider (SPEC §9.1). Tapping fills the code in.
class _TestModeHint extends StatelessWidget {
  const _TestModeHint({required this.code, required this.onTap});

  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.goldLight,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.science_rounded, size: 20, color: AppColors.wine),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.testModeHint(code),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.wineDeep,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      S.testModeTap,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.wineLight),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.touch_app_rounded, size: 18, color: AppColors.wineLight),
            ],
          ),
        ),
      ),
    );
  }
}
