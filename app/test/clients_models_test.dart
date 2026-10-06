import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/agent.dart';
import 'package:matrimony_agents/models/agent_change.dart';
import 'package:matrimony_agents/models/customer.dart';
import 'package:matrimony_agents/models/delete_request.dart';
import 'package:matrimony_agents/models/interest.dart';
import 'package:matrimony_agents/models/notifications.dart';
import 'package:matrimony_agents/services/admin_service.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/clients_service.dart';

/// Wire shapes from backend/src/lib/customers.js (interestRow / clientRow /
/// agentChangeRow) and routes/notifications.js.
void main() {
  const targetProfile = {
    'id': 7,
    'full_name': 'Ravi Teja',
    'gender': 'groom',
    'age': 29,
    'community': {'id': 1, 'name': 'Reddy'},
    'subcaste': null,
    'status': 'active',
    'photo_url': '/api/photos/12',
  };
  const customerProfile = {
    'id': 9,
    'full_name': 'Priya',
    'gender': 'bride',
    'age': 25,
    'community': {'id': 1, 'name': 'Reddy'},
    'subcaste': {'id': 3, 'name': 'Motati'},
    'status': 'active',
    'photo_url': null,
  };

  group('Interest', () {
    test("uploader's view: customer_agent present, target_agent absent, can decide", () {
      final it = Interest.fromJson({
        'id': 41,
        'status': 'pending',
        'note': 'Family is keen',
        'created_at': '2026-09-20T10:00:00.000Z',
        'decided_at': null,
        'days_left': null,
        'access_expires_at': null,
        'customer': {'id': 5, 'full_name': 'Priya', 'agent_id': 2},
        'customer_profile': customerProfile,
        'profile': targetProfile,
        'customer_agent': {
          'id': 2,
          'full_name': 'Lakshmi',
          'agency_name': 'Sri Bureau',
          'phone': '9876543210',
        },
        'can_decide': true,
      });
      expect(it.isPending, isTrue);
      expect(it.canDecide, isTrue);
      expect(it.customer.fullName, 'Priya');
      expect(it.customer.phone, isNull, reason: "the uploader never gets the customer's phone");
      expect(it.customerAgent?.fullName, 'Lakshmi');
      expect(it.customerAgent?.phone, '9876543210');
      expect(it.customerAgent?.label, 'Lakshmi · Sri Bureau');
      expect(it.targetAgent, isNull);
      expect(it.otherAgent?.id, 2);
      expect(it.profile?.id, 7);
      expect(it.profile?.subtitle, 'Groom · 29 yrs · Reddy');
      expect(it.profile?.photoAbsoluteUrl, endsWith('/api/photos/12'));
      expect(it.customerProfile?.subcaste, 'Motati');
      expect(it.customerProfile?.photoAbsoluteUrl, isNull);
      expect(it.statusLabel, 'Waiting for a decision');
    });

    test("customer's agent view: no customer_agent, target_agent and phone present", () {
      final it = Interest.fromJson({
        'id': 41,
        'status': 'accepted',
        'note': null,
        'created_at': '2026-09-20T10:00:00.000Z',
        'decided_at': '2026-09-21T10:00:00.000Z',
        'days_left': 14,
        'access_expires_at': '2026-10-05T10:00:00.000Z',
        'customer': {'id': 5, 'full_name': 'Priya', 'phone': '9000000001', 'agent_id': 2},
        'customer_profile': null,
        'profile': targetProfile,
        'target_agent': {'id': 1, 'full_name': 'Ravi', 'agency_name': null, 'phone': '9111111111'},
        'can_decide': false,
      });
      expect(it.isAccepted, isTrue);
      expect(it.canDecide, isFalse);
      expect(it.customer.phone, '9000000001');
      expect(it.customerAgent, isNull);
      expect(it.targetAgent?.fullName, 'Ravi');
      expect(it.targetAgent?.label, 'Ravi', reason: 'no agency → name only');
      expect(it.otherAgent?.id, 1);
      expect(it.customerProfile, isNull);
      expect(it.daysLeft, 14);
      expect(it.accessExpiresAt, isNotNull);
      expect(it.statusLabel, 'Details shared · 14 days left');
    });

    test('lapsed and other statuses read naturally; missing customer does not crash', () {
      Interest at(String status) => Interest.fromJson({'id': 1, 'status': status});
      expect(at('expired').statusLabel, 'Access expired');
      expect(at('declined').statusLabel, 'Declined');
      expect(at('withdrawn').statusLabel, 'Withdrawn by the client');
      expect(at('revoked').statusLabel, 'Access revoked');
      expect(at('accepted').statusLabel, 'Details shared');
      expect(at('pending').customer.id, 0);
      expect(at('pending').profile, isNull);
    });
  });

  group('NotificationFeed', () {
    test('SPEC §9.10 counts feed the Clients badge', () {
      final feed = NotificationFeed.fromJson({
        'badge': 9,
        'items': [
          {
            'type': 'client_pending',
            'id': 5,
            'customer_id': 5,
            'title': 'New client awaiting approval',
            'body': 'Priya registered through your form',
            'at': '2026-09-20T10:00:00.000Z',
          },
        ],
        'counts': {
          'contact_requests_inbox': 1,
          'hold_requests_inbox': 2,
          'pending_agents': 0,
          'pending_password_resets': 0,
          'pending_clients': 3,
          'interests_inbox': 2,
          'agent_change_inbox': 1,
        },
      });
      expect(feed.pendingClients, 3);
      expect(feed.interestsInbox, 2);
      expect(feed.agentChangeInbox, 1);
      expect(feed.clientsBadge, 6);
      expect(feed.requestsBadge, 3);
      expect(feed.items.single.customerId, 5);
      expect(feed.items.single.profileId, isNull);
    });

    test('a v2.0 server without the new counts gives a zero Clients badge', () {
      final feed = NotificationFeed.fromJson({
        'badge': 1,
        'items': [],
        'counts': {'contact_requests_inbox': 1, 'pending_agents': 0},
      });
      expect(feed.clientsBadge, 0);
      expect(NotificationFeed.empty.clientsBadge, 0);
    });

    test('SPEC §9.13: delete requests join the Clients badge; the item opens the client', () {
      final feed = NotificationFeed.fromJson({
        'badge': 7,
        'items': [
          {
            'type': 'profile_delete_requested',
            'id': 12,
            'customer_id': 5,
            'profile_id': 9,
            'title': 'Profile delete request',
            'body': 'Priya asked to delete the profile Priya',
            'at': '2026-09-28T10:00:00.000Z',
          },
          {'type': 'contact_request', 'id': 3, 'profile_id': 7, 'title': 't', 'body': 'b'},
        ],
        'counts': {
          'pending_clients': 1,
          'interests_inbox': 2,
          'agent_change_inbox': 1,
          'delete_requests_inbox': 3,
        },
      });
      expect(feed.deleteRequestsInbox, 3);
      expect(feed.clientsBadge, 7);
      final item = feed.items.first;
      expect(item.id, 12);
      expect(item.customerId, 5);
      expect(item.profileId, 9);
      expect(item.opensClient, isTrue);
      expect(feed.items.last.opensClient, isFalse);
    });
  });

  group('Customer', () {
    test('list row without a profile', () {
      final c = Customer.fromJson({
        'id': 5,
        'full_name': 'Priya',
        'phone': '9000000001',
        'status': 'pending',
        'source': 'form',
        'phone_verified_at': null,
        'approved_at': null,
        'created_at': '2026-09-20T10:00:00.000Z',
        'profile_id': null,
        'has_profile': false,
        'pending_agent_change': null,
        'agent_id': 2,
        'last_login_at': null,
        'profile': null,
        'interests_count': 0,
      });
      expect(c.isPending, isTrue);
      expect(c.hasProfile, isFalse);
      expect(c.profile, isNull);
      expect(c.isFromForm, isTrue);
      expect(c.sourceLabel, 'Form');
      expect(c.statusLabel, 'Waiting for approval');
      expect(c.agent, isNull, reason: 'agents do not get the owning agent');
      expect(c.pendingAgentChange, isNull);
      expect(c.interests, isEmpty);
      expect(c.agentChangeRequests, isEmpty);
      expect(c.phoneVerifiedAt, isNull);
    });

    test('admin row with a profile, a pending agent change and embedded interests', () {
      final c = Customer.fromJson({
        'id': 5,
        'full_name': 'Priya',
        'phone': '9000000001',
        'status': 'active',
        'source': 'app',
        'created_at': '2026-09-20T10:00:00.000Z',
        'approved_at': '2026-09-21T10:00:00.000Z',
        'agent': {'id': 2, 'full_name': 'Lakshmi', 'agency_name': 'Sri Bureau'},
        'profile_id': 9,
        'has_profile': true,
        'pending_agent_change': {
          'id': 3,
          'to_agent': {'id': 4, 'full_name': 'Suresh', 'agency_name': 'Om Bureau', 'city': 'Guntur'},
          'note': null,
          'created_at': '2026-09-22T10:00:00.000Z',
        },
        'agent_id': 2,
        'profile': customerProfile,
        'interests_count': 2,
        'interests': [
          {'id': 41, 'status': 'pending', 'customer': {'id': 5, 'full_name': 'Priya'}, 'profile': targetProfile},
        ],
        'agent_change_requests': [
          {
            'id': 3,
            'status': 'pending',
            'from_agent': {'id': 2, 'full_name': 'Lakshmi'},
            'to_agent': {'id': 4, 'full_name': 'Suresh', 'agency_name': 'Om Bureau'},
            'customer': {'id': 5, 'full_name': 'Priya', 'phone': '9000000001', 'status': 'active'},
            'box': 'outgoing',
            'can_decide': true,
          },
        ],
      });
      expect(c.isActive, isTrue);
      expect(c.agent?.label, 'Lakshmi · Sri Bureau');
      expect(c.hasProfile, isTrue);
      expect(c.profile?.fullName, 'Priya');
      expect(c.interestsCount, 2);
      expect(c.pendingAgentChange?.toAgent.fullName, 'Suresh');
      expect(c.pendingAgentChange?.toAgent.city, 'Guntur');
      expect(c.interests.single.profile?.id, 7);
      expect(c.agentChangeRequests.single.isOutgoing, isTrue);
      expect(c.agentChangeRequests.single.canDecide, isTrue);
      expect(c.approvedAt, isNotNull);
    });

    test('v2.2 row: profiles[] with paid state, oldest first (SPEC §9.12)', () {
      final c = Customer.fromJson({
        'id': 6,
        'full_name': 'Ramana',
        'phone': '9000000002',
        'status': 'pending',
        'source': 'app',
        'agent_id': 2,
        'profile_id': 9,
        'profile': customerProfile,
        'profiles': [
          {
            ...customerProfile,
            'paid': true,
            'paid_at': '2026-09-25T10:00:00.000Z',
            'visibility': 'awaiting_approval',
          },
          {
            'id': 11,
            'full_name': 'Kiran',
            'gender': 'groom',
            'age': 28,
            'community': {'id': 1, 'name': 'Reddy'},
            'subcaste': null,
            'status': 'hidden',
            'photo_url': null,
            'paid': false,
            'paid_at': null,
            'visibility': 'payment_pending',
          },
        ],
        'interests_count': 0,
      });
      expect(c.profiles, hasLength(2));
      expect(c.allProfiles.first.id, 9);
      expect(c.profiles.first.paid, isTrue);
      expect(c.profiles.first.paidAt, isNotNull);
      expect(c.profiles.first.visibility, 'awaiting_approval');
      expect(c.profiles.last.isUnpaid, isTrue);
      expect(c.profiles.last.paidAt, isNull);
      expect(c.profiles.last.visibility, 'payment_pending');
      expect(c.hasUnpaidProfile, isTrue);
      expect(c.allProfilesUnpaid, isFalse);
    });

    test('older server: no profiles[] falls back to profile; unknown paid is not unpaid', () {
      final c = Customer.fromJson({
        'id': 5,
        'full_name': 'Priya',
        'phone': '9000000001',
        'status': 'pending',
        'source': 'app',
        'profile': customerProfile,
      });
      expect(c.profiles, isEmpty);
      expect(c.allProfiles.single.id, 9);
      expect(c.allProfiles.single.paid, isNull);
      expect(c.hasUnpaidProfile, isFalse);
      expect(c.allProfilesUnpaid, isFalse);
      expect(Customer.fromJson({'id': 1, 'full_name': 'X', 'phone': '1', 'profiles': null}).profiles, isEmpty);
    });

    test('all profiles unpaid → approve note applies', () {
      final c = Customer.fromJson({
        'id': 7,
        'full_name': 'Sita',
        'phone': '9000000003',
        'status': 'pending',
        'source': 'app',
        'profiles': [
          {...customerProfile, 'status': 'hidden', 'paid': false, 'paid_at': null, 'visibility': 'payment_pending'},
        ],
      });
      expect(c.allProfilesUnpaid, isTrue);
      expect(c.hasProfile, isTrue);
    });

    test('guest admin row: no agent (null agent_id, agent of nulls)', () {
      final c = Customer.fromJson({
        'id': 8,
        'full_name': 'Guest User',
        'phone': '9000000004',
        'status': 'guest',
        'source': 'app',
        'agent': {'id': null, 'full_name': null, 'agency_name': null},
        'agent_id': null,
        'profile_id': null,
        'profile': null,
        'profiles': [],
        'pending_agent_change': null,
        'interests_count': 0,
      });
      expect(c.isGuest, isTrue);
      expect(c.isPending, isFalse);
      expect(c.statusLabel, 'Guest');
      expect(c.agent, isNull);
      expect(c.agentId, isNull);
      expect(c.hasProfile, isFalse);
      expect(c.allProfiles, isEmpty);
      expect(Customer.fromJson({'id': 9, 'full_name': 'G', 'phone': '2', 'status': 'guest', 'agent': null}).agent,
          isNull);
    });

    test('SPEC §9.13: delete_request_id on profiles and delete_requests[] on detail', () {
      final c = Customer.fromJson({
        'id': 5,
        'full_name': 'Priya',
        'phone': '9000000001',
        'status': 'active',
        'source': 'app',
        'profiles': [
          {...customerProfile, 'paid': true, 'paid_at': '2026-09-25T10:00:00.000Z', 'delete_request_id': 12},
          {...customerProfile, 'id': 10, 'paid': false, 'paid_at': null, 'delete_request_id': null},
        ],
        'delete_requests': [
          {
            'id': 12,
            'status': 'pending',
            'reason': 'Marriage fixed',
            'created_at': '2026-09-28T10:00:00.000Z',
            'decided_at': null,
            'profile_name': 'Priya',
            'profile_id': 9,
            'profile': customerProfile,
            'customer': {'id': 5, 'full_name': 'Priya', 'phone': '9000000001', 'agent_id': 2},
            'can_decide': true,
          },
          {
            'id': 4,
            'status': 'approved',
            'reason': null,
            'created_at': '2026-09-20T10:00:00.000Z',
            'decided_at': '2026-09-21T10:00:00.000Z',
            'profile_name': 'Old profile',
            'profile_id': null,
            'profile': null,
            'customer': {'id': 5, 'full_name': 'Priya', 'phone': '9000000001', 'agent_id': 2},
            'can_decide': false,
          },
        ],
      });
      expect(c.profiles.first.deleteRequestId, 12);
      expect(c.profiles.last.deleteRequestId, isNull);
      expect(c.hasDeleteRequest, isTrue);
      expect(c.deleteRequests, hasLength(2));
      final pending = c.deleteRequests.first;
      expect(pending.isPending, isTrue);
      expect(pending.canDecide, isTrue);
      expect(pending.reason, 'Marriage fixed');
      expect(pending.profile?.id, 9);
      expect(pending.customer.phone, '9000000001');
      final done = c.deleteRequests.last;
      expect(done.profile, isNull, reason: 'the profile is gone after approval');
      expect(done.profileName, 'Old profile');
      expect(done.statusLabel, 'Deleted');
      expect(done.decidedAt, isNotNull);

      final plain = Customer.fromJson({'id': 1, 'full_name': 'X', 'phone': '1', 'profiles': [customerProfile]});
      expect(plain.hasDeleteRequest, isFalse);
      expect(plain.deleteRequests, isEmpty);
    });

    test('delete request list row (GET /clients/delete-requests)', () {
      final r = ProfileDeleteRequest.fromJson({
        'id': 3,
        'status': 'rejected',
        'profile_name': 'Kiran',
        'profile': null,
        'customer': {'id': 6, 'full_name': 'Ramana'},
      });
      expect(r.isPending, isFalse);
      expect(r.canDecide, isFalse);
      expect(r.statusLabel, 'Rejected');
      expect(r.customer.fullName, 'Ramana');
      expect(r.customer.phone, isNull);
    });

    test('admin stats carry guests and paid registrations', () {
      final s = AdminStats.fromJson({'guest_customers': 3, 'paid_registrations': 5, 'active_customers': 1});
      expect(s.guestCustomers, 3);
      expect(s.paidRegistrations, 5);
      expect(AdminStats.fromJson(const {}).guestCustomers, 0);
    });
  });

  group('AgentChangeRequest', () {
    test('incoming request is read-only and labels its agents', () {
      final r = AgentChangeRequest.fromJson({
        'id': 3,
        'status': 'approved',
        'note': 'Moving city',
        'created_at': '2026-09-22T10:00:00.000Z',
        'decided_at': '2026-09-23T10:00:00.000Z',
        'from_agent': {'id': 2, 'full_name': 'Lakshmi', 'agency_name': 'Sri Bureau', 'city': null, 'phone': '9876543210'},
        'to_agent': {'id': 1, 'full_name': 'Ravi', 'agency_name': null, 'city': 'Vijayawada', 'phone': '9111111111'},
        'box': 'incoming',
        'customer': {'id': 5, 'full_name': 'Priya', 'phone': '9000000001', 'status': 'active', 'agent_id': 1},
        'customer_profile': customerProfile,
        'can_decide': false,
      });
      expect(r.isIncoming, isTrue);
      expect(r.isPending, isFalse);
      expect(r.canDecide, isFalse);
      expect(r.fromAgent.labelComma, 'Lakshmi, Sri Bureau');
      expect(r.toAgent.city, 'Vijayawada');
      expect(r.customer.phone, '9000000001');
      expect(r.customerProfile?.id, 9);
      expect(r.statusLabel, 'Approved — moved');
    });

    test('missing agent cards fall back instead of crashing', () {
      final r = AgentChangeRequest.fromJson({'id': 3, 'status': 'cancelled'});
      expect(r.fromAgent.id, 0);
      expect(r.toAgent.fullName, AgentCard.unknown.fullName);
      expect(r.box, isNull);
      expect(r.statusLabel, 'Cancelled by the client');
    });
  });

  group('OTP + account', () {
    test('send result echoes the mock code only in test mode', () {
      final mock = OtpSendResult.fromJson(
          {'sent': true, 'mock': true, 'expires_in': 300, 'retry_after': 30, 'mock_code': '123456'});
      expect(mock.mock, isTrue);
      expect(mock.mockCode, '123456');
      expect(mock.retryAfter, 30);
      expect(mock.expiresIn, 300);

      final real = OtpSendResult.fromJson({'sent': true, 'mock': false, 'expires_in': 300, 'retry_after': 30});
      expect(real.mockCode, isNull);
      expect(OtpSendResult.fromJson(const {}).retryAfter, 30, reason: 'sane default');
    });

    test('Agent carries the directory city', () {
      final a = Agent.fromJson({
        'id': 1,
        'full_name': 'Ravi',
        'phone': '9111111111',
        'role': 'agent',
        'status': 'active',
        'agency_name': null,
        'city': 'Vijayawada',
        'communities': [],
      });
      expect(a.city, 'Vijayawada');
      expect(Agent.fromJson({'id': 1, 'full_name': 'R', 'phone': '1', 'status': 'active'}).city, isNull);
    });

    test('registration link falls back to the url as the WhatsApp text', () {
      final link = RegistrationLink.fromJson({'url': 'https://x/r/abc'});
      expect(link.url, 'https://x/r/abc');
      expect(link.whatsappText, 'https://x/r/abc');
      expect(InterestBox.received.name, 'received');
      expect(TransferBox.incoming.name, 'incoming');
    });
  });
}
