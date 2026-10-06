import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/notification.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/state/notifications_state.dart';
import 'package:gandharva/ui/screens/notifications/notifications_screen.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:gandharva/ui/widgets/notification_bell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GET /customer/notifications exactly as routes/customerNotifications.js
/// builds it: action items first, each group newest first.
Map<String, dynamic> feedJson() => {
      'action_count': 2,
      'items': [
        {
          'type': 'payment_due',
          'group': 'action',
          'id': 80,
          'my_profile_id': 80,
          'title': 'Pay the registration fee',
          'body': "Sita's profile is shown to families after the ₹150 fee.",
          'at': '2026-09-20T10:00:00.000Z',
        },
        {
          'type': 'interest_expiring',
          'group': 'action',
          'id': 12,
          'interest_id': 12,
          'profile_id': 41,
          'title': 'Shared details end soon',
          'body': "Lakshmi's details are visible for 2 more days.",
          'at': '2026-09-30T10:00:00.000Z',
        },
        {
          'type': 'interest_accepted',
          'group': 'update',
          'id': 11,
          'interest_id': 11,
          'profile_id': 42,
          'my_profile_id': 79,
          'title': 'Details shared with you',
          'body': 'Anitha — for Ravi',
          'at': '2026-09-28T09:00:00.000Z',
        },
        {
          'type': 'account_approved',
          'group': 'update',
          'id': 24,
          'title': 'Your account is approved',
          'body': 'Agent A approved your account.',
          'at': '2026-09-27T09:00:00.000Z',
        },
        {
          'type': 'brand_new_type',
          'group': 'update',
          'id': 1,
          'title': 'Something new',
          'at': '2026-09-26T09:00:00.000Z',
        },
      ],
    };

AppNotification n(String type, {int? profileId, int? myProfileId, String group = 'update'}) =>
    AppNotification(type: type, group: group, id: 1, title: type, profileId: profileId, myProfileId: myProfileId);

