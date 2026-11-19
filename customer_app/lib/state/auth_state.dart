import 'package:flutter/foundation.dart';

import '../models/customer.dart';
import '../services/api_client.dart';
import '../services/customer_auth_service.dart';

enum AuthPhase { starting, loggedOut, loggedIn }

/// Holds the signed-in customer and drives login (mobile + password) and the
/// one-time-code flows of Create account and Forgot password (SPEC §9.24 C).
class AuthState extends ChangeNotifier {
  AuthState({required ApiClient api, required CustomerAuthService auth})
      : _api = api,
        _auth = auth {
    _api.addUnauthorizedListener(_onServerRejectedToken);
  }

  final ApiClient _api;
  final CustomerAuthService _auth;

  /// Runs at logout while the token is still valid (push unregistration).
  Future<void> Function()? beforeLogout;

  AuthPhase _phase = AuthPhase.starting;
  Customer? _customer;

  AuthPhase get phase => _phase;
  Customer? get customer => _customer;
  AgentCard? get agent => _customer?.agent;
  bool get isActive => _customer?.isActive ?? false;
  bool get isPending => _customer?.isPending ?? false;
  bool get isRejected => _customer?.isRejected ?? false;
  bool get isSuspended => _customer?.isSuspended ?? false;
  bool get isGuest => _customer?.isGuest ?? false;

  /// Active + a paid profile: profiles and interests open (SPEC §9.12).
  bool get hasFullAccess => _customer?.hasFullAccess ?? false;

  /// Called at startup: restores the session if a token is stored.
  Future<void> bootstrap() async {
    if (!await _auth.hasToken()) {
      _set(AuthPhase.loggedOut, null);
      return;
    }
    try {
      final customer = await _auth.me();
      _set(AuthPhase.loggedIn, customer);
    } on ApiException catch (e) {
      // A dead token is cleared; on a flaky network the token stays so the
      // next launch can retry, but this launch starts at the phone screen.
      if (e.isAuthProblem) await _auth.logout();
      _set(AuthPhase.loggedOut, null);
    }
  }

  /// Log in with mobile + password (SPEC §9.24 C) — the root swaps to Home
  /// (or the blocked screen when suspended). Throws [ApiException]:
  /// `bad_credentials`, `password_not_set`, …
  Future<void> login({required String phone, required String password}) async {
    final result = await _auth.login(phone: phone, password: password);
    _set(AuthPhase.loggedIn, result.customer);
  }

  /// Create account / Forgot password, step 1 — ask the server for a code
  /// for [purpose]. The screen shows [OtpSent.mockCode] in test mode and
  /// counts down [OtpSent.retryAfter] before "Resend".
  Future<OtpSent> sendOtp(String phone, {required OtpPurpose purpose}) =>
      _auth.sendOtp(phone, purpose: purpose);

  /// Step 2 — the code checks the number: [PhoneVerified] with the token the
  /// signup / new-password screen must carry. (Only a server older than
  /// v2.14 logs a known number in here instead.)
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String code,
    required OtpPurpose purpose,
  }) async {
    final result = await _auth.verifyOtp(phone: phone, code: code, purpose: purpose);
    if (result is LoggedIn) _set(AuthPhase.loggedIn, result.customer);
    return result;
  }

  /// Step 2 with Firebase phone auth (SPEC §9.19 A): the ID token instead of
  /// the code — same answers as [verifyOtp].
  Future<OtpVerifyResult> verifyFirebaseToken({
    required String phone,
    required String idToken,
    required OtpPurpose purpose,
  }) async {
    final result = await _auth.verifyFirebaseToken(phone: phone, idToken: idToken, purpose: purpose);
    if (result is LoggedIn) _set(AuthPhase.loggedIn, result.customer);
    return result;
  }

  /// Create account, step 3 — name + password: the account starts as a
  /// guest and lands on Home straight away (SPEC §9.12 / §9.24 C).
  Future<void> signup({
    required String fullName,
    required String phone,
    required String password,
    required String verificationToken,
    bool acceptedTerms = false,
  }) async {
    final result = await _auth.signup(
      fullName: fullName,
      phone: phone,
      password: password,
      verificationToken: verificationToken,
      acceptedTerms: acceptedTerms,
    );
    _set(AuthPhase.loggedIn, result.customer);
  }

  /// Forgot password, step 3 — the new password; logged in straight after.
  Future<void> resetPassword({
    required String phone,
    required String verificationToken,
    required String newPassword,
  }) async {
    final result = await _auth.resetPassword(
      phone: phone,
      verificationToken: verificationToken,
      newPassword: newPassword,
    );
    _set(AuthPhase.loggedIn, result.customer);
  }

  /// More → Change password / Set a password ([currentPassword] null). The
  /// account has a password afterwards. Throws [ApiException]
  /// (`bad_credentials` for a wrong current password).
  Future<void> changePassword({String? currentPassword, required String newPassword}) async {
    await _auth.changePassword(currentPassword: currentPassword, newPassword: newPassword);
    final c = _customer;
    if (_phase == AuthPhase.loggedIn && c != null && !c.hasPassword) {
      _customer = c.copyWith(hasPassword: true);
      notifyListeners();
    }
  }

  /// Re-reads the customer (`/customer/auth/me`) — after every action that
  /// can change access, profiles or the agent, and when Get started polls.
  /// Throws [ApiException] so a manual "Check again" can show the error;
  /// a token the server rejects logs out via the client's listener.
  Future<void> refreshCustomer() async {
    final customer = await _auth.me();
    if (_phase != AuthPhase.loggedIn) return;
    _customer = customer;
    notifyListeners();
  }

  /// Best-effort [refreshCustomer]: errors are swallowed (the screens keep
  /// what they have). Returns whether it worked.
  Future<bool> refresh() async {
    try {
      await refreshCustomer();
      return true;
    } on ApiException {
      return false;
    }
  }

  /// Applies a customer the server just returned (link agent, payment).
  void setCustomer(Customer customer) {
    if (_phase != AuthPhase.loggedIn) return;
    _customer = customer;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await beforeLogout?.call();
    } catch (_) {
      // Best effort — logging out must always work.
    }
    await _auth.logout();
    _set(AuthPhase.loggedOut, null);
  }

  void _onServerRejectedToken() {
    if (_phase != AuthPhase.loggedIn) return;
    // The session is already dead; the hook still drops the local push token.
    beforeLogout?.call().catchError((_) {});
    _auth.logout();
    _set(AuthPhase.loggedOut, null);
  }

  void _set(AuthPhase phase, Customer? customer) {
    _phase = phase;
    _customer = customer;
    notifyListeners();
  }
}
