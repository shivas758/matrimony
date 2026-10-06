import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/agent_change.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/models/master_data.dart';
import 'package:gandharva/models/profile.dart';
import 'package:gandharva/services/customer_auth_service.dart';
import 'package:gandharva/state/browse_filters.dart';
import 'package:gandharva/ui/strings.dart';

/// The PUBLIC ("appearance profile") payload as `profilePublic()` in
/// backend/src/lib/profiles.js emits it — no protected keys at all.
Map<String, dynamic> publicProfileJson() => {
      'id': 41,
      'full_name': 'Lakshmi Prasanna',
      'gender': 'bride',
      'dob': '1998-04-12',
      'age': 28,
      'height_cm': 160,
      'weight_kg': 52,
      'complexion': {'id': 2, 'name': 'Fair'},
      'religion': {'id': 1, 'name': 'Hindu'},
      'community': {'id': 3, 'name': 'Kamma'},
      'subcaste': {'id': 9, 'name': 'Chowdary'},
      'gothram': 'Kashyapa',
      'mother_tongue': {'id': 1, 'name': 'Telugu'},
      'known_languages': [
        {'id': 1, 'name': 'Telugu'},
        {'id': 3, 'name': 'English'},
      ],
      'food_habit': {'id': 1, 'name': 'Vegetarian'},
      'nationality': {'id': 1, 'name': 'India'},
      'education': {'id': 4, 'name': 'B.Tech / B.E.'},
      'education_details': 'CSE, JNTU 2019',
      'education_levels': [
        {'level': '10th', 'details': 'Narayana, 9.8 GPA', 'country': {'id': 1, 'name': 'India'}},
        {'level': 'graduation', 'details': 'B.Tech CSE', 'country': null},
        {'level': 'bogus_level', 'details': 'ignored', 'country': null},
      ],
      'profession': {'id': 2, 'name': 'Software Engineer'},
      'profession_details': 'Infosys, Hyderabad',
      'occupation_type': {'id': 1, 'name': 'Private job'},
      'work_country': {'id': 1, 'name': 'India'},
      'marital_status': {'id': 1, 'name': 'Unmarried'},
      'zodiac': {'id': 1, 'english_name': 'Aries', 'indian_name': 'Mesha'},
      'nakshatram': {'id': 3, 'name': 'Krittika'},
      'birth_time': '22:40',
      'income_text': '12 LPA',
      'other_income': 'Rental',
      'is_nri': false,
      'nri_country': null,
      'about': 'Soft-spoken, family oriented.',
      'status': 'active',
      'is_customer_profile': true,
      'created_at': '2026-09-01T10:00:00.000Z',
      'updated_at': '2026-09-02T10:00:00.000Z',
      'is_mine': false,
      'photos': [
        {'id': 7, 'url': '/api/customer/photos/7', 'is_primary': true, 'sort_order': 0},
        {'id': 8, 'url': '/api/customer/photos/8', 'is_primary': false, 'sort_order': 1},
      ],
      'primary_photo_url': '/api/customer/photos/7',
    };

/// What `protectedFields()` adds once access is granted.
Map<String, dynamic> protectedJson() => {
      'city': 'Nalgonda',
      'state': 'Telangana',
      'birth_place': 'Guntur',
      'birth_state': 'Andhra Pradesh',
      'birth_country': {'id': 1, 'name': 'India'},
      'work_place': 'Hyderabad',
      'nri_place': null,
      'father_name': 'Venkat Rao',
      'father_occupation': 'Farmer',
      'father_phone': '9000000001',
      'mother_name': 'Padma',
      'mother_occupation': 'Home maker',
      'mother_phone': '9000000002',
      'contact_name': 'Venkat Rao',
      'contact_phone': '9000000001',
      'has_siblings': true,
      'siblings_count': 2,
      'siblings_details': 'One married sister in the US',
      'elder_sisters': 1,
      'younger_sisters': 0,
      'elder_brothers': 0,
      'younger_brothers': 1,
      'family_details': 'Agricultural family',
      'property_share': 'Equal share',
      'property_details': '5 acres near Guntur',
    };