void main() {
  group('Feed parsing, grouping and the bell count', () {
    final feed = NotificationFeed.fromJson(feedJson());

    test('groups keep the server order', () {
      expect(feed.actionCount, 2);
      expect(feed.actions.map((x) => x.type), ['payment_due', 'interest_expiring']);
      expect(feed.updates.map((x) => x.type), ['interest_accepted', 'account_approved', 'brand_new_type']);
      final first = feed.items.first;
      expect(first.isAction, isTrue);
      expect(first.myProfileId, 80);
      expect(first.at, isNotNull);
      expect(feed.items[2].interestId, 11);
      expect(feed.items[2].profileId, 42);
    });

    test('never opened → every update is new', () {
      expect(feed.badgeCount(null), 2 + 3);
    });

    test('updates newer than the last opening count; actions always count', () {
      final lastOpened = DateTime.parse('2026-09-27T12:00:00.000Z');
      expect(NotificationFeed.isNew(feed.updates[0], lastOpened), isTrue);
      expect(NotificationFeed.isNew(feed.updates[1], lastOpened), isFalse);
      expect(NotificationFeed.isNew(feed.actions[0], lastOpened), isFalse, reason: 'actions have no dot');
      expect(feed.badgeCount(lastOpened), 2 + 1);
      expect(feed.badgeCount(DateTime.parse('2026-10-01T00:00:00Z')), 2);
    });

    test('empty / missing keys are tolerated', () {
      final empty = NotificationFeed.fromJson({});
      expect(empty.items, isEmpty);
      expect(empty.badgeCount(null), 0);
      final noCount = NotificationFeed.fromJson({'items': feedJson()['items']});
      expect(noCount.actionCount, 2, reason: 'derived from the items');
      final odd = AppNotification.fromJson({'type': 'x', 'group': 'weird', 'id': 3, 'title': 't', 'at': null});
      expect(odd.isAction, isFalse);
      expect(odd.at, isNull);
    });
  });

  group('Routing per type (SPEC §9.15 table)', () {
    const own = NotificationDestination.ownProfile;
    const detail = NotificationDestination.profileDetail;

    test('actions', () {
      expect(routeFor(n('payment_due', myProfileId: 80)), const NotificationRoute(own, 80));
      expect(routeFor(n('interest_expiring', profileId: 41)), const NotificationRoute(detail, 41));
    });

    test('interest decisions open that profile', () {
      for (final t in ['interest_accepted', 'interest_declined', 'interest_revoked']) {
        expect(routeFor(n(t, profileId: 42, myProfileId: 79)), const NotificationRoute(detail, 42), reason: t);
      }
      expect(routeFor(n('interest_accepted')).tappable, isFalse, reason: 'no profile id');
    });

    test('account, payments, agent change and delete requests', () {
      expect(routeFor(n('account_approved')).destination, NotificationDestination.myProfilesTab);
      expect(routeFor(n('account_rejected')).destination, NotificationDestination.getStarted);
      expect(routeFor(n('payment_received', myProfileId: 77)), const NotificationRoute(own, 77));
      expect(routeFor(n('payment_received')).destination, NotificationDestination.myProfilesTab,
          reason: 'the profile may be gone');
      expect(routeFor(n('delete_request_rejected', myProfileId: 77)), const NotificationRoute(own, 77));
      expect(routeFor(n('delete_request_rejected')).destination, NotificationDestination.myProfilesTab);
      expect(routeFor(n('delete_request_approved', myProfileId: 77)).destination,
          NotificationDestination.myProfilesTab);
      expect(routeFor(n('agent_change_approved')).destination, NotificationDestination.moreTab);
      expect(routeFor(n('agent_change_rejected')).destination, NotificationDestination.moreTab);
    });

    test('unknown types are not tappable', () {
      expect(routeFor(n('brand_new_type')), NotificationRoute.none);
      expect(routeFor(n('brand_new_type')).tappable, isFalse);
    });
  });

  group('Relative time', () {
    final now = DateTime(2026, 9, 28, 15, 0);

    test('past', () {
      expect(S.relativeTime(now.subtract(const Duration(seconds: 20)), now), 'Just now');
      expect(S.relativeTime(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
      expect(S.relativeTime(now.subtract(const Duration(hours: 3)), now), '3 h ago');
      expect(S.relativeTime(DateTime(2026, 9, 27, 23, 0), now), 'Yesterday');
      expect(S.relativeTime(DateTime(2026, 9, 24, 10, 0), now), '4 days ago');
      expect(S.relativeTime(DateTime(2026, 9, 12, 10, 0), now), '12 Sep 2026');
    });

    test('future (an interest that ends soon)', () {
      expect(S.relativeTime(now.add(const Duration(minutes: 30)), now), 'in 30 min');
      expect(S.relativeTime(now.add(const Duration(hours: 5)), now), 'in 5 h');
      expect(S.relativeTime(now.add(const Duration(hours: 30)), now), 'in 2 days');
      expect(S.relativeTime(now.add(const Duration(hours: 24)), now), 'in 1 day');
    });
  });

  group('Screen + bell', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<NotificationsState> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final state = _fake();
      await state.start(24); // as the home shell does before any screen opens
      await tester.pumpWidget(
        ChangeNotifierProvider<NotificationsState>.value(
          value: state,
          child: MaterialApp(theme: AppTheme.light(), home: child),
        ),
      );
      await tester.pump();
      return state;
    }

    testWidgets('bell shows actions + unseen updates', (tester) async {
      final state = await pump(tester, Scaffold(appBar: AppBar(actions: const [NotificationBell()])));
      expect(find.text('5'), findsOneWidget);
      state.stop(); // cancels the poller timer
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('screen lists both groups, marks as opened, unknown type has no chevron', (tester) async {
      final state = await pump(tester, const NotificationsScreen());
      await tester.pump();
      expect(find.text(S.needsYourAction.toUpperCase()), findsOneWidget);
      expect(find.text(S.updates.toUpperCase()), findsOneWidget);
      expect(find.text('Pay the registration fee'), findsOneWidget);
      expect(find.text('Something new'), findsOneWidget);
      expect(state.lastOpened, isNotNull);
      expect(state.badgeCount, 2, reason: 'opening clears the unseen updates');
      // 4 tappable rows get a chevron; the unknown type does not.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNWidgets(4));
      expect(tester.takeException(), isNull);
      state.stop(); // cancels the poller timer
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('empty state', (tester) async {
      final state = _fake({'action_count': 0, 'items': []});
      await tester.pumpWidget(
        ChangeNotifierProvider<NotificationsState>.value(
          value: state,
          child: MaterialApp(theme: AppTheme.light(), home: const NotificationsScreen()),
        ),
      );
      await state.start(25);
      await tester.pump();
      expect(find.text(S.noNotifications), findsOneWidget);
      state.stop(); // cancels the poller timer
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// NotificationsState without the network (the timer is stopped per test).
NotificationsState _fake([Map<String, dynamic>? json]) =>
    NotificationsState(ApiClient(), interval: const Duration(days: 1), fetch: () async => json ?? feedJson());
