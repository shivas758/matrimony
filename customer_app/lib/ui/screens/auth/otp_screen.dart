import 'dart:async';

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

/// Step 2: the 6-digit code (SPEC §9.11 Gandharva 1). A known number logs in
/// straight away; a new one continues to the signup screen with the
/// verification token.
///
/// With Firebase phone auth ([firebase] set, SPEC §9.19 A) the code came
/// from Firebase: *Verify* confirms it with Firebase and sends the resulting
/// ID token to the server; Android may also read the SMS by itself, and the
/// screen then continues on its own ("Verifying automatically…"). No
/// test-mode hint in that mode.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phone, required this.initial, this.firebase});

  /// 10-digit number the code was sent to.
  final String phone;

  /// The send response — carries the mock code in test mode and the resend delay.
  final OtpSent initial;

  /// The Firebase verification when the server's provider is `firebase`.
  final FirebaseOtpSession? firebase;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  late OtpSent _sent = widget.initial;
  late FirebaseOtpSession? _session = widget.firebase;
  Timer? _timer;
  int _secondsLeft = 0;
  bool _busy = false;
  bool _resending = false;
  String? _error;

  /// Firebase mode: an ID token already in hand (auto-verified, or kept for
  /// a retry after the server could not be reached).
  String? _idToken;

  /// Firebase mode: Android verified the number by itself; the server call runs.
  bool _autoVerifying = false;
  StreamSubscription<PhoneAutoVerified>? _autoSub;

  @override
  void initState() {
    super.initState();
    _startCountdown(_sent.retryAfter);
    if (_session != null) _listenForAutoVerification();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _autoSub?.cancel();
    _code.dispose();
    super.dispose();
  }

  /// SMS auto-read after the code was sent (Firebase mode only).
  void _listenForAutoVerification() {
    _autoSub ??= context.read<PhoneAuthGateway>().autoVerified.listen((event) {
      if (!mounted || _session == null) return;
      if (event.phone != null && event.phone != widget.phone) return;
      if (_busy) {
        // A typed code is being checked; keep the token in case that fails.
        _idToken ??= event.idToken;
        return;
      }
      _idToken = event.idToken;
      _verifyFirebase(auto: true);
    });
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
    if (_session != null) {
      if (_busy) return;
      // A token in hand needs no code.
      if (_idToken != null) return _verifyFirebase();
      if (!_formKey.currentState!.validate()) return;
      FocusScope.of(context).unfocus();
      return _verifyFirebase(code: _code.text.trim());
    }
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
      // Logged in: the root swaps to Home (or the blocked screen) underneath this route.
      continueAfterVerify(Navigator.of(context), widget.phone, result, replace: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Firebase mode: the typed [code] → Firebase ID token (unless one is
  /// already in hand) → the server's verify → signed out of Firebase.
  Future<void> _verifyFirebase({String? code, bool auto = false}) async {
    final session = _session!;
    final auth = context.read<AuthState>();
    final gateway = context.read<PhoneAuthGateway>();
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _autoVerifying = auto;
      _error = null;
    });
    try {
      final token = _idToken ?? await gateway.confirmCode(session.verificationId, code ?? '');
      _idToken = token;
      final result = await verifyFirebaseIdToken(auth, gateway, widget.phone, token);
      if (!mounted) return;
      continueAfterVerify(nav, widget.phone, result, replace: true);
    } on PhoneAuthFailure catch (e) {
      if (mounted) setState(() => _error = phoneAuthMessage(e));
    } on ApiException catch (e) {
      // Keep the token only for a retry after a network / server hiccup —
      // one the server refused will not work a second time.
      if (!_isTransient(e)) _idToken = null;
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _autoVerifying = false;
        });
      }
    }
  }

  static bool _isTransient(ApiException e) =>
      e.code == 'network_error' || e.code == 'server_error' || (e.status ?? 0) >= 500;

  Future<void> _resend() async {
    final auth = context.read<AuthState>();
    final gateway = context.read<PhoneAuthGateway>();
    final nav = Navigator.of(context);
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      // Firebase mode resends with Firebase's resend token; the server may
      // also have switched provider between two sends.
      final request = await requestOtp(auth, gateway, widget.phone, resendToken: _session?.resendToken);
      if (!mounted) return;
      switch (request) {
        case OtpCodeNeeded(:final sent, :final session):
          _code.clear();
          _idToken = null;
          _sent = sent;
          _session = session;
          if (session != null) _listenForAutoVerification();
          _startCountdown(sent.retryAfter);
          showSnack(context, S.otpResent);
        case OtpAutoVerified(:final result):
          continueAfterVerify(nav, widget.phone, result, replace: true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } on PhoneAuthFailure catch (e) {
      if (mounted) setState(() => _error = phoneAuthMessage(e));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Never a test-mode hint while Firebase sends the SMS.
    final mockCode = _session == null ? _sent.mockCode : null;

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
                    if (_autoVerifying) ...[
                      const SizedBox(height: 14),
                      const _AutoVerifyingNote(),
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

/// "Verifying automatically…" — Android read the SMS (Firebase mode).
class _AutoVerifyingNote extends StatelessWidget {
  const _AutoVerifyingNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.wine),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            S.otpVerifyingAuto,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.wine, fontWeight: FontWeight.w500),
          ),
        ),
      ],
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
