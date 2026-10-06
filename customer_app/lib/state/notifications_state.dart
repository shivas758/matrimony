import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification.dart';
import '../services/api_client.dart';

/// Fetches the raw feed; injectable for tests.
typedef NotificationsFetch = Future<Map<String, dynamic>> Function();

/// Loads GET /customer/notifications (SPEC §9.15) and keeps the per-device
/// "last opened" timestamp behind the bell count. One poller: [start] when
/// the home shell appears (every [interval], plus [refresh] when the app
/// returns to the foreground), [stop] when it goes away (logout, suspension).
class NotificationsState extends ChangeNotifier {
  NotificationsState(ApiClient api, {this.interval = const Duration(seconds: 60), NotificationsFetch? fetch})
      : _fetch = fetch ?? (() => api.get('/customer/notifications'));

  final NotificationsFetch _fetch;
  final Duration interval;

  NotificationFeed _feed = NotificationFeed.empty;
  DateTime? _lastOpened;

  /// [lastOpened] as it was when the screen was last opened — the "new" dots
  /// on that visit are measured against it.
  DateTime? _seenBefore;
  int? _customerId;
  Timer? _timer;
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  NotificationFeed get feed => _feed;
  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  DateTime? get lastOpened => _lastOpened;

  /// The bell: action items + updates newer than the last opening.
  int get badgeCount => _feed.badgeCount(_lastOpened);

  /// The "new" dot on the screen currently open.
  bool isNew(AppNotification n) => NotificationFeed.isNew(n, _seenBefore);

  static String _key(int customerId) => 'notifications_last_opened_$customerId';

  /// Starts polling for [customerId] (a different customer starts clean).
  Future<void> start(int customerId) async {
    if (_customerId != customerId) {
      _feed = NotificationFeed.empty;
      _loaded = false;
      _customerId = customerId;
      _lastOpened = await _readLastOpened(customerId);
      _seenBefore = _lastOpened;
    }
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => refresh());
    await refresh();
  }

  /// Stops polling and forgets the feed. [notify] false when called while
  /// the widget tree is being torn down (HomeShell.dispose).
  void stop({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    _customerId = null;
    _feed = NotificationFeed.empty;
    _loaded = false;
    if (notify) notifyListeners();
  }

  Future<void> refresh() async {
    if (_customerId == null || _loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final json = await _fetch();
      if (_customerId == null) return;
      _feed = NotificationFeed.fromJson(json);
      _loaded = true;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The screen was opened: remember now (the dots of this visit still use
  /// the previous value).
  Future<void> markOpened({DateTime? now}) async {
    final id = _customerId;
    _seenBefore = _lastOpened;
    _lastOpened = now ?? DateTime.now();
    notifyListeners();
    if (id == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(id), _lastOpened!.toUtc().toIso8601String());
    } catch (_) {
      // Storage unavailable — the count simply resets next launch.
    }
  }

  static Future<DateTime?> _readLastOpened(int customerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key(customerId));
      return v == null ? null : DateTime.tryParse(v)?.toLocal();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
