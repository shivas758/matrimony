import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/notifications.dart';
import 'package:matrimony_agents/state/home_nav.dart';
import 'package:matrimony_agents/state/notification_routes.dart';

/// SPEC §9.14 — the Notifications screen's grouping, routing and times.
void main() {
  NotificationItem item(String type, {int? id, int? profileId, int? customerId}) =>
      NotificationItem.fromJson({
        'type': type,
        'id': id,
        'profile_id': profileId,
        'customer_id': customerId,
        'title': 't',
        'body': 'b',
        'at': '2026-09-28T10:00:00.000Z',
      });

  group('grouping', () {
    test('action types for everyone', () {
      for (final t in [
        'contact_request_received',
        'hold_request_received',
        'client_pending',
        'interest_received',
        'agent_change_requested',
        'profile_delete_requested',
      ]) {
        expect(notificationGroup(t, isAdmin: false), NotificationGroup.action, reason: t);
      }
    });

    test('admin-only action types', () {
      for (final t in ['agent_pending', 'password_reset_requested']) {
        expect(notificationGroup(t, isAdmin: true), NotificationGroup.action);
        expect(notificationGroup(t, isAdmin: false), NotificationGroup.update);
      }
    });

    test('decisions and unknown types are updates', () {
      for (final t in [
        'contact_request_decided',
        'hold_request_decided',
        'community_request_decided',
        'interest_decided',
        'agent_change_decided',
        'something_new',
      ]) {
        expect(notificationGroup(t, isAdmin: true), NotificationGroup.update, reason: t);
      }
    });
  });

  group('routing', () {
    NotificationTarget? route(NotificationItem i, {bool admin = false}) =>
        notificationTarget(i, isAdmin: admin);

    test('requests inbox', () {
      const inbox = TabTarget(HomeTab.requests, HomeSubTabs.requestsInbox);
      expect(route(item('contact_request_received', id: 1, profileId: 7)), inbox);
      expect(route(item('hold_request_received', id: 2, profileId: 7)), inbox);
    });

    test('decided requests open the profile', () {
      expect(route(item('contact_request_decided', id: 1, profileId: 7)), const ProfileTarget(7));
      expect(route(item('hold_request_decided', id: 1, profileId: 8)), const ProfileTarget(8));
      expect(route(item('contact_request_decided', id: 1)), isNull, reason: 'no profile id');
    });

    test('community decision opens settings', () {
      expect(route(item('community_request_decided', id: 3)), const SettingsTarget());
    });

    test('admin targets only for admins', () {
      expect(route(item('agent_pending', id: 4), admin: true), const AdminPendingAgentsTarget());
      expect(route(item('password_reset_requested', id: 5), admin: true),
          const AdminPasswordResetsTarget());
      expect(route(item('agent_pending', id: 4)), isNull);
      expect(route(item('password_reset_requested', id: 5)), isNull);
    });

    test('client items open the client', () {
      for (final t in ['client_pending', 'interest_decided', 'agent_change_decided', 'profile_delete_requested']) {
        expect(route(item(t, id: 1, customerId: 5)), const ClientTarget(5), reason: t);
        expect(route(item(t, id: 1)), isNull, reason: '$t without customer_id');
      }
    });

    test('interests and transfers open the Clients sub-tabs', () {
      expect(route(item('interest_received', id: 1, customerId: 5)),
          const TabTarget(HomeTab.clients, HomeSubTabs.clientsInterests));
      expect(route(item('agent_change_requested', id: 1, customerId: 5)),
          const TabTarget(HomeTab.clients, HomeSubTabs.clientsTransfers));
    });

    test('unknown types are tolerated but not tappable', () {
      final unknown = NotificationItem.fromJson({'type': 'brand_new_type', 'title': 'Hi', 'body': 'x'});
      expect(unknown.type, 'brand_new_type');
      expect(unknown.at, isNull);
      expect(route(unknown, admin: true), isNull);
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 9, 28, 15, 0);
    test('recent', () {
      expect(relativeTime(null, now), '');
      expect(relativeTime(now.subtract(const Duration(seconds: 20)), now), 'Just now');
      expect(relativeTime(now.add(const Duration(minutes: 2)), now), 'Just now', reason: 'clock skew');
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
      expect(relativeTime(now.subtract(const Duration(hours: 1)), now), '1 hour ago');
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now), '3 hours ago');
    });

    test('days and dates', () {
      expect(relativeTime(DateTime(2026, 9, 27, 23, 0), now), 'Yesterday');
      expect(relativeTime(DateTime(2026, 9, 27, 9, 0), now), 'Yesterday');
      expect(relativeTime(DateTime(2026, 9, 24, 9, 0), now), '4 days ago');
      expect(relativeTime(DateTime(2026, 9, 12, 9, 0), now), '12 Sep 2026');
    });
  });

  test('HomeNav hands a sub-tab to its tab once', () {
    final nav = HomeNav();
    var calls = 0;
    nav.addListener(() => calls++);
    nav.go(HomeTab.clients, subTab: HomeSubTabs.clientsInterests);
    expect(nav.tab, HomeTab.clients);
    expect(calls, 1);
    expect(nav.takeSubTab(HomeTab.requests), isNull);
    expect(nav.takeSubTab(HomeTab.clients), HomeSubTabs.clientsInterests);
    expect(nav.takeSubTab(HomeTab.clients), isNull);
    nav.select(HomeTab.clients);
    expect(calls, 1, reason: 'same tab: no rebuild');
    nav.dispose();
  });
}
