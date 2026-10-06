import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/push_service.dart';
import 'package:matrimony_agents/state/notification_routes.dart';

/// Records calls; answers /push/config with [config] (or throws when null).
class _FakeApi extends ApiClient {
  _FakeApi(this.config);

  Map<String, dynamic>? config;
  final calls = <String>[];
  final bodies = <Object?>[];

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    calls.add('GET $path ${query?['app']}');
    if (config == null) throw ApiException('network_error', 'offline');
    return config!;
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    calls.add('POST $path');
    bodies.add(body);
    return {'ok': true};
  }
}

class _FakeMessaging implements PushMessaging {
  bool initialized = false;
  bool deleted = false;
  bool failInit = false;
  String? token = 'tok-1';
  PushMessage? initial;
  final refresh = StreamController<String>.broadcast();
  final messages = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  Future<void> initialize(PushConfig config) async {
    if (failInit) throw Exception('bad options');
    initialized = true;
  }

  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<String?> getToken() async => token;
  @override
  Future<void> deleteToken() async => deleted = true;
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Stream<PushMessage> get onMessage => messages.stream;
  @override
  Stream<PushMessage> get onMessageOpenedApp => opened.stream;
  @override
  Future<PushMessage?> getInitialMessage() async => initial;
}

const _enabled = {
  'enabled': true,
  'options': {
    'api_key': 'AIza-test',
    'app_id': '1:123:android:abc',
    'messaging_sender_id': '123',
    'project_id': 'mediator-test',
  },
};

void main() {
  group('PushConfig', () {
    test('enabled with every option', () {
      final c = PushConfig.fromJson(_enabled);
      expect(c.enabled, isTrue);
      expect(c.usable, isTrue);
      expect(c.apiKey, 'AIza-test');
      expect(c.appId, '1:123:android:abc');
      expect(c.messagingSenderId, '123');
      expect(c.projectId, 'mediator-test');
    });

    test('disabled, null options or a missing option is not usable', () {
      expect(PushConfig.fromJson({'enabled': false, 'options': null}).usable, isFalse);
      expect(PushConfig.fromJson({'enabled': true, 'options': null}).usable, isFalse);
      expect(PushConfig.fromJson(const {}).usable, isFalse);
      expect(
        PushConfig.fromJson({
          'enabled': true,
          'options': {'api_key': 'k', 'app_id': 'a', 'project_id': 'p'},
        }).usable,
        isFalse,
      );
    });
  });

  group('push data → route', () {
    test('string ids are parsed and routed like the Notifications screen', () {
      final client = pushDataToItem(
        {'type': 'profile_delete_requested', 'id': '12', 'customer_id': '5', 'profile_id': '9', 'app': 'mediator'},
        title: 'Profile delete request',
        body: 'Priya asked…',
      );
      expect(client.id, 12);
      expect(client.customerId, 5);
      expect(client.profileId, 9);
      expect(client.title, 'Profile delete request');
      expect(notificationTarget(client, isAdmin: false), const ClientTarget(5));

      final decided = pushDataToItem({'type': 'contact_request_decided', 'id': '3', 'profile_id': '7'});
      expect(notificationTarget(decided, isAdmin: false), const ProfileTarget(7));

      final interest = const PushMessage(data: {'type': 'interest_received', 'id': '4'}).toItem();
      expect(notificationTarget(interest, isAdmin: false),
          const TabTarget(HomeTab.clients, HomeSubTabs.clientsInterests));
    });

    test('junk or missing data gives no target (→ Notifications screen)', () {
      expect(notificationTarget(pushDataToItem(const {}), isAdmin: true), isNull);
      final bad = pushDataToItem({'type': 'client_pending', 'customer_id': 'abc'});
      expect(bad.customerId, isNull);
      expect(notificationTarget(bad, isAdmin: false), isNull);
      expect(notificationTarget(pushDataToItem({'type': 'summary'}), isAdmin: false), isNull);
    });
  });

  group('PushService', () {
    test('disabled config: no Firebase, no registration', () async {
      final api = _FakeApi({'enabled': false, 'options': null});
      final fm = _FakeMessaging();
      final push = PushService(api, messaging: fm);
      expect(await push.start(), isFalse);
      expect(fm.initialized, isFalse);
      expect(api.calls, ['GET /push/config mediator']);
      expect(push.isOn, isFalse);
      await push.stop();
      expect(api.calls.where((c) => c.startsWith('POST')), isEmpty);
      expect(fm.deleted, isFalse);
    });

    test('server unreachable or Firebase failing: silently off', () async {
      final offline = PushService(_FakeApi(null), messaging: _FakeMessaging());
      expect(await offline.start(), isFalse);

      final fm = _FakeMessaging()..failInit = true;
      final api = _FakeApi(_enabled);
      final broken = PushService(api, messaging: fm);
      expect(await broken.start(), isFalse);
      expect(api.calls.where((c) => c.startsWith('POST')), isEmpty);
    });

    test('enabled: registers the token, re-registers on refresh, removes on logout', () async {
      final api = _FakeApi(_enabled);
      final fm = _FakeMessaging();
      final push = PushService(api, messaging: fm);
      expect(await push.start(), isTrue);
      expect(fm.initialized, isTrue);
      expect(push.token, 'tok-1');
      expect(api.calls, ['GET /push/config mediator', 'POST /push/devices']);
      expect(api.bodies.last, {'token': 'tok-1'});

      // Idempotent while registered.
      expect(await push.start(), isTrue);
      expect(api.calls.where((c) => c == 'POST /push/devices').length, 1);

      fm.refresh.add('tok-2');
      await Future<void>.delayed(Duration.zero);
      expect(api.bodies.last, {'token': 'tok-2'});
      expect(push.token, 'tok-2');

      await push.stop();
      expect(api.calls.last, 'POST /push/devices/remove');
      expect(api.bodies.last, {'token': 'tok-2'});
      expect(fm.deleted, isTrue);
      expect(push.isOn, isFalse);

      // Logged out: a refresh is not registered.
      final before = api.calls.length;
      fm.refresh.add('tok-3');
      await Future<void>.delayed(Duration.zero);
      expect(api.calls.length, before);
    });

    test('foreground, opened and cold-start messages are forwarded', () async {
      final fm = _FakeMessaging()
        ..initial = const PushMessage(title: 'Cold', data: {'type': 'client_pending', 'customer_id': '5'});
      final push = PushService(_FakeApi(_enabled), messaging: fm);
      final opened = <PushMessage>[];
      final foreground = <PushMessage>[];
      push.openedMessages.listen(opened.add);
      push.foregroundMessages.listen(foreground.add);

      await push.start();
      fm.messages.add(const PushMessage(title: 'Hi'));
      fm.opened.add(const PushMessage(title: 'Tapped'));
      await Future<void>.delayed(Duration.zero);

      expect(opened.map((m) => m.title), ['Cold', 'Tapped']);
      expect(foreground.single.title, 'Hi');
    });
  });
}
