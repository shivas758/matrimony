import 'package:flutter/foundation.dart';

import '../models/customer.dart';
import '../services/api_client.dart';
import '../services/customer_auth_service.dart';

enum AuthPhase { starting, loggedOut, loggedIn }

/// Holds the signed-in customer and drives the phone → OTP → signup flow.
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

  /// Step 1 — ask the server for a code. The screen shows [OtpSent.mockCode]
  /// in test mode and counts down [OtpSent.retryAfter] before "Resend".
  Future<OtpSent> sendOtp(String phone) => _auth.sendOtp(phone);

  /// Step 2 — a known number logs in here (the root swaps to Home, or the
  /// blocked screen when suspended); a new number returns [NeedsSignup] with the
  /// verification token the signup screen must carry.
  Future<OtpVerifyResult> verifyOtp({required String phone, required String code}) async {
    final result = await _auth.verifyOtp(phone: phone, code: code);
    if (result is LoggedIn) _set(AuthPhase.loggedIn, result.customer);
    return result;
  }

  /// Step 3 (new numbers only) — just the name: the account starts as a
  /// guest and lands on Home straight away (SPEC §9.12).
  Future<void> signup({
    required String fullName,
    required String phone,
    required String verificationToken,
  }) async {
    final result = await _auth.signup(
      fullName: fullName,
      phone: phone,
      verificationToken: verificationToken,
    );
    _set(AuthPhase.loggedIn, result.customer);
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
