import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import 'login_screen.dart';

/// Two-step signup (SPEC §9.1 / §9.11): verify the mobile number with an OTP,
/// then the details form, submitted with the phone verification token.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _phoneForm = GlobalKey<FormState>();
  final _detailsForm = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _agency = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final Set<int> _communityIds = {};

  /// Step 1 state: a code was sent / the number is verified.
  bool _otpSent = false;
  bool _verified = false;
  String? _mockCode;
  String? _verificationToken;
  int _resendIn = 0;
  Timer? _countdown;

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The community list is public — needed before any token exists.
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<MastersState>().load());
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _phone.dispose();
    _code.dispose();
    _name.dispose();
    _agency.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // ---- step 1: OTP

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
    if (!_phoneForm.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context.read<AuthService>().sendSignupOtp(_phone.text.trim());
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _mockCode = result.mockCode;
        _code.clear();
      });
      _startCountdown(result.retryAfter);
    } on ApiException catch (e) {
      // phone_taken / otp_cooldown / otp_limit — the server message says it all.
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = S.otpInvalidLength);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await context.read<AuthService>().verifySignupOtp(_phone.text.trim(), code);
      if (!mounted) return;
      _countdown?.cancel();
      setState(() {
        _verificationToken = token;
        _verified = true;
        _resendIn = 0;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // invalid_otp keeps the field for a retry; an expired or locked code
      // needs a fresh one, so clear it and let Resend do the work.
      setState(() {
        _error = e.message;
        if (e.code == 'otp_expired' || e.code == 'too_many_attempts') _code.clear();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    _countdown?.cancel();
    setState(() {
      _verified = false;
      _otpSent = false;
      _verificationToken = null;
      _mockCode = null;
      _resendIn = 0;
      _error = null;
      _code.clear();
    });
  }

  // ---- step 2: details

  Future<void> _submit() async {
    if (!_detailsForm.currentState!.validate()) return;
    if (_communityIds.isEmpty) {
      setState(() => _error = S.selectOneCommunity);
      return;
    }
    final token = _verificationToken;
    if (token == null) {
      _changeNumber();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().signup(
            fullName: _name.text.trim(),
            phone: _phone.text.trim(),
            password: _password.text,
            agencyName: _agency.text.trim().isEmpty ? null : _agency.text.trim(),
            communityIds: _communityIds.toList(),
            phoneVerificationToken: token,
          );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      // The 15-minute token lapsed (or the number was taken meanwhile):
      // back to step 1 with the server's message.
      if (e.code == 'phone_not_verified' || e.code == 'phone_taken') _changeNumber();
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(S.signup)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _verified ? _detailsStep(theme) : _phoneStep(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _spinner() => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
      );

  Widget _phoneStep(ThemeData theme) {
    final phone = _phone.text.trim();
    return Form(
      key: _phoneForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepHeader(step: 1, title: S.otpStepTitle, body: S.otpStepBody),
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
              helperText: 'This is your login ID',
              suffixIcon: _otpSent
                  ? TextButton(
                      onPressed: _busy ? null : _changeNumber,
                      child: const Text(S.changeNumber),
                    )
                  : null,
            ),
            validator: (v) =>
                (v ?? '').trim().length == 10 ? null : 'Enter a valid 10-digit mobile number',
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
                helperText: '${S.otpSentTo} +91 $phone',
                counterText: '',
              ),
            ),
            if (_mockCode != null) ...[
              const SizedBox(height: 10),
              Container(
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
                        '${S.testModeHint} $_mockCode',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
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
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : (_otpSent ? _verify : _sendOtp),
            child: _busy ? _spinner() : Text(_otpSent ? S.verifyOtp : S.sendOtp),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text(S.haveAccount),
          ),
        ],
      ),
    );
  }

  Widget _detailsStep(ThemeData theme) {
    final masters = context.watch<MastersState>();
    return Form(
      key: _detailsForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepHeader(step: 2, title: S.detailsStepTitle),
          const SizedBox(height: 14),
          // The verified number, with a way back to step 1.
          Container(
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
                        '+91 ${_phone.text.trim()}',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        S.phoneVerified,
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _changeNumber,
                  child: const Text(S.changeNumber),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: S.fullName,
              prefixIcon: Icon(Icons.person_rounded),
            ),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your full name' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _agency,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: S.agencyName,
              prefixIcon: Icon(Icons.storefront_rounded),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: S.password,
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v ?? '').length < 6 ? 'Use at least 6 characters' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirm,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: S.confirmPassword,
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            validator: (v) => v != _password.text ? 'Passwords do not match' : null,
          ),
          const SizedBox(height: 28),
          Text(S.selectCommunities, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            S.selectCommunitiesHint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 12),
          if (masters.loading && !masters.isLoaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (masters.error != null && !masters.isLoaded)
            OutlinedButton.icon(
              onPressed: () => context.read<MastersState>().load(force: true),
              icon: const Icon(Icons.refresh_rounded),
              label: Text('${masters.error} — ${S.retry}'),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in masters.data.communities)
                  FilterChip(
                    label: Text(c.name),
                    selected: _communityIds.contains(c.id),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _communityIds.add(c.id);
                      } else {
                        _communityIds.remove(c.id);
                      }
                      _error = null;
                    }),
                  ),
              ],
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? _spinner() : const Text(S.signup),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text(S.haveAccount),
          ),
        ],
      ),
    );
  }
}

/// "STEP 1 OF 2" + title + optional explanation.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.title, this.body});

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
