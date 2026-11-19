import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../services/phone_auth_gateway.dart';
import '../../strings.dart';
import '../../theme.dart';
import 'login_screen.dart' show ErrorBanner;

/// "Verify your mobile number": the number, the one-time code, Resend with
/// its cooldown — shared by signup (SPEC §9.1) and "Forgot password?"
/// (SPEC §9.24 D). Ends with [onVerified] and the server's short-lived phone
/// verification token.
///
/// The server picks the OTP provider. `mock` / `msg91` / StartMessaging: the
/// server sends the code and checks it. `firebase` (SPEC §9.19 A): the phone
/// sends and checks the SMS through Firebase phone auth ([PhoneAuthGateway]);
/// the server then checks the Firebase ID token and answers the same
/// verification token.
class PhoneOtpStep extends StatefulWidget {
  const PhoneOtpStep({
    super.key,
    required this.purpose,
    required this.header,
    required this.onVerified,
    this.initialPhone = '',
    this.initialError,
    this.phoneHelper,
    this.describeError,
    this.codeHelp,
    this.footer,
  });

  /// Which OTP the server sends and checks.
  final OtpPurpose purpose;

  /// Shown above the number (the step title).
  final Widget header;

  /// The verified number and the token to present to the next call.
  final void Function(String phone, String verificationToken) onVerified;

  /// Pre-filled number (the login field, or the number of an earlier try).
  final String initialPhone;

  /// Shown at once, e.g. why the agent was sent back to this step.
  final String? initialError;

  /// The line under the number field.
  final String? phoneHelper;

  /// Words a server refusal for the banner; the server's message otherwise.
  final String Function(ApiException e)? describeError;

  /// Under the code field once a code was sent — gets the number.
  final Widget Function(BuildContext context, String phone, bool busy)? codeHelp;

  /// Under the main button, e.g. the way back to Login.
  final Widget Function(BuildContext context, bool busy)? footer;

  @override
  State<PhoneOtpStep> createState() => _PhoneOtpStepState();
}

