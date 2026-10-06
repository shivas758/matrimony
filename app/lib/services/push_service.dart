import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/notifications.dart';
import 'api_client.dart';

/// `GET /push/config?app=mediator` (SPEC §9.16): the public Firebase client
/// options, or disabled. The app ships without google-services.json — the
/// server hands the options over, so push switches on without a rebuild.
class PushConfig {
  const PushConfig({
    required this.enabled,
    this.apiKey,
    this.appId,
    this.messagingSenderId,
    this.projectId,
  });

  final bool enabled;
  final String? apiKey;
  final String? appId;
  final String? messagingSenderId;
  final String? projectId;

  static const disabled = PushConfig(enabled: false);

  /// Enabled only when the server says so AND every option is present.
  bool get usable =>
      enabled &&
      [apiKey, appId, messagingSenderId, projectId].every((v) => v != null && v.isNotEmpty);

  factory PushConfig.fromJson(Map<String, dynamic> j) {
    final o = j['options'];
    if (j['enabled'] != true || o is! Map) return disabled;
    String? s(Object? v) => v == null ? null : '$v';
    return PushConfig(
      enabled: true,
      apiKey: s(o['api_key']),
      appId: s(o['app_id']),
      messagingSenderId: s(o['messaging_sender_id']),
      projectId: s(o['project_id']),
    );
  }
}

/// A push as the app sees it: the system notification's text plus the
/// string `data` map (`type, id, profile_id, customer_id, …`).
class PushMessage {
  const PushMessage({this.title, this.body, this.data = const {}});

  final String? title;
  final String? body;
  final Map<String, dynamic> data;

  /// The same shape the Notifications screen routes (ids arrive as strings).
  NotificationItem toItem() => pushDataToItem(data, title: title, body: body);
}

/// Push `data` (all strings) → a NotificationItem for notificationTarget().
NotificationItem pushDataToItem(Map<String, dynamic> data, {String? title, String? body}) {
  int? n(Object? v) => v == null ? null : int.tryParse('$v'.trim());
  return NotificationItem(
    type: '${data['type'] ?? ''}',
    title: title ?? '',
    body: body ?? '',
    id: n(data['id']),
    profileId: n(data['profile_id']),
    customerId: n(data['customer_id']),
  );
}

/// The Firebase calls PushService needs — a seam so tests run without
/// Firebase (FirebasePushMessaging is the real one).
abstract class PushMessaging {
  Future<void> initialize(PushConfig config);
  Future<bool> requestPermission();
  Future<String?> getToken();
  Future<void> deleteToken();
  Stream<String> get onTokenRefresh;
  Stream<PushMessage> get onMessage;
  Stream<PushMessage> get onMessageOpenedApp;
  Future<PushMessage?> getInitialMessage();
}

class FirebasePushMessaging implements PushMessaging {
  static PushMessage _from(RemoteMessage m) => PushMessage(
        title: m.notification?.title,
        body: m.notification?.body,
        data: m.data,
      );

  @override
  Future<void> initialize(PushConfig config) async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: config.apiKey!,
        appId: config.appId!,
        messagingSenderId: config.messagingSenderId!,
        projectId: config.projectId!,
      ),
    );
  }

  @override
  Future<bool> requestPermission() async {
    final s = await FirebaseMessaging.instance.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => FirebaseMessaging.instance.getToken();

  @override
  Future<void> deleteToken() => FirebaseMessaging.instance.deleteToken();

  @override
  Stream<String> get onTokenRefresh => FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<PushMessage> get onMessage => FirebaseMessaging.onMessage.map(_from);

  @override
  Stream<PushMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp.map(_from);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final m = await FirebaseMessaging.instance.getInitialMessage();
    return m == null ? null : _from(m);
  }
}

/// Push notifications (SPEC §9.16). Everything is best effort: when the
/// server has no Firebase keys, is unreachable, or Firebase fails, push is
/// simply off and the app works as before.
class PushService {
  PushService(this._api, {PushMessaging? messaging, this.app = 'mediator'})
      : _messagingOverride = messaging;

  final ApiClient _api;
  final PushMessaging? _messagingOverride;
  final String app;

  PushMessaging? _messaging;
  PushMessaging get _m => _messaging ??= _messagingOverride ?? FirebasePushMessaging();

  bool _initialized = false;
  bool _starting = false;

  /// Between start() and stop(): token refreshes are registered only then.
  bool _active = false;
  String? _token;
  final List<StreamSubscription<dynamic>> _subs = [];

  final _foreground = StreamController<PushMessage>.broadcast();
  final _opened = StreamController<PushMessage>.broadcast();

  /// Messages arriving while the app is open.
  Stream<PushMessage> get foregroundMessages => _foreground.stream;

  /// System notifications the user tapped (background or cold start).
  Stream<PushMessage> get openedMessages => _opened.stream;

  /// The token registered with the server for this session, if any.
  String? get token => _token;
  bool get isOn => _token != null;

  Future<PushConfig> fetchConfig() async {
    final json = await _api.get('/push/config', query: {'app': app});
    return PushConfig.fromJson(json);
  }

  /// After login (any agent status): config → Firebase → permission → token
  /// → register. Safe to call repeatedly; returns whether push is on.
  Future<bool> start() async {
    if (_token != null || _starting) return _token != null;
    _starting = true;
    _active = true;
    try {
      final config = await fetchConfig();
      if (!config.usable) return false;
      if (!_initialized) {
        await _m.initialize(config);
        _initialized = true;
        _subs.add(_m.onMessage.listen(_foreground.add));
        _subs.add(_m.onMessageOpenedApp.listen(_opened.add));
        _subs.add(_m.onTokenRefresh.listen((t) {
          if (_active) _register(t);
        }));
        final initial = await _m.getInitialMessage();
        if (initial != null) _opened.add(initial);
      }
      await _m.requestPermission();
      final token = await _m.getToken();
      if (token == null || token.isEmpty) return false;
      await _register(token);
      return _token != null;
    } catch (e) {
      debugPrint('push off: $e');
      return false;
    } finally {
      _starting = false;
    }
  }

  Future<void> _register(String token) async {
    try {
      await _api.post('/push/devices', body: {'token': token});
      _token = token;
    } catch (e) {
      debugPrint('push register failed: $e');
    }
  }

  /// On logout: tell the server (while still authenticated — best effort)
  /// and drop the FCM token so the next account gets a fresh one.
  Future<void> stop({bool remote = true}) async {
    final token = _token;
    _token = null;
    _active = false;
    if (token != null && remote) {
      try {
        await _api.post('/push/devices/remove', body: {'token': token});
      } catch (_) {
        // Best effort.
      }
    }
    if (_initialized) {
      try {
        await _m.deleteToken();
      } catch (_) {
        // Best effort.
      }
    }
  }
}
