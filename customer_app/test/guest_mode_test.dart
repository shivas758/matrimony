import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/models/payment.dart';
import 'package:gandharva/models/profile.dart';
import 'package:gandharva/services/payment_service.dart';
import 'package:gandharva/state/browse_filters.dart';
import 'package:gandharva/ui/strings.dart';

/// Shapes exactly as the v2.2 backend sends them (SPEC §9.12) — captured
/// from the dev API: loadCustomerMe(), guestRow(), paymentPublic(),
/// interestRow({customer}).
Map<String, dynamic> guestMeJson() => {
      'id': 24,
      'full_name': 'Test Guest',
      'phone': '7990591543',
      'status': 'guest',
      'source': 'app',
      'phone_verified_at': '2026-09-28T10:32:23.716Z',
      'approved_at': null,
      'created_at': '2026-09-28T10:32:23.716Z',
      'agent': null,
      'profile_id': null,
      'has_profile': false,
      'pending_agent_change': null,
      'access': 'guest',
      'profiles': [],
      'max_profiles': 1,
      'profile_fee_inr': 150,
      'payment_provider': 'mock',
      'unlock': {'agent_linked': false, 'profile_registered': false, 'paid': false, 'approved': false},
    };

Map<String, dynamic> ownSummary(int id, String name, String gender, String visibility, {bool paid = true}) => {
      'id': id,
      'full_name': name,
      'gender': gender,
      'age': 27,
      'community': {'id': 1, 'name': 'Kamma'},
      'subcaste': null,
      'status': visibility == 'live' ? 'active' : 'hidden',
      'photo_url': '/api/customer/photos/$id',
      'paid': paid,
      'paid_at': paid ? '2026-09-28T10:32:35.426Z' : null,
      'visibility': visibility,
    };

Map<String, dynamic> activeMeJson() => {
      ...guestMeJson(),
      'status': 'active',
      'approved_at': '2026-09-28T11:00:00.000Z',
      'agent': {
        'id': 2,
        'full_name': 'Agent A',
        'agency_name': 'A Bureau',
        'city': 'Vijayawada',
        'phone': '9094563283',
        'communities': [
          {'id': 1, 'name': 'Kamma'},
        ],
      },
      'profile_id': 77,
      'has_profile': true,
      'access': 'full',
      'profiles': [
        ownSummary(77, 'Priya', 'bride', 'live'),
        ownSummary(78, 'Kavya', 'bride', 'live'),
        ownSummary(79, 'Ravi', 'groom', 'live'),
        ownSummary(80, 'Sita', 'bride', 'payment_pending', paid: false),
      ],
      'unlock': {'agent_linked': true, 'profile_registered': true, 'paid': true, 'approved': true},
    };