Map<String, dynamic> customerJson() => {
      'id': 12,
      'full_name': 'Ravi Kumar',
      'phone': '9876543210',
      'status': 'pending',
      'source': 'app',
      'phone_verified_at': '2026-09-20T05:00:00.000Z',
      'approved_at': null,
      'created_at': '2026-09-20T05:00:00.000Z',
      'agent': {
        'id': 3,
        'full_name': 'Suresh Babu',
        'agency_name': 'Sri Lakshmi Marriage Bureau',
        'city': 'Guntur',
        'phone': '9000000003',
        'communities': [
          {'id': 3, 'name': 'Kamma'},
          {'id': 4, 'name': 'Reddy'},
        ],
      },
      'profile_id': null,
      'has_profile': false,
      'pending_agent_change': null,
    };

void main() {
  group('Customer', () {
    test('parses a pending customer with their agent', () {
      final c = Customer.fromJson(customerJson());
      expect(c.id, 12);
      expect(c.fullName, 'Ravi Kumar');
      expect(c.phone, '9876543210');
      expect(c.status, CustomerStatus.pending);
      expect(c.isPending, isTrue);
      expect(c.isActive, isFalse);
      expect(c.source, 'app');
      expect(c.phoneVerifiedAt, isNotNull);
      expect(c.approvedAt, isNull);
      expect(c.hasProfile, isFalse);
      expect(c.profileId, isNull);
      expect(c.pendingAgentChange, isNull);

      final a = c.agent!;
      expect(a.id, 3);
      expect(a.fullName, 'Suresh Babu');
      expect(a.agencyName, 'Sri Lakshmi Marriage Bureau');
      expect(a.city, 'Guntur');
      expect(a.phone, '9000000003');
      expect(a.communities.map((m) => m.name), ['Kamma', 'Reddy']);
      expect(a.agencyLine, 'Sri Lakshmi Marriage Bureau · Guntur');
      expect(a.communitiesLabel, 'Kamma, Reddy');
    });

    test('active customer with a profile and a pending agent change', () {
      final j = customerJson()
        ..['status'] = 'active'
        ..['approved_at'] = '2026-09-21T05:00:00.000Z'
        ..['profile_id'] = 41
        ..['has_profile'] = true
        ..['pending_agent_change'] = {
          'id': 5,
          'to_agent': {'id': 8, 'full_name': 'Anitha', 'agency_name': 'Anitha Matrimony', 'city': 'Vijayawada'},
          'created_at': '2026-09-25T05:00:00.000Z',
        };
      final c = Customer.fromJson(j);
      expect(c.isActive, isTrue);
      expect(c.hasProfile, isTrue);
      expect(c.profileId, 41);
      final change = c.pendingAgentChange!;
      expect(change.id, 5);
      expect(change.toAgent.fullName, 'Anitha');
      expect(change.toAgent.phone, isNull, reason: 'to_agent carries no phone');
      expect(change.toAgent.communities, isEmpty);
      expect(change.createdAt, isNotNull);
    });

    test('has_profile is inferred from profile_id when the flag is absent', () {
      final j = customerJson()
        ..remove('has_profile')
        ..['profile_id'] = 41;
      expect(Customer.fromJson(j).hasProfile, isTrue);
    });

    test('unknown status falls back to pending; rejected and suspended parse', () {
      expect(Customer.fromJson(customerJson()..['status'] = 'weird').status, CustomerStatus.pending);
      expect(Customer.fromJson(customerJson()..['status'] = 'rejected').isRejected, isTrue);
      expect(Customer.fromJson(customerJson()..['status'] = 'suspended').isSuspended, isTrue);
    });

    test('directory rows flag the current agent', () {
      final a = AgentCard.fromJson({'id': 3, 'full_name': 'Suresh Babu', 'is_current': true});
      expect(a.isCurrent, isTrue);
      expect(a.agencyLine, isNull);
    });
  });

  group('Profile without protected keys', () {
    test('parses every public field and reports no shared details', () {
      final p = Profile.fromJson(publicProfileJson());
      expect(p.id, 41);
      expect(p.fullName, 'Lakshmi Prasanna');
      expect(p.isBride, isTrue);
      expect(p.age, 28);
      expect(p.dobLabel, '12 Apr 1998');
      expect(p.ageDobLine, '28 yrs (12 Apr 1998)');
      expect(p.heightLabel, '5\' 3" (160 cm)');
      expect(p.heightShort, '5\'3"');
      expect(p.weightLabel, '52 kg');
      expect(p.complexion?.name, 'Fair');
      expect(p.religion?.name, 'Hindu');
      expect(p.communityLine, 'Kamma · Chowdary');
      expect(p.gothram, 'Kashyapa');
      expect(p.motherTongue?.name, 'Telugu');
      expect(p.knownLanguagesLabel, 'Telugu, English');
      expect(p.foodHabit?.name, 'Vegetarian');
      expect(p.nationality?.name, 'India');
      expect(p.educationLine, 'B.Tech / B.E. — CSE, JNTU 2019');
      expect(p.professionLine, 'Software Engineer — Infosys, Hyderabad');
      expect(p.occupationType?.name, 'Private job');
      expect(p.occupationLine, 'Private job — Infosys, Hyderabad');
      expect(p.workCountry?.name, 'India');
      expect(p.placeLine, 'India', reason: 'public location is the work country');
      expect(p.maritalStatus?.name, 'Unmarried');
      expect(p.starRasi, 'Krittika · Mesha / Aries');
      expect(p.birthTime, '22:40');
      expect(p.birthTimeLabel, '10:40 PM');
      expect(p.incomeText, '12 LPA');
      expect(p.otherIncome, 'Rental');
      expect(p.isNri, isFalse);
      expect(p.nriLabel, isNull);
      expect(p.about, 'Soft-spoken, family oriented.');
      expect(p.status, ProfileStatus.active);
      expect(p.isCustomerProfile, isTrue);
      expect(p.isMine, isFalse);
      expect(p.photos.length, 2);
      expect(p.photos.first.isPrimary, isTrue);
      expect(p.primaryPhotoUrl, endsWith('/api/customer/photos/7'));
      expect(p.primaryPhotoUrl, startsWith('http'));

      // Nothing on request leaked in.
      expect(p.hasProtectedFields, isFalse);
      expect(p.detailsShared, isFalse);
      expect(p.hasPersonalDetails, isFalse);
      expect(p.city, isNull);
      expect(p.nativePlace, isNull);
      expect(p.birthPlaceLine, isNull);
      expect(p.workPlace, isNull);
      expect(p.fatherName, isNull);
      expect(p.contactPhone, isNull);
      expect(p.hasSiblings, isNull);
      expect(p.siblingsLabel, isNull);
      expect(p.siblingsBreakdown, isNull);
      expect(p.familyDetails, isNull);
      expect(p.propertyShare, isNull);
      expect(p.interest, isNull);
      expect(p.interestStatus, isNull);
      expect(p.isInterested, isFalse);
      expect(p.accessDaysLeft, isNull);
    });

    test('education levels keep the server order, drop unknown levels and label themselves', () {
      final p = Profile.fromJson(publicProfileJson());
      expect(p.educationLevels.length, 2, reason: 'bogus_level is dropped');
      expect(p.educationLevels[0].level, EducationLevel.tenth);
      expect(p.educationLevels[0].level.label, '10th');
      expect(p.educationLevels[0].country?.name, 'India');
      expect(p.educationLevels[0].line, '10th — Narayana, 9.8 GPA (India)');
      expect(p.educationLevels[1].level, EducationLevel.graduation);
      expect(p.educationLevels[1].country, isNull);
      expect(p.educationLevels[1].line, 'Graduation — B.Tech CSE');
      expect(p.educationLevels[1].toJson(), {'level': 'graduation', 'details': 'B.Tech CSE'});
      expect(EducationLevel.below10th.label, 'Below 10th');
      expect(EducationLevel.intermediate.label, 'Intermediate / 12th');
      expect(EducationLevel.postGraduation.apiValue, 'post_graduation');
      expect(EducationLevel.fromApi('nope'), isNull);
    });

    test('NRI profile shows the country as its public place', () {
      final j = publicProfileJson()
        ..['is_nri'] = true
        ..['nri_country'] = {'id': 5, 'name': 'United States'};
      final p = Profile.fromJson(j);
      expect(p.nriLabel, 'United States');
      expect(p.placeLine, 'United States');
    });

    test('list rows carry interest_status / is_interested', () {
      final j = publicProfileJson()
        ..['interest_status'] = 'pending'
        ..['is_interested'] = true;
      final p = Profile.fromJson(j);
      expect(p.interestStatus, 'pending');
      expect(p.isInterested, isTrue);
      expect(p.interest, isNull);
    });

    test('a page of profiles parses', () {
      final page = ProfilePage.fromJson({
        'profiles': [publicProfileJson(), publicProfileJson()..['id'] = 42],
        'total': 2,
        'page': 1,
      });
      expect(page.profiles.map((p) => p.id), [41, 42]);
      expect(page.total, 2);
      expect(page.page, 1);
    });
  });

  group('Profile with protected keys', () {
    test('parses the on-request block and reports shared details', () {
      final j = publicProfileJson()
        ..addAll(protectedJson())
        ..['interest'] = {
          'id': 77,
          'status': 'accepted',
          'note': null,
          'created_at': '2026-09-22T05:00:00.000Z',
          'decided_at': '2026-09-23T05:00:00.000Z',
          'access_expires_at': '2026-10-08T05:00:00.000Z',
          'days_left': 11,
        };
      final p = Profile.fromJson(j);
      expect(p.hasProtectedFields, isTrue);
      expect(p.detailsShared, isTrue);
      expect(p.hasPersonalDetails, isTrue);
      expect(p.nativePlace, 'Nalgonda, Telangana');
      expect(p.birthPlaceLine, 'Guntur, Andhra Pradesh, India');
      expect(p.birthCountry?.name, 'India');
      expect(p.workPlace, 'Hyderabad');
      expect(p.nriPlace, isNull);
      expect(p.fatherName, 'Venkat Rao');
      expect(p.fatherOccupation, 'Farmer');
      expect(p.fatherPhone, '9000000001');
      expect(p.motherName, 'Padma');
      expect(p.motherOccupation, 'Home maker');
      expect(p.motherPhone, '9000000002');
      expect(p.contactName, 'Venkat Rao');
      expect(p.contactPhone, '9000000001');
      expect(p.hasSiblings, isTrue);
      expect(p.siblingsCount, 2);
      expect(p.siblingsLabel, '2');
      expect(p.siblingsDetails, 'One married sister in the US');
      expect(p.elderSisters, 1);
      expect(p.youngerBrothers, 1);
      expect(p.siblingsBreakdown, '1 elder sister, 1 younger brother');
      expect(p.familyDetails, 'Agricultural family');
      expect(p.propertyShare, 'Equal share');
      expect(p.propertyDetails, '5 acres near Guntur');

      final i = p.interest!;
      expect(i.id, 77);
      expect(i.isAccepted, isTrue);
      expect(i.isLive, isTrue);
      expect(i.daysLeft, 11);
      expect(p.interestStatus, 'accepted');
      expect(p.isInterested, isTrue);
      expect(p.accessDaysLeft, 11);
    });

    test('own profile is always shared, even with nothing recorded', () {
      final j = publicProfileJson()
        ..['is_mine'] = true
        ..addAll({for (final k in Profile.protectedKeys) k: null});
      final p = Profile.fromJson(j);
      expect(p.isMine, isTrue);
      expect(p.detailsShared, isTrue);
      expect(p.hasPersonalDetails, isFalse);
      expect(p.siblingsLabel, isNull);
    });

    test('no siblings reads as "None"', () {
      final j = publicProfileJson()
        ..addAll(protectedJson())
        ..['has_siblings'] = false
        ..['siblings_count'] = 0;
      final p = Profile.fromJson(j);
      expect(p.siblingsLabel, 'None');
      expect(p.siblingsBreakdown, isNull);
    });

    test('protectedKeys matches PROTECTED_FIELDS on the server', () {
      expect(Profile.protectedKeys.length, 25);
      expect(Profile.protectedKeys.toSet(), protectedJson().keys.toSet());
    });
  });

  group('Interest', () {
    test('pending interest with an embedded profile summary (GET /customer/interests)', () {
      final i = Interest.fromJson({
        'id': 5,
        'status': 'pending',
        'note': 'Please check',
        'created_at': '2026-09-22T05:00:00.000Z',
        'decided_at': null,
        'days_left': null,
        'profile': {
          'id': 41,
          'full_name': 'Lakshmi Prasanna',
          'gender': 'bride',
          'age': 28,
          'community': {'id': 3, 'name': 'Kamma'},
          'subcaste': {'id': 9, 'name': 'Chowdary'},
          'status': 'active',
          'photo_url': '/api/customer/photos/7',
        },
      });
      expect(i.id, 5);
      expect(i.isPending, isTrue);
      expect(i.isLive, isFalse);
      expect(i.canReExpress, isFalse);
      expect(i.note, 'Please check');
      expect(i.createdAt, isNotNull);
      expect(i.decidedAt, isNull);
      expect(i.accessExpiresAt, isNull);
      expect(i.daysLeft, isNull);
      final s = i.profile!;
      expect(s.id, 41);
      expect(s.fullName, 'Lakshmi Prasanna');
      expect(s.age, 28);
      expect(s.communityLine, 'Kamma · Chowdary');
      expect(s.absolutePhotoUrl, endsWith('/api/customer/photos/7'));
    });

    test('declined / withdrawn / revoked / expired can be expressed again; accepted cannot', () {
      Interest at(String status, {int? daysLeft}) =>
          Interest.fromJson({'id': 1, 'status': status, 'days_left': daysLeft});
      expect(at('declined').canReExpress, isTrue);
      expect(at('withdrawn').canReExpress, isTrue);
      expect(at('revoked').canReExpress, isTrue);
      expect(at('expired').canReExpress, isTrue);
      expect(at('accepted', daysLeft: 3).canReExpress, isFalse);
      expect(at('accepted', daysLeft: 3).isLive, isTrue);
      expect(at('accepted').isLive, isFalse, reason: 'no days_left means the window is not live');
      expect(at('pending').canReExpress, isFalse);
    });

    test('every state has a chip label and a colour-able status', () {
      expect(S.interestChip('pending', null), 'Waiting');
      expect(S.interestChip('accepted', 11), 'Details shared · 11 days');
      expect(S.interestChip('accepted', 1), 'Details shared · 1 day');
      expect(S.interestChip('declined', null), 'Declined');
      expect(S.interestChip('withdrawn', null), 'Withdrawn');
      expect(S.interestChip('expired', null), 'Expired');
      expect(S.interestChip('revoked', null), 'Access ended');
      expect(S.interestStatusLabel('accepted'), 'Details shared');
      expect(S.daysLeft(1), '1 day left');
      expect(S.daysLeft(7), '7 days left');
    });

    test('the detail route\'s interest drives the button state on the profile', () {
      Profile withInterest(String status, {int? daysLeft, bool protected = false}) {
        final j = publicProfileJson()
          ..['interest'] = {'id': 9, 'status': status, 'days_left': daysLeft}
          ..['contact_access'] = protected ? 'granted' : 'none';
        if (protected) j.addAll(protectedJson());
        return Profile.fromJson(j);
      }

      final pending = withInterest('pending');
      expect(pending.isInterested, isTrue);
      expect(pending.detailsShared, isFalse);
      expect(pending.interest!.canReExpress, isFalse);

      final accepted = withInterest('accepted', daysLeft: 4, protected: true);
      expect(accepted.isInterested, isTrue);
      expect(accepted.detailsShared, isTrue);
      expect(accepted.accessDaysLeft, 4);
      expect(accepted.fatherPhone, '9000000001');

      final declined = withInterest('declined');
      expect(declined.isInterested, isFalse);
      expect(declined.detailsShared, isFalse);
      expect(declined.interest!.canReExpress, isTrue);
      expect(declined.fatherName, isNull, reason: 'protected fields are omitted');

      final expired = withInterest('expired');
      expect(expired.isInterested, isFalse);
      expect(expired.detailsShared, isFalse);
      expect(expired.interest!.isExpired, isTrue);
      expect(expired.interest!.canReExpress, isTrue);

      final withdrawn = withInterest('withdrawn');
      expect(withdrawn.isInterested, isFalse);
      expect(withdrawn.interest!.isWithdrawn, isTrue);
    });
  });

  group('BrowseFilters', () {
    test('defaults send only paging and sort', () {
      expect(BrowseFilters.empty.activeCount, 0);
      expect(BrowseFilters.empty.hasSearch, isFalse);
      expect(BrowseFilters.empty.toQuery(page: 2, limit: 20), {'page': 2, 'limit': 20, 'sort': 'newest'});
    });

    test('set filters serialise with the agent list\'s parameter names', () {
      final f = const BrowseFilters().copyWith(
        ageMin: 24,
        ageMax: 30,
        heightMin: 150,
        heightMax: 175,
        communityIds: {3, 1},
        subcasteIds: {9},
        educationIds: {4},
        professionIds: {2},
        occupationTypeIds: {1},
        workCountryIds: {1},
        maritalStatusIds: {1},
        complexionIds: {2},
        religionIds: {1},
        motherTongueIds: {1},
        foodHabitIds: {1},
        nriOnly: true,
        countryIds: {5},
        city: 'Guntur',
        query: 'Lakshmi',
        sort: 'age_asc',
      );
      final q = f.toQuery(page: 1, limit: 20);
      expect(q['age_min'], 24);
      expect(q['age_max'], 30);
      expect(q['height_min'], 150);
      expect(q['height_max'], 175);
      expect(q['community_id'], '1,3', reason: 'comma list, sorted');
      expect(q['subcaste_id'], '9');
      expect(q['education_id'], '4');
      expect(q['profession_id'], '2');
      expect(q['occupation_type_id'], '1');
      expect(q['work_country_id'], '1');
      expect(q['marital_status_id'], '1');
      expect(q['complexion_id'], '2');
      expect(q['religion_id'], '1');
      expect(q['mother_tongue_id'], '1');
      expect(q['food_habit_id'], '1');
      expect(q['nri'], 'true');
      expect(q['country_id'], '5');
      expect(q['city'], 'Guntur');
      expect(q['q'], 'Lakshmi');
      expect(q['sort'], 'age_asc');
      expect(q.containsKey('gender'), isFalse, reason: 'the server picks the opposite gender');
      expect(q.containsKey('mine'), isFalse);
      expect(q.containsKey('status'), isFalse);
      // 15 filters set: NRI + countries count once, the search text is not a filter.
      expect(f.activeCount, 15);
      expect(f.hasSearch, isTrue);
    });

    test('NRI countries alone imply nri=true; switching NRI off drops them', () {
      final f = const BrowseFilters().copyWith(countryIds: {5});
      expect(f.toQuery()['nri'], 'true');
      expect(f.activeCount, 1);
      final off = f.copyWith(nriOnly: false, countryIds: const {});
      expect(off.toQuery().containsKey('nri'), isFalse);
    });

    test('clear all keeps the search text and sort', () {
      final f = const BrowseFilters().copyWith(query: 'Ravi', sort: 'name', city: 'Vizag', ageMin: 30);
      final cleared = f.clearedFilters();
      expect(cleared.activeCount, 0);
      expect(cleared.query, 'Ravi');
      expect(cleared.sort, 'name');
      expect(cleared.city, isNull);
      expect(f.copyWith(clearCity: true).city, isNull);
      expect(f.copyWith(clearQuery: true).query, isNull);
    });
  });

  group('AgentChangeRequest', () {
    test('parses the customer view with both agent cards', () {
      final r = AgentChangeRequest.fromJson({
        'id': 4,
        'status': 'pending',
        'note': 'Moving to Vijayawada',
        'created_at': '2026-09-25T05:00:00.000Z',
        'decided_at': null,
        'from_agent': {'id': 3, 'full_name': 'Suresh Babu', 'agency_name': 'Sri Lakshmi', 'city': 'Guntur', 'phone': '9000000003'},
        'to_agent': {'id': 8, 'full_name': 'Anitha', 'agency_name': null, 'city': 'Vijayawada', 'phone': '9000000008'},
      });
      expect(r.id, 4);
      expect(r.isPending, isTrue);
      expect(r.note, 'Moving to Vijayawada');
      expect(r.createdAt, isNotNull);
      expect(r.decidedAt, isNull);
      expect(r.fromAgent.fullName, 'Suresh Babu');
      expect(r.fromAgent.agencyLine, 'Sri Lakshmi · Guntur');
      expect(r.toAgent.fullName, 'Anitha');
      expect(r.toAgent.agencyLine, 'Vijayawada');
      expect(r.toAgent.phone, '9000000008');
      expect(r.toAgent.communities, isEmpty);
      expect(AgentChangeRequest.fromJson({'id': 1, 'status': 'approved', 'from_agent': {'id': 1, 'full_name': 'A'}, 'to_agent': {'id': 2, 'full_name': 'B'}}).isApproved, isTrue);
      expect(S.requestStatusLabel('rejected'), 'Not approved');
      expect(S.requestStatusLabel('cancelled'), 'Cancelled');
    });
  });

  group('OTP + masters', () {
    test('send response carries the mock code and resend delay', () {
      final s = OtpSent.fromJson({'sent': true, 'mock': true, 'expires_in': 300, 'retry_after': 30, 'mock_code': '123456'});
      expect(s.mock, isTrue);
      expect(s.mockCode, '123456');
      expect(s.retryAfter, 30);
      expect(s.expiresIn, 300);
      final prod = OtpSent.fromJson({'sent': true, 'mock': false});
      expect(prod.mockCode, isNull);
      expect(prod.retryAfter, 30, reason: 'default when the server omits it');
    });

    test('masters include occupation types and India-first countries', () {
      final m = MasterData.fromJson({
        'communities': [{'id': 3, 'name': 'Kamma'}],
        'professions': [],
        'educations': [],
        'marital_statuses': [],
        'countries': [{'id': 1, 'name': 'India'}, {'id': 5, 'name': 'United States'}],
        'occupation_types': [{'id': 1, 'name': 'Private job'}, {'id': 2, 'name': 'Government job'}],
        'zodiac_signs': [],
        'nakshatrams': [],
      });
      expect(m.occupationTypes.map((o) => o.name), ['Private job', 'Government job']);
      expect(m.occupationTypeName(2), 'Government job');
      expect(m.countries.first.name, 'India');
      expect(m.communityName(3), 'Kamma');
    });
  });
}