class _PhoneOtpStepState extends State<PhoneOtpStep> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _phone = TextEditingController(text: widget.initialPhone);
  final _code = TextEditingController();

  /// A code was sent / the number is verified.
  bool _otpSent = false;
  bool _verified = false;
  String? _mockCode;
  int _resendIn = 0;
  Timer? _countdown;

  /// Firebase mode (SPEC §9.19 A): set by a `provider: 'firebase'` send
  /// answer, cleared by "change number".
  FirebaseClientOptions? _firebase;
  String? _verificationId;
  int? _resendToken;
  bool _autoVerifying = false;
  PhoneAuthGateway? _gateway;
  StreamSubscription<String>? _autoSub;

  bool _busy = false;
  late String? _error = widget.initialError;

  /// The code could not be sent (SMS provider down, hourly limit, Firebase
  /// refused): [PhoneOtpStep.codeHelp] is offered under the error too.
  bool _sendFailed = false;

  @override
  void dispose() {
    _countdown?.cancel();
    _autoSub?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _number => _phone.text.trim();

  String _message(ApiException e) => widget.describeError?.call(e) ?? e.message;

  // ---- the three server calls of this purpose

  Future<OtpSendResult> _sendCall(AuthService auth) => switch (widget.purpose) {
        OtpPurpose.signup => auth.sendSignupOtp(_number),
        OtpPurpose.reset => auth.sendResetOtp(_number),
      };

  Future<String> _verifyCodeCall(AuthService auth, String code) => switch (widget.purpose) {
        OtpPurpose.signup => auth.verifySignupOtp(_number, code),
        OtpPurpose.reset => auth.verifyResetOtp(_number, code),
      };

  Future<String> _verifyFirebaseCall(AuthService auth, String idToken) => switch (widget.purpose) {
        OtpPurpose.signup => auth.verifySignupFirebase(_number, idToken),
        OtpPurpose.reset => auth.verifyResetFirebase(_number, idToken),
      };

  // ---- sending

  void _startCountdown(int seconds) {
    _countdown?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn = _resendIn - 1);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _sendOtp() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _sendFailed = false;
    });
    try {
      final result = await _sendCall(context.read<AuthService>());
      if (!mounted) return;
      if (result.isFirebase) {
        await _startFirebase(result);
        return;
      }
      setState(() {
        _firebase = null;
        _otpSent = true;
        _mockCode = result.mockCode;
        _code.clear();
      });
      _startCountdown(result.retryAfter);
    } on ApiException catch (e) {
      // phone_taken / account_not_found / otp_cooldown / otp_limit.
      if (mounted) {
        setState(() {
          _error = _message(e);
          _sendFailed = e.code == 'otp_provider_error' || e.code == 'otp_limit';
        });
      }
    } on PhoneAuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _sendFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Firebase mode: the phone asks Firebase for the SMS (a Resend passes
  /// Firebase's resend token). Android may verify the number by itself —
  /// then there is nothing to type. Called with [_busy] held.
  Future<void> _startFirebase(OtpSendResult result) async {
    final gateway = _gateway ??= context.read<PhoneAuthGateway>();
    _autoSub ??= gateway.autoVerifiedIdTokens.listen(_onAutoVerified);
    // A Resend for the same number reuses Firebase's token; a first send not.
    final resendToken = _firebase != null && _otpSent ? _resendToken : null;
    setState(() {
      _firebase = result.firebase;
      _mockCode = null;
    });
    final step = await gateway.start(result.firebase!, _number, resendToken: resendToken);
    if (!mounted) return;
    switch (step) {
      case PhoneCodeSent(:final verificationId, resendToken: final token):
        setState(() {
          _otpSent = true;
          _verificationId = verificationId;
          _resendToken = token ?? _resendToken;
          _code.clear();
        });
        _startCountdown(result.retryAfter);
      case PhoneAutoVerified(:final idToken):
        setState(() {
          _otpSent = true;
          _autoVerifying = true;
        });
        _startCountdown(result.retryAfter);
        try {
          await _verifyFirebaseToken(idToken);
        } on ApiException catch (e) {
          _onFirebaseVerifyError(e);
        } finally {
          if (mounted) setState(() => _autoVerifying = false);
        }
    }
  }

  /// Android read the SMS after the code field was already shown.
  void _onAutoVerified(String idToken) {
    if (!mounted || _firebase == null || !_otpSent || _verified || _busy) return;
    _autoVerify(idToken);
  }

  Future<void> _autoVerify(String idToken) async {
    setState(() {
      _busy = true;
      _autoVerifying = true;
      _error = null;
    });
    try {
      await _verifyFirebaseToken(idToken);
    } on ApiException catch (e) {
      _onFirebaseVerifyError(e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _autoVerifying = false;
        });
      }
    }
  }

  // ---- verifying

  /// The server checks the Firebase ID token and answers the verification
  /// token. Win or lose, the Firebase session ends here — the app keeps none.
  Future<void> _verifyFirebaseToken(String idToken) async {
    try {
      final token = await _verifyFirebaseCall(context.read<AuthService>(), idToken);
      if (!mounted) return;
      _onVerified(token);
    } finally {
      unawaited(_gateway?.signOut());
    }
  }

  /// invalid_firebase_token / phone_mismatch / otp_provider_mismatch: the
  /// server message says it all. The code was spent on Firebase, so a retry
  /// needs a new one; a provider switch needs a fresh send.
  void _onFirebaseVerifyError(ApiException e) {
    if (!mounted) return;
    if (e.code == 'otp_provider_mismatch') _resetOtp();
    setState(() {
      _error = _message(e);
      _code.clear();
    });
  }

  void _onVerified(String token) {
    _countdown?.cancel();
    setState(() {
      _verified = true;
      _resendIn = 0;
    });
    widget.onVerified(_number, token);
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = S.otpInvalidLength);
      return;
    }
    if (_firebase != null) return _verifyFirebaseCode(code);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await _verifyCodeCall(context.read<AuthService>(), code);
      if (!mounted) return;
      _onVerified(token);
    } on ApiException catch (e) {
      if (!mounted) return;
      // invalid_otp keeps the field for a retry; an expired or locked code
      // needs a fresh one, so clear it and let Resend do the work.
      setState(() {
        _error = _message(e);
        if (e.code == 'otp_expired' || e.code == 'too_many_attempts') _code.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Firebase mode: the typed code → Firebase ID token → the server.
  Future<void> _verifyFirebaseCode(String code) async {
    final verificationId = _verificationId;
    final gateway = _gateway;
    if (verificationId == null || gateway == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await gateway.confirmCode(verificationId, code);
      if (!mounted) return;
      await _verifyFirebaseToken(idToken);
    } on PhoneAuthFailure catch (e) {
      if (!mounted) return;
      // A wrong code keeps the field for a retry; an expired one needs Resend.
      setState(() {
        _error = e.message;
        if (e.needsNewCode) _code.clear();
      });
    } on ApiException catch (e) {
      _onFirebaseVerifyError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Back to "enter your number" (the number itself stays in the field).
  void _resetOtp() {
    _countdown?.cancel();
    if (_firebase != null) unawaited(_gateway?.signOut());
    setState(() {
      _verified = false;
      _otpSent = false;
      _mockCode = null;
      _firebase = null;
      _verificationId = null;
      _resendToken = null;
      _autoVerifying = false;
      _resendIn = 0;
      _code.clear();
    });
  }

  void _changeNumber() {
    _resetOtp();
    setState(() => _error = null);
  }

  // ---- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.header,
          const SizedBox(height: 20),
          TextFormField(
            controller: _phone,
            readOnly: _otpSent,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _otpSent ? null : _sendOtp(),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: InputDecoration(
              labelText: S.phone,
              prefixIcon: const Icon(Icons.phone_rounded),
              prefixText: '+91 ',
              helperText: widget.phoneHelper,
              suffixIcon: _otpSent
                  ? TextButton(
                      onPressed: _busy ? null : _changeNumber,
                      child: const Text(S.changeNumber),
                    )
                  : null,
            ),
            validator: (v) => (v ?? '').trim().length == 10 ? null : S.phoneInvalid,
          ),
          if (_otpSent) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _verify(),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFamily: AppTheme.bodyFont,
                fontWeight: FontWeight.w700,
                letterSpacing: 10,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: S.otpCode,
                helperText: '${S.otpSentTo} +91 $_number',
                counterText: '',
              ),
            ),
            if (_mockCode != null) ...[
              const SizedBox(height: 10),
              _TestModeHint(code: _mockCode!),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _resendIn > 0 ? '${S.resendIn} $_resendIn s' : '',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy || _resendIn > 0 ? null : _sendOtp,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(S.resendOtp),
                ),
              ],
            ),
            if (widget.codeHelp != null) widget.codeHelp!(context, _number, _busy),
          ],
          if (_autoVerifying) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    S.verifyingAutomatically,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(message: _error!),
            if (!_otpSent && _sendFailed && widget.codeHelp != null) ...[
              const SizedBox(height: 4),
              widget.codeHelp!(context, _number, _busy),
            ],
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : (_otpSent ? _verify : _sendOtp),
            child: _busy ? const ButtonSpinner() : Text(_otpSent ? S.verifyOtp : S.sendOtp),
          ),
          if (widget.footer != null) ...[
            const SizedBox(height: 8),
            widget.footer!(context, _busy),
          ],
        ],
      ),
    );
  }
}