void main() {
  group('Customer (v2.2 me)', () {
    test('a fresh guest: no agent, guest access, empty checklist', () {
      final c = Customer.fromJson(guestMeJson());
      expect(c.status, CustomerStatus.guest);
      expect(c.isGuest, isTrue);
      expect(c.isPending, isFalse);
      expect(c.agent, isNull);
      expect(c.hasFullAccess, isFalse);
      expect(c.access, 'guest');
      expect(c.profiles, isEmpty);
      expect(c.hasProfile, isFalse);
      expect(c.maxProfiles, 1);
      expect(c.profileFeeInr, 150);
      expect(c.paymentProvider, 'mock');
      expect(c.canLinkAgent, isTrue);
      expect(c.canAddProfile, isTrue);
      expect(c.firstUnpaid, isNull);
      final u = c.unlock;
      expect([u.agentLinked, u.profileRegistered, u.paid, u.approved], [false, false, false, false]);
      expect(u.allDone, isFalse);
    });

    test('an active customer with several profiles', () {
      final c = Customer.fromJson(activeMeJson());
      expect(c.isActive, isTrue);
      expect(c.hasFullAccess, isTrue);
      expect(c.canLinkAgent, isFalse, reason: 'active customers use Change agent');
      expect(c.agent!.fullName, 'Agent A');
      expect(c.profiles, hasLength(4));
      expect(c.unlock.allDone, isTrue);

      final first = c.profiles.first;
      expect(first.fullName, 'Priya');
      expect(first.paid, isTrue);
      expect(first.paidAt, isNotNull);
      expect(first.visibility, ProfileVisibility.live);
      expect(first.communityLine, 'Kamma');

      expect(c.firstUnpaid!.id, 80);
      expect(c.firstUnpaid!.visibility, ProfileVisibility.paymentPending);

      // Interest in a groom: my two live brides; in a bride: my one live groom.
      expect(c.liveProfilesFor('groom').map((p) => p.id), [77, 78]);
      expect(c.liveProfilesFor('bride').map((p) => p.id), [79]);
    });

    test('pending and rejected customers may still link another agent; the limit is respected', () {
      expect(Customer.fromJson({...guestMeJson(), 'status': 'pending'}).canLinkAgent, isTrue);
      expect(Customer.fromJson({...guestMeJson(), 'status': 'rejected'}).canLinkAgent, isTrue);
      expect(Customer.fromJson({...guestMeJson(), 'status': 'suspended'}).canLinkAgent, isFalse);
      final full = Customer.fromJson({...activeMeJson(), 'max_profiles': 4});
      expect(full.canAddProfile, isFalse);
      final one = Customer.fromJson({...activeMeJson(), 'max_profiles': 1, 'profiles': [(activeMeJson()['profiles'] as List).first]});
      expect(one.canAddProfile, isFalse, reason: 'one profile per customer (SPEC §9.17)');
    });

    test('a v1.0-style me (no v2.2 keys) still parses', () {
      final j = guestMeJson()
        ..remove('access')
        ..remove('profiles')
        ..remove('max_profiles')
        ..remove('profile_fee_inr')
        ..remove('payment_provider')
        ..remove('unlock')
        ..['status'] = 'pending';
      final c = Customer.fromJson(j);
      expect(c.access, 'guest');
      expect(c.profiles, isEmpty);
      expect(c.maxProfiles, 1, reason: 'one profile per customer (SPEC §9.17)');
      expect(c.profileFeeInr, isNull, reason: 'never invent a fee');
      expect(c.unlock.agentLinked, isFalse);
    });
  });

  group('Guest browse rows', () {
    Map<String, dynamic> guestRow() => {
          'id': 74,
          'gender': 'groom',
          'age': 30,
          'community': {'id': 1, 'name': 'Kamma'},
          'subcaste': {'id': 9, 'name': 'Chowdary'},
          'profession': null,
          'occupation_type': {'id': 2, 'name': 'Government job'},
          'income_text': '8 LPA',
          'primary_photo_url': '/api/customer/photos/31',
          'locked': true,
        };

    test('a row without a name parses without crashing', () {
      final p = Profile.fromJson(guestRow());
      expect(p.id, 74);
      expect(p.fullName, '');
      expect(p.locked, isTrue);
      expect(p.age, 30);
      expect(p.communityLine, 'Kamma · Chowdary');
      expect(p.jobLabel, 'Government job', reason: 'occupation type when no profession');
      expect(p.incomeText, '8 LPA');
      expect(p.primaryPhotoUrl, endsWith('/api/customer/photos/31'));
      expect(p.hasProtectedFields, isFalse);
      expect(p.photos, isEmpty);
    });

    test('profession wins over occupation type; a bare row (no gender either) is tolerated', () {
      final p = Profile.fromJson({
        ...guestRow(),
        'profession': {'id': 2, 'name': 'Software Engineer'},
      });
      expect(p.jobLabel, 'Software Engineer');
      final bare = Profile.fromJson({'id': 5, 'locked': true});
      expect(bare.fullName, '');
      expect(bare.gender, '');
      expect(bare.jobLabel, isNull);
    });

    test('the page says guest access and has no default gender', () {
      final page = ProfilePage.fromJson({
        'total': 59,
        'page': 1,
        'limit': 20,
        'gender': null,
        'access': 'guest',
        'profiles': [guestRow()],
      });
      expect(page.isGuest, isTrue);
      expect(page.gender, isNull);
      expect(page.profiles.single.locked, isTrue);

      final full = ProfilePage.fromJson({'total': 0, 'page': 1, 'gender': 'groom', 'access': 'full', 'profiles': []});
      expect(full.isGuest, isFalse);
      expect(full.gender, 'groom');
    });
  });

  group('Own profile view', () {
    test('carries paid / visibility / fee', () {
      final p = Profile.fromJson({
        'id': 77,
        'full_name': 'Kid One',
        'gender': 'bride',
        'status': 'hidden',
        'is_mine': true,
        'paid': false,
        'paid_at': null,
        'visibility': 'payment_pending',
        'profile_fee_inr': 150,
      });
      expect(p.paid, isFalse);
      expect(p.visibility, ProfileVisibility.paymentPending);
      expect(p.profileFeeInr, 150);
      expect(ProfileVisibility.fromApi('awaiting_approval'), ProfileVisibility.awaitingApproval);
      expect(ProfileVisibility.fromApi('nonsense'), isNull);
    });
  });

  group('Payment', () {
    Map<String, dynamic> payment(String status) => {
          'id': 16,
          'profile_id': 77,
          'status': status,
          'amount_paise': 15000,
          'amount_inr': 150,
          'currency': 'INR',
          'provider': 'mock',
          'order_id': 'mock_4aa4fdb1edae614a',
          'key_id': null,
          'created_at': '2026-09-28T10:32:35.273Z',
          'paid_at': status == 'paid' ? '2026-09-28T10:32:35.426Z' : null,
        };

    test('an order parses', () {
      final p = Payment.fromJson(payment('created'));
      expect(p.id, 16);
      expect(p.profileId, 77);
      expect(p.amountInr, 150);
      expect(p.amountPaise, 15000);
      expect(p.isMock, isTrue);
      expect(p.isPaid, isFalse);
      expect(p.isFailed, isFalse);
      expect(p.keyId, isNull);
      expect(p.paidAt, isNull);
    });

    test('amount falls back to paise when amount_inr is missing', () {
      final p = Payment.fromJson(payment('created')..remove('amount_inr'));
      expect(p.amountInr, 150);
    });

    test('confirm result: paid, with the profile state and the refreshed customer', () {
      final r = PaymentResult.fromJson({
        'payment': payment('paid'),
        'profile': {
          'id': 77,
          'full_name': 'Kid One',
          'gender': 'bride',
          'status': 'hidden',
          'paid': true,
          'paid_at': '2026-09-28T10:32:35.426Z',
          'visibility': 'awaiting_approval',
        },
        'customer': {...guestMeJson(), 'status': 'pending'},
      });
      expect(r.payment.isPaid, isTrue);
      expect(r.payment.paidAt, isNotNull);
      expect(r.profile!.visibility, ProfileVisibility.awaitingApproval);
      expect(r.customer!.isPending, isTrue);
    });

    test('a failed attempt', () {
      final r = PaymentResult.fromJson({'payment': payment('failed'), 'profile': null, 'customer': null});
      expect(r.payment.isFailed, isTrue);
      expect(r.profile, isNull);
      expect(r.customer, isNull);
    });

    test('only the mock provider can be completed in this app version', () {
      expect(PaymentService.supportsInApp('mock'), isTrue);
      expect(PaymentService.supportsInApp('razorpay'), isFalse);
    });

    test('fee labels come from the API amount', () {
      expect(S.feeLabel(150), '₹150');
      expect(S.feeLabel(150.0), '₹150');
      expect(S.feeLabel(199.5), '₹199.50');
      expect(S.payFee(150), 'Pay ₹150');
      expect(S.feeLabel(null), 'the fee');
    });
  });

  group('Interest with from_profile', () {
    test('says which of my profiles is interested', () {
      final i = Interest.fromJson({
        'id': 3,
        'status': 'pending',
        'note': null,
        'created_at': '2026-09-28T12:00:00.000Z',
        'decided_at': null,
        'days_left': null,
        'access_expires_at': null,
        'profile': {'id': 41, 'full_name': 'Lakshmi', 'gender': 'bride', 'age': 28, 'photo_url': null},
        'from_profile': {
          'id': 79,
          'full_name': 'Ravi',
          'gender': 'groom',
          'age': 30,
          'community': {'id': 1, 'name': 'Kamma'},
          'subcaste': null,
          'status': 'active',
          'photo_url': '/api/customer/photos/5',
        },
      });
      expect(i.fromProfile!.fullName, 'Ravi');
      expect(i.fromProfile!.gender, 'groom');
      expect(S.forProfile(i.fromProfile!.fullName), 'for Ravi');
      expect(i.profile!.fullName, 'Lakshmi');
    });

    test('older rows have none', () {
      final i = Interest.fromJson({'id': 1, 'status': 'accepted', 'days_left': 4, 'from_profile': null});
      expect(i.fromProfile, isNull);
    });
  });

  group('BrowseFilters gender + guest', () {
    test('gender is sent when set and survives Clear all', () {
      const f = BrowseFilters(gender: 'bride', city: 'Guntur', query: 'lak', sort: 'name');
      expect(f.toQuery()['gender'], 'bride');
      expect(f.clearedFilters().gender, 'bride');
      expect(f.copyWith(clearGender: true).toQuery().containsKey('gender'), isFalse);
      expect(BrowseFilters.empty.toQuery().containsKey('gender'), isFalse);
    });

    test('guests send every filter incl. place, but never name search or sort-by-name (SPEC §9.13)', () {
      const f = BrowseFilters(gender: 'groom', city: 'Guntur', query: 'lak', sort: 'name', ageMin: 25);
      final q = f.forGuest().toQuery();
      expect(q.containsKey('q'), isFalse);
      expect(q['city'], 'Guntur');
      expect(q['sort'], 'newest');
      expect(q['gender'], 'groom');
      expect(q['age_min'], 25);
    });
  });

  group('Delete requests (SPEC §9.13)', () {
    test('own-profile view carries the pending one', () {
      final p = Profile.fromJson({
        'id': 77,
        'full_name': 'Kid One',
        'gender': 'bride',
        'status': 'active',
        'paid': true,
        'paid_at': '2026-09-28T10:32:35.426Z',
        'visibility': 'live',
        'delete_request': {
          'id': 4,
          'status': 'pending',
          'reason': 'Marriage fixed',
          'created_at': '2026-09-28T12:00:00.000Z',
        },
      });
      final d = p.deleteRequest!;
      expect(d.id, 4);
      expect(d.isPending, isTrue);
      expect(d.reason, 'Marriage fixed');
      expect(d.createdAt, isNotNull);
      expect(p.paid, isTrue);
    });

    test('none pending → null; the create / cancel row parses fully', () {
      expect(Profile.fromJson({'id': 1, 'delete_request': null}).deleteRequest, isNull);
      expect(Profile.fromJson({'id': 1}).deleteRequest, isNull);
      final d = DeleteRequest.fromJson({
        'id': 5,
        'status': 'cancelled',
        'reason': null,
        'created_at': '2026-09-28T12:00:00.000Z',
        'decided_at': '2026-09-28T12:05:00.000Z',
        'profile_name': 'Kid One',
        'profile_id': 77,
      });
      expect(d.isPending, isFalse);
      expect(d.decidedAt, isNotNull);
      expect(d.profileName, 'Kid One');
      expect(d.profileId, 77);
    });

    test('summaries pick up delete_request_id when the server sends it', () {
      final s = ProfileSummary.fromJson({...ownSummary(77, 'Priya', 'bride', 'live'), 'delete_request_id': 9});
      expect(s.deleteRequestId, 9);
      expect(ProfileSummary.fromJson(ownSummary(78, 'Kavya', 'bride', 'live')).deleteRequestId, isNull);
    });

    test('a cash-paid profile reads as paid (no Pay button)', () {
      final s = ProfileSummary.fromJson(ownSummary(80, 'Sita', 'bride', 'awaiting_approval'));
      expect(s.paid, isTrue);
      expect(s.visibility, ProfileVisibility.awaitingApproval);
    });
  });
}
