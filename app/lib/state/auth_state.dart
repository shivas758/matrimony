import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/agent.dart';
import '../models/notifications.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../services/push_service.dart';

enum AuthPhase { starting, loggedOut, loggedIn }

/// Holds the signed-in agent and the notification badge.
class AuthState extends ChangeNotifier {
  AuthState({
    required ApiClient api,
    required AuthService auth,
    required ProfileService profiles,
    PushService? push,
  })  : _api = api,
        _auth = auth,
        _profiles = profiles,
        _push = push {
    _api.addUnauthorizedListener(_onServerRejectedToken);
  }

  final ApiClient _api;
  final AuthService _auth;
  final ProfileService _profiles;

  /// Push notifications (SPEC §9.16) — best effort, off without Firebase keys.
  final PushService? _push;

  AuthPhase _phase = AuthPhase.starting;
  Agent? _agent;
  NotificationFeed _notifications = NotificationFeed.empty;
  Timer? _pollTimer;

  AuthPhase get phase => _phase;
  Agent? get agent => _agent;
  bool get isAdmin => _agent?.isAdmin ?? false;
  bool get isActive => _agent?.isActive ?? false;

  /// Logged in with a temporary password — the root shows the
  /// "set a new password" screen until this clears (SPEC §5 screen 2).
  bool get mustChangePassword => _agent?.mustChangePassword ?? false;
  NotificationFeed get notifications => _notifications;
  int get badge => _notifications.badge;

  /// Contact + hold requests waiting for my decision (Requests tab).
  int get requestsBadge => _notifications.requestsBadge;

  /// Pending clients + interests on my uploads + transfer and delete requests (Clients tab).
  int get clientsBadge => _notifications.clientsBadge;

  /// Called at startup: restores the session if a token is stored.
  Future<void> bootstrap() async {
    if (!await _auth.hasToken()) {
      _set(AuthPhase.loggedOut, null);
      return;
    }
    try {
      final agent = await _auth.me();
      _set(AuthPhase.loggedIn, agent);
      _startPolling();
    } on ApiException catch (e) {
      // A dead token logs out; a flaky network keeps the session so the app
      // can retry rather than dumping the agent back to the login screen.
      if (e.isAuthProblem) {
        await _auth.logout();
        _set(AuthPhase.loggedOut, null);
      } else {
        _set(AuthPhase.loggedOut, null);
      }
    }
  }

  Future<void> login({required String phone, required String password}) async {
    final result = await _auth.login(phone: phone, password: password);
    _set(AuthPhase.loggedIn, result.agent);
    _startPolling();
  }

  Future<void> signup({
    required String fullName,
    required String phone,
    required String password,
    required List<int> communityIds,
    required String phoneVerificationToken,
    String? agencyName,
  }) async {
    final result = await _auth.signup(
      fullName: fullName,
      phone: phone,
      password: password,
      communityIds: communityIds,
      phoneVerificationToken: phoneVerificationToken,
      agencyName: agencyName,
    );
    _set(AuthPhase.loggedIn, result.agent);
    _startPolling();
  }

  /// Replaces the signed-in agent after a self-service update
  /// (PATCH /my/account returns the refreshed row).
  void updateAgent(Agent agent) {
    if (_phase != AuthPhase.loggedIn) return;
    _agent = agent;
    notifyListeners();
    _startPush();
  }

  Future<void> logout() async {
    _stopPolling();
    // Unregister the device while the token still authenticates us.
    await _push?.stop();
    await _auth.logout();
    _notifications = NotificationFeed.empty;
    _set(AuthPhase.loggedOut, null);
  }

  /// Re-reads the agent — used by the pending screen to poll for activation.
  Future<void> refreshAgent() async {
    try {
      final agent = await _auth.me();
      _agent = agent;
      notifyListeners();
      if (agent.isActive) _startPolling();
      _startPush();
    } on ApiException {
      // Leave the current state alone; the UI shows its own error.
    }
  }

  Future<void> refreshNotifications() async {
    if (!isActive || mustChangePassword) return;
    try {
      _notifications = await _profiles.notifications();
      notifyListeners();
    } on ApiException {
      // Badge refresh is best-effort.
    }
  }

  void _startPolling() {
    // Data routes answer 403 until a temporary password has been replaced.
    if (!isActive || mustChangePassword) return;
    _pollTimer?.cancel();
    refreshNotifications();
    _pollTimer = Timer.periodic(AppConfig.notificationPollInterval, (_) => refreshNotifications());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _onServerRejectedToken() {
    if (_phase != AuthPhase.loggedIn) return;
    _stopPolling();
    _push?.stop(remote: false);
    _auth.logout();
    _set(AuthPhase.loggedOut, null);
  }

  void _set(AuthPhase phase, Agent? agent) {
    _phase = phase;
    _agent = agent;
    notifyListeners();
    _startPush();
  }

  /// Any logged-in agent (pending too) registers for push; retried on the
  /// next agent refresh if the server refused (e.g. temporary password).
  void _startPush() {
    if (_phase == AuthPhase.loggedIn && _agent != null) _push?.start();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