/// "Test mode — enter 123456" (SPEC §9.1, `OTP_PROVIDER=mock`).
class _TestModeHint extends StatelessWidget {
  const _TestModeHint({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.goldPale,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, size: 20, color: AppColors.goldDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${S.testModeHint} $code',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// The white spinner inside a busy [FilledButton].
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
      );
}

/// "STEP 1 OF 2" + title + optional explanation — the heading of each step
/// of signup and of "Forgot password?".
class AuthStepHeader extends StatelessWidget {
  const AuthStepHeader({super.key, required this.step, required this.title, this.body});

  final int step;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${S.stepOf} $step of 2'.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.goldDark,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy)),
        if (body != null) ...[
          const SizedBox(height: 6),
          Text(
            body!,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ],
    );
  }
}

/// The verified number at the top of step 2, with a way back to step 1.
class VerifiedPhoneCard extends StatelessWidget {
  const VerifiedPhoneCard({super.key, required this.phone, required this.onChange});

  final String phone;

  /// Null while busy.
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '+91 $phone',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  S.phoneVerified,
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success),
                ),
              ],
            ),
          ),
          // Wraps instead of overflowing on a narrow phone with large text.
          Flexible(
            child: TextButton(
              onPressed: onChange,
              child: const Text(S.changeNumber, textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}
