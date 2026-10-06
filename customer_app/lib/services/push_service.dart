import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/notification.dart';
import 'api_client.dart';

/// GET /api/push/config?app=gandharva (SPEC §9.16) → `{enabled, options}`.
/// The Firebase client options are public; they come from the server so the
/// APK needs no google-services.json and push can be switched on later
/// without an app update.
class PushConfig {
  const PushConfig({required this.enabled, this.apiKey, this.appId, this.messagingSenderId, this.projectId});

  final bool enabled;
  final String? apiKey;
  final String? appId;
  final String? messagingSenderId;
  final String? projectId;

  static const disabled = PushConfig(enabled: false);

  /// Enabled AND every option present — otherwise push stays off.
  bool get usable =>
      enabled &&
      [apiKey, appId, messagingSenderId, projectId].every((v) => v != null && v.isNotEmpty);

  factory PushConfig.fromJson(Map<String, dynamic> j) {
    final o = j['options'];
    if (o is! Map) return PushConfig(enabled: j['enabled'] == true);
    String? str(String k) => o[k] == null ? null : '${o[k]}';
    return PushConfig(
      enabled: j['enabled'] == true,
      apiKey: str('api_key'),
      appId: str('app_id'),
      messagingSenderId: str('messaging_sender_id'),
      projectId: str('project_id'),
    );
  }
}

/// A received push, reduced to what the app uses.
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;

  /// FCM data — all strings: type, id, app, profile_id, my_profile_id, …
  final Map<String, String> data;
}

/// Where a tapped push goes: the same [routeFor] as the Notifications
/// screen, from the push's string data. Null → open the Notifications screen
/// (unknown type, missing ids, empty data).
NotificationRoute? pushRoute(Map<String, String> data) {
  int? i(String k) => int.tryParse(data[k] ?? '');
  final type = data['type'];
  if (type == null || type.isEmpty) return null;
  final route = routeFor(AppNotification(
    type: type,
    group: 'update',
    id: i('id') ?? 0,
    title: '',
    profileId: i('profile_id'),
    myProfileId: i('my_profile_id'),
    interestId: i('interest_id'),
  ));
  return route.tappable ? route : null;
}

/// The Firebase calls, behind an interface so the flow is testable without
/// a Firebase project.
abstract class PushPlatform {
  Future<void> initialize(PushConfig config);
  Future<bool> requestPermission();
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;
  Stream<PushMessage> get onForegroundMessage;
  Stream<PushMessage> get onOpenedMessage;
  Future<PushMessage?> getInitialMessage();
}

class FirebasePushPlatform implements PushPlatform {
  FirebaseMessaging get _m => FirebaseMessaging.instance;

  static PushMessage _convert(RemoteMessage m) => PushMessage(
        title: m.notification?.title,
        body: m.notification?.body,
        data: {for (final e in m.data.entries) e.key: '${e.value}'},
      );

  @override
  Future<void> initialize(PushConfig c) async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: c.apiKey!,
        appId: c.appId!,
        messagingSenderId: c.messagingSenderId!,
        projectId: c.projectId!,
      ),
    );
  }

  @override
  Future<bool> requestPermission() async {
    final s = await _m.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _m.getToken();

  @override
  Future<void> deleteToken() => _m.deleteToken();

  @override
  Stream<String> get onTokenRefresh => _m.onTokenRefresh;

  @override
  Stream<PushMessage> get onForegroundMessage => FirebaseMessaging.onMessage.map(_convert);

  @override
  Stream<PushMessage> get onOpenedMessage => FirebaseMessaging.onMessageOpenedApp.map(_convert);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final m = await _m.getInitialMessage();
    return m == null ? null : _convert(m);
  }
}

/// Push notifications for Gandharva (SPEC §9.16), isolated here. Everything
/// is best effort: config unreachable / disabled / any Firebase error →
/// push is simply off and the app works as before.
class PushService {
  PushService(this._api, {PushPlatform? platform}) : _platform = platform ?? FirebasePushPlatform();

  final ApiClient _api;
  final PushPlatform _platform;

  bool _active = false;
  String? _token;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// A push arrived while the app was open.
  void Function(PushMessage message)? onForeground;

  /// A system notification was tapped (background or from terminated).
  void Function(PushMessage message)? onOpened;

  bool get active => _active;
  String? get token => _token;

  /// Fetches the config; any failure means "disabled".
  Future<PushConfig> fetchConfig() async {
    try {
      return PushConfig.fromJson(await _api.get('/push/config', query: {'app': 'gandharva'}));
    } catch (_) {
      return PushConfig.disabled;
    }
  }

  /// After login (any status): config → Firebase → permission → token →
  /// register; re-register on refresh; listen for messages. Returns whether
  /// push is on.
  Future<bool> start() async {
    if (_active) return true;
    try {
      final config = await fetchConfig();
      if (!config.usable) return false;
      await _platform.initialize(config);
      await _platform.requestPermission();
      final token = await _platform.getToken();
      if (token == null || token.isEmpty) return false;
      _token = token;
      _active = true;
      await _register(token);
      _subs
        ..add(_platform.onTokenRefresh.listen((t) {
          _token = t;
          _register(t);
        }))
        ..add(_platform.onForegroundMessage.listen((m) => onForeground?.call(m)))
        ..add(_platform.onOpenedMessage.listen((m) => onOpened?.call(m)));
      final initial = await _platform.getInitialMessage();
      if (initial != null) onOpened?.call(initial);
      return true;
    } catch (e) {
      debugPrint('[push] off: $e');
      await _cancelSubs();
      _active = false;
      return false;
    }
  }

  /// Logout: unregister the token (while the session still works) and drop it.
  Future<void> stop() async {
    final token = _token;
    final wasActive = _active;
    _active = false;
    _token = null;
    await _cancelSubs();
    if (!wasActive) return;
    if (token != null) {
      try {
        await _api.post('/customer/push/devices/remove', body: {'token': token});
      } catch (_) {
        // Best effort — the server drops dead tokens on its own.
      }
    }
    try {
      await _platform.deleteToken();
    } catch (_) {}
  }

  Future<void> _register(String token) async {
    try {
      await _api.post('/customer/push/devices', body: {'token': token});
    } catch (e) {
      debugPrint('[push] register failed: $e');
    }
  }

  Future<void> _cancelSubs() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }
}
