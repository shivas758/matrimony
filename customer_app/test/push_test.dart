import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/notification.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/services/push_service.dart';

/// Records calls; answers /push/config with [config] (or throws).
class _FakeApi extends ApiClient {
  _FakeApi({this.config, this.failConfig = false});

  final Map<String, dynamic>? config;
  final bool failConfig;
  final List<(String, Object?)> posts = [];
  final List<(String, Map<String, dynamic>?)> gets = [];

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    gets.add((path, query));
    if (failConfig) throw ApiException('network_error', 'offline');
    return config ?? {'enabled': false, 'options': null};
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    posts.add((path, body));
    return {'ok': true};
  }
}

class _FakePlatform implements PushPlatform {
  _FakePlatform({this.token = 'tok-1', this.initError = false, this.initial});

  final String? token;
  final bool initError;
  final PushMessage? initial;
  PushConfig? initialisedWith;
  bool permissionAsked = false;
  bool tokenDeleted = false;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();

  @override
  Future<void> initialize(PushConfig config) async {
    if (initError) throw Exception('bad Firebase options');
    initialisedWith = config;
  }

  @override
  Future<bool> requestPermission() async => permissionAsked = true;

  @override
  Future<String?> getToken() async => token;

  @override
  Future<void> deleteToken() async => tokenDeleted = true;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;

  @override
  Stream<PushMessage> get onOpenedMessage => opened.stream;

  @override
  Future<PushMessage?> getInitialMessage() async => initial;
}

Map<String, dynamic> enabledConfig() => {
      'enabled': true,
      'options': {
        'api_key': 'AIzaTest',
        'app_id': '1:123:android:abc',
        'messaging_sender_id': '123',
        'project_id': 'mediator-test',
      },
    };

void main() {
  group('PushConfig', () {
    test('enabled with every option', () {
      final c = PushConfig.fromJson(enabledConfig());
      expect(c.enabled, isTrue);
      expect(c.usable, isTrue);
      expect(c.apiKey, 'AIzaTest');
      expect(c.appId, '1:123:android:abc');
      expect(c.messagingSenderId, '123');
      expect(c.projectId, 'mediator-test');
    });

    test('disabled, null options, or a missing option → not usable', () {
      expect(PushConfig.fromJson({'enabled': false, 'options': null}).usable, isFalse);
      expect(PushConfig.fromJson({'enabled': true, 'options': null}).usable, isFalse);
      final partial = enabledConfig();
      (partial['options'] as Map).remove('app_id');
      expect(PushConfig.fromJson(partial).usable, isFalse);
      expect(PushConfig.fromJson({}).usable, isFalse);
    });
  });

  group('Push data → route (same routeFor as the Notifications screen)', () {
    test('string ids are parsed', () {
      expect(
        pushRoute({'type': 'interest_accepted', 'id': '11', 'app': 'gandharva', 'profile_id': '42'}),
        const NotificationRoute(NotificationDestination.profileDetail, 42),
      );
      expect(
        pushRoute({'type': 'payment_received', 'id': '3', 'my_profile_id': '77'}),
        const NotificationRoute(NotificationDestination.ownProfile, 77),
      );
      expect(pushRoute({'type': 'account_approved', 'id': '24'})!.destination, NotificationDestination.myProfilesTab);
      expect(pushRoute({'type': 'account_rejected', 'id': '24'})!.destination, NotificationDestination.getStarted);
      expect(pushRoute({'type': 'agent_change_rejected', 'id': '5'})!.destination, NotificationDestination.moreTab);
    });

    test('unknown type, missing ids or no data → null (open the Notifications screen)', () {
      expect(pushRoute({'type': 'brand_new', 'id': '1'}), isNull);
      expect(pushRoute({'type': 'interest_declined', 'id': '1', 'profile_id': 'abc'}), isNull);
      expect(pushRoute({}), isNull);
    });
  });

  group('PushService', () {
    test('disabled config → Firebase is never touched', () async {
      final api = _FakeApi();
      final platform = _FakePlatform();
      final push = PushService(api, platform: platform);
      expect(await push.start(), isFalse);
      expect(api.gets.single.$1, '/push/config');
      expect(api.gets.single.$2, {'app': 'gandharva'});
      expect(platform.initialisedWith, isNull);
      expect(platform.permissionAsked, isFalse);
      expect(api.posts, isEmpty);
      await push.stop();
      expect(api.posts, isEmpty, reason: 'nothing to unregister');
      expect(platform.tokenDeleted, isFalse);
    });

    test('config unreachable or a Firebase error → silently off', () async {
      final offline = PushService(_FakeApi(failConfig: true), platform: _FakePlatform());
      expect(await offline.start(), isFalse);
      final broken = PushService(_FakeApi(config: enabledConfig()), platform: _FakePlatform(initError: true));
      expect(await broken.start(), isFalse);
      expect(broken.active, isFalse);
    });

    test('enabled: init → permission → token → register; refresh re-registers; logout removes', () async {
      final api = _FakeApi(config: enabledConfig());
      final platform = _FakePlatform();
      final push = PushService(api, platform: platform);
      final foreground = <PushMessage>[];
      push.onForeground = foreground.add;

      expect(await push.start(), isTrue);
      expect(platform.initialisedWith!.projectId, 'mediator-test');
      expect(platform.permissionAsked, isTrue);
      expect(api.posts.single.$1, '/customer/push/devices');
      expect(api.posts.single.$2, {'token': 'tok-1'});

      platform.refresh.add('tok-2');
      await Future<void>.delayed(Duration.zero);
      expect(api.posts.last.$1, '/customer/push/devices');
      expect(api.posts.last.$2, {'token': 'tok-2'});

      platform.foreground.add(const PushMessage(title: 'Hi', data: {'type': 'account_approved'}));
      await Future<void>.delayed(Duration.zero);
      expect(foreground.single.title, 'Hi');

      expect(await push.start(), isTrue, reason: 'idempotent');
      expect(api.gets, hasLength(1));

      await push.stop();
      expect(api.posts.last.$1, '/customer/push/devices/remove');
      expect(api.posts.last.$2, {'token': 'tok-2'});
      expect(platform.tokenDeleted, isTrue);
      expect(push.active, isFalse);
    });

    test('a notification that launched the app is delivered to onOpened', () async {
      final platform = _FakePlatform(
        initial: const PushMessage(data: {'type': 'payment_due', 'id': '80', 'my_profile_id': '80'}),
      );
      final push = PushService(_FakeApi(config: enabledConfig()), platform: platform);
      final opened = <PushMessage>[];
      push.onOpened = opened.add;
      await push.start();
      expect(pushRoute(opened.single.data), const NotificationRoute(NotificationDestination.ownProfile, 80));
      await push.stop();
    });

    test('no token → off, nothing registered', () async {
      final api = _FakeApi(config: enabledConfig());
      final push = PushService(api, platform: _FakePlatform(token: null));
      expect(await push.start(), isFalse);
      expect(api.posts, isEmpty);
    });
  });
}
