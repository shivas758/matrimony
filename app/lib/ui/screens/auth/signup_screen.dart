import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config.dart';
import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../../state/store_config.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/searchable_lists.dart';
import '../../widgets/terms_consent.dart';
import 'choose_state_screen.dart';
import 'login_screen.dart';
import 'phone_otp_step.dart';

/// Two-step signup (SPEC §9.1 / §9.11): verify the mobile number with an OTP
/// ([PhoneOtpStep] — mock, SMS or Firebase phone auth, SPEC §9.19 A), then
/// the details form, submitted with the phone verification token.
///
/// At most [maxCommunities] communities at signup (SPEC §9.20 C) — more are
/// requested later from My communities, ₹1000 each.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  static const maxCommunities = AppConfig.communityFreeLimit;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _detailsForm = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _agency = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final Set<int> _communityIds = {};

  /// The agent's state (SPEC §9.18 B) — decides their permanent agent code.
  int? _stateId;

  /// The number of step 1; verified once [_verificationToken] is set.
  String _phone = '';
  String? _verificationToken;

  /// Why the agent was sent back to step 1.
  String? _phoneError;

  bool _busy = false;
  bool _obscure = true;

  /// The Terms & Privacy checkbox (SPEC §9.22 C) — signup waits for it.
  bool _acceptedTerms = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The community list is public — needed before any token exists.
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<MastersState>().load());
  }

  @override
  void dispose() {
    _name.dispose();
    _agency.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // ---- step 1: the number (PhoneOtpStep)

  void _onVerified(String phone, String token) => setState(() {
        _phone = phone;
        _verificationToken = token;
        _phoneError = null;
        _error = null;
      });

  /// Back to step 1 (the number stays in the field), optionally saying why.
  void _changeNumber([String? message]) => setState(() {
        _verificationToken = null;
        _phoneError = message;
        _error = null;
      });

  // ---- step 2: details

  /// No price in a Play Store build, which cannot take the payment (SPEC §9.20 G).
  String get _tooManyMessage => StoreConfig.isPlayStore(context)
      ? S.playTooManyCommunities(SignupScreen.maxCommunities)
      : S.tooManyCommunities(SignupScreen.maxCommunities, AppConfig.extraCommunityFeeInr);

  /// A 4th chip is refused with the rule (the server's `too_many_communities`
  /// says the same).
  void _toggleCommunity(int id, bool on) {
    setState(() {
      if (!on) {
        _communityIds.remove(id);
        _error = null;
      } else if (_communityIds.length >= SignupScreen.maxCommunities) {
        _error = _tooManyMessage;
      } else {
        _communityIds.add(id);
        _error = null;
      }
    });
  }

  Future<void> _submit() async {
    if (!_detailsForm.currentState!.validate()) return;
    if (_communityIds.isEmpty) {
      setState(() => _error = S.selectOneCommunity);
      return;
    }
    if (_communityIds.length > SignupScreen.maxCommunities) {
      setState(() => _error = _tooManyMessage);
      return;
    }
    if (!_acceptedTerms) {
      setState(() => _error = S.termsRequired);
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
            phone: _phone,
            password: _password.text,
            agencyName: _agency.text.trim().isEmpty ? null : _agency.text.trim(),
            communityIds: _communityIds.toList(),
            phoneVerificationToken: token,
            stateId: _stateId,
            acceptedTerms: true,
          );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      // The 15-minute token lapsed (or the number was taken meanwhile):
      // back to step 1 with the server's message.
      if (e.code == 'phone_not_verified' || e.code == 'phone_taken') {
        _changeNumber(e.message);
        return;
      }
      // The chosen state was deactivated meanwhile — fetch the current list.
      if (e.code == 'invalid_state') {
        _stateId = null;
        context.read<MastersState>().load(force: true);
      }
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
              child: _verificationToken == null ? _phoneStep() : _detailsStep(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneStep() => PhoneOtpStep(
        purpose: OtpPurpose.signup,
        header: const AuthStepHeader(step: 1, title: S.otpStepTitle, body: S.otpStepBody),
        initialPhone: _phone,
        initialError: _phoneError,
        phoneHelper: S.phoneIsLoginId,
        onVerified: _onVerified,
        footer: (context, busy) => TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text(S.haveAccount),
        ),
      );

  Widget _detailsStep(ThemeData theme) {
    final masters = context.watch<MastersState>();
    // Empty against a server older than v2.8 — the field is left out then
    // and the agent chooses their state after the upgrade.
    final states = masters.data.activeStates;
    return Form(
      key: _detailsForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthStepHeader(step: 2, title: S.detailsStepTitle),
          const SizedBox(height: 14),
          // The verified number, with a way back to step 1.
          VerifiedPhoneCard(phone: _phone, onChange: _busy ? null : _changeNumber),
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
          if (states.isNotEmpty) ...[
            const SizedBox(height: 16),
            StateDropdown(
              states: states,
              value: _stateId,
              enabled: !_busy,
              validator: (v) => v == null ? S.stateRequired : null,
              onChanged: (v) => setState(() {
                _stateId = v;
                _error = null;
              }),
            ),
          ],
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
          const SizedBox(height: 2),
          Text(
            StoreConfig.isPlayStore(context)
                ? S.playSignupCommunitiesLimit(SignupScreen.maxCommunities)
                : S.signupCommunitiesLimit(SignupScreen.maxCommunities, AppConfig.extraCommunityFeeInr),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.goldDark,
              fontWeight: FontWeight.w600,
            ),
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
            // A long list gets a search field above the chips (SPEC §9.23 E).
            SearchableChipGroup(
              key: const ValueKey('signup-communities'),
              searchLabel: S.community,
              enabled: !_busy,
              options: masterOptions(masters.data.communities),
              selected: _communityIds,
              onToggle: (id) => _toggleCommunity(id, !_communityIds.contains(id)),
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 16),
          TermsConsent(
            value: _acceptedTerms,
            enabled: !_busy,
            onChanged: (v) => setState(() {
              _acceptedTerms = v;
              if (_error == S.termsRequired) _error = null;
            }),
          ),
          const SizedBox(height: 16),
          FilledButton(
            // Disabled until the terms are accepted.
            onPressed: _busy || !_acceptedTerms ? null : _submit,
            child: _busy ? const ButtonSpinner() : const Text(S.signup),
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
