import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/config.dart';
import 'package:gandharva/models/agent_change.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/models/master_data.dart';
import 'package:gandharva/models/privacy_settings.dart';
import 'package:gandharva/models/profile.dart';
import 'package:gandharva/services/agents_service.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/widgets/common.dart';

import 'guest_mode_test.dart' show activeMeJson, ownSummary;
import 'models_test.dart' show protectedJson, publicProfileJson;

/// GET /api/masters of a v2.8 server (SPEC §9.18): the usual lists plus
/// `states`, `privacy_fields` and `privacy_always_visible`.
Map<String, dynamic> mastersJson() => {
      'communities': [
        {'id': 1, 'name': 'Kamma'},
        {'id': 2, 'name': 'Reddy'},
        {'id': 3, 'name': 'Kapu'},
      ],
      'subcastes': [
        {'id': 9, 'community_id': 1, 'name': 'Chowdary'},
      ],
      'professions': [
        {'id': 2, 'name': 'Software Engineer'},
      ],
      'educations': [
        {'id': 4, 'name': 'B.Tech / B.E.'},
      ],
      'marital_statuses': [
        {'id': 1, 'name': 'Unmarried'},
      ],
      'countries': [
        {'id': 1, 'name': 'India'},
        {'id': 5, 'name': 'United States'},
      ],
      'zodiac_signs': [],
      'nakshatrams': [],
      'states': [
        {'id': 1, 'name': 'Karnataka', 'code': 'KA', 'active': true, 'sort_order': 1},
      ],
      'privacy_fields': [
        {'key': 'name', 'label': 'Name', 'section': 'personal', 'hint': 'Others see "Profile" and a number instead'},
        {'key': 'dob', 'label': 'Date of birth', 'section': 'personal', 'hint': 'Your age is always shown'},
        {'key': 'community', 'label': 'Community', 'section': 'personal', 'hint': null},
        {'key': 'subcaste', 'label': 'Subcaste', 'section': 'personal', 'hint': null},
        {'key': 'photos', 'label': 'Other photos', 'section': 'personal', 'hint': 'The main photo is always shown'},
        {'key': 'education', 'label': 'Education', 'section': 'professional', 'hint': null},
        {'key': 'income', 'label': 'Income', 'section': 'professional', 'hint': '  '},
        {'key': 'star_rasi', 'label': 'Star & rasi', 'section': 'horoscope', 'hint': null},
      ],
      'privacy_always_visible': ['Main photo', 'Age', 'Gender'],
    };

/// Every key of SPEC §9.18 D, as `masked_fields` lists them.
const allPrivacyKeys = [
  'name', 'dob', 'marital_status', 'religion', 'community', 'subcaste', 'mother_tongue', 'known_languages',
  'height', 'weight', 'complexion', 'food_habit', 'nationality', 'about', 'photos', 'education', 'profession',
  'income', 'work_location', 'star_rasi', 'gothram', 'birth_time',
];

/// Another family's profile with EVERY toggle switched off, as the detail
/// route sends it to a viewer without access (SPEC §9.18 D): values null /
/// `[]` / `is_nri: false`, the name replaced, only the main photo.
Map<String, dynamic> maskedProfileJson() => {
      'id': 1042,
      'full_name': 'Profile 1042',
      'gender': 'bride',
      'dob': null,
      'age': 27,
      'height_cm': null,
      'weight_kg': null,
      'complexion': null,
      'religion': null,
      'community': null,
      'subcaste': null,
      'gothram': null,
      'mother_tongue': null,
      'known_languages': [],
      'food_habit': null,
      'nationality': null,
      'education': null,
      'education_details': null,
      'education_levels': [],
      'profession': null,
      'profession_details': null,
      'occupation_type': null,
      'work_country': null,
      'marital_status': null,
      'zodiac': null,
      'nakshatram': null,
      'birth_time': null,
      'income_text': null,
      'other_income': null,
      'is_nri': false,
      'nri_country': null,
      'about': null,
      'status': 'active',
      'is_customer_profile': true,
      'created_at': '2026-11-01T10:00:00.000Z',
      'updated_at': '2026-11-02T10:00:00.000Z',
      'is_mine': false,
      'photos': [
        {'id': 7, 'url': '/api/customer/photos/7', 'is_primary': true, 'sort_order': 0},
      ],
      'primary_photo_url': '/api/customer/photos/7',
      'masked_fields': allPrivacyKeys,
      'interest': null,
    };

/// My own profile as `/customer/my-profiles/:id` returns it since v2.8.
Map<String, dynamic> ownProfileJson() => {
      ...publicProfileJson(),
      ...protectedJson(),
      'id': 77,
      'full_name': 'Priya',
      'is_mine': true,
      'community': {'id': 1, 'name': 'Kamma'},
      'subcaste': {'id': 9, 'name': 'Chowdary'},
      'paid': true,
      'paid_at': '2026-09-28T10:32:35.426Z',
      'visibility': 'live',
      'profile_fee_inr': 150,
      'delete_request': null,
      'profile_code': 'GN-KA1A-A001',
      'hidden_fields': ['income', 'community'],
      'audience_all': false,
      'audience_communities': [
        {'id': 2, 'name': 'Reddy'},
      ],
      'masked_fields': [],
    };

/// `/customer/auth/me` since v2.8: the ID and the agent's code.
Map<String, dynamic> wedbookMeJson() => {
      ...activeMeJson(),
      'customer_code': 'GN-KA1A-A001',
      'agent': {...(activeMeJson()['agent'] as Map<String, dynamic>), 'agent_code': 'KA1A'},
      'max_profiles': 1,
      'profiles': [
        {...ownSummary(77, 'Priya', 'bride', 'live'), 'profile_code': 'GN-KA1A-A001'},
      ],
    };

void main() {
  group('Brand', () {
    test('the app is Wedbook Matrimony everywhere a person reads it', () {
      expect(AppConfig.appName, 'Wedbook Matrimony');
      expect(S.brandShort, 'Wedbook');
      expect(S.appTagline, 'Matrimony');
      expect(S.signupBody, contains('Wedbook Matrimony'));
      expect(S.signupBody, isNot(contains('MILI')));
      expect(S.version, 'v3.1.0');
    });
  });

  group('IDs and agent codes (SPEC §9.18 B / C)', () {
    test('me carries customer_code, profiles[].profile_code and the agent code', () {
      final c = Customer.fromJson(wedbookMeJson());
      expect(c.customerCode, 'GN-KA1A-A001');
      expect(c.profiles.single.profileCode, 'GN-KA1A-A001');
      expect(c.agent!.agentCode, 'KA1A');
    });

    test('an older server (no codes) and blank codes read as null', () {
      final c = Customer.fromJson(activeMeJson());
      expect(c.customerCode, isNull);
      expect(c.agent!.agentCode, isNull);
      expect(c.profiles.first.profileCode, isNull);
      expect(Customer.fromJson({...activeMeJson(), 'customer_code': null}).customerCode, isNull);
      expect(Customer.fromJson({...activeMeJson(), 'customer_code': '  '}).customerCode, isNull);
      expect(AgentCard.fromJson({'id': 1, 'full_name': 'A', 'agent_code': null}).agentCode, isNull);
      expect(AgentCard.fromJson({'id': 1, 'full_name': 'A', 'agent_code': ''}).agentCode, isNull);
    });

    test('directory rows and agent-change rows carry agent_code', () {
      final row = AgentCard.fromJson({
        'id': 8,
        'full_name': 'Anitha',
        'agency_name': 'Anitha Matrimony',
        'city': 'Mysuru',
        'phone': '9000000008',
        'agent_code': 'KA2B',
        'communities': [],
        'is_current': false,
      });
      expect(row.agentCode, 'KA2B');
      expect(S.agentCodeLine(row.agentCode!), 'Agent code KA2B');

      final r = AgentChangeRequest.fromJson({
        'id': 4,
        'status': 'pending',
        'from_agent': {'id': 3, 'full_name': 'Suresh Babu', 'agent_code': 'KA1A'},
        'to_agent': {'id': 8, 'full_name': 'Anitha', 'agent_code': 'KA2B'},
      });
      expect(r.fromAgent.agentCode, 'KA1A');
      expect(r.toAgent.agentCode, 'KA2B');

      final pending = PendingAgentChange.fromJson({
        'id': 5,
        'to_agent': {'id': 8, 'full_name': 'Anitha', 'agent_code': 'KA2B'},
        'created_at': '2026-11-05T05:00:00.000Z',
      });
      expect(pending.toAgent.agentCode, 'KA2B');
    });

    test('my own profile carries its ID; other people\'s never do', () {
      expect(Profile.fromJson(ownProfileJson()).profileCode, 'GN-KA1A-A001');
      expect(Profile.fromJson(publicProfileJson()).profileCode, isNull);
      expect(Profile.fromJson({...ownProfileJson(), 'profile_code': null}).profileCode, isNull);
      expect(S.idLine('GN-KA1A-A001'), 'ID GN-KA1A-A001');
    });
  });

  group('Linking an agent: mobile number or agent code (SPEC §9.18 B / G)', () {
    test('ten digits are a mobile number — spaces, dashes, +91, 91 and a leading 0 are dropped', () {
      for (final input in [
        '9876543210',
        ' 98765 43210 ',
        '98765-43210',
        '+91 98765 43210',
        '+919876543210',
        '919876543210',
        '09876543210',
        '(98765) 43210',
      ]) {
        final lookup = AgentLookup.parse(input);
        expect(lookup, isNotNull, reason: input);
        expect(lookup!.isPhone, isTrue, reason: input);
        expect(lookup.phone, '9876543210', reason: input);
        expect(lookup.code, isNull, reason: input);
        expect(lookup.toJson(), {'agent_phone': '9876543210'}, reason: input);
      }
    });

    test('letters with digits are an agent code — case-insensitive, sent upper-cased', () {
      for (final (input, code) in [
        ('KA1A', 'KA1A'),
        ('ka1a', 'KA1A'),
        (' Ka 1a ', 'KA1A'),
        ('ts12z', 'TS12Z'),
        ('KA999ZZ', 'KA999ZZ'),
        ('ap-7-ab', 'AP7AB'),
      ]) {
        final lookup = AgentLookup.parse(input);
        expect(lookup, isNotNull, reason: input);
        expect(lookup!.isPhone, isFalse, reason: input);
        expect(lookup.code, code, reason: input);
        expect(lookup.phone, isNull, reason: input);
        expect(lookup.toJson(), {'agent_code': code}, reason: input);
      }
    });

    test('anything else is neither', () {
      for (final input in [
        '',
        '   ',
        '98765', // too few digits
        '98765432101', // eleven digits, not a leading 0
        '987654321', // nine
        '1234567890123',
        'KA', // letters only
        'KAAA',
        '1KA', // a code starts with the state letters
        'KA1A!',
        'agent',
        '+91',
      ]) {
        expect(AgentLookup.parse(input), isNull, reason: '"$input"');
      }
    });

    test('a number is never mistaken for a code and the other way round', () {
      expect(AgentLookup.parse('9876543210')!.toJson().containsKey('agent_code'), isFalse);
      expect(AgentLookup.parse('KA1A')!.toJson().containsKey('agent_phone'), isFalse);
      expect(AgentLookup.parse('KA1A').toString(), 'code:KA1A');
      expect(AgentLookup.parse('9876543210').toString(), 'phone:9876543210');
    });

    test('link errors are shown in the server\'s words; other errors stay friendly', () {
      String msg(String code, String message) => linkAgentMessage(ApiException(code, message, status: 400));
      expect(msg('agent_not_found', 'No agent has the code KA9Z'), 'No agent has the code KA9Z');
      expect(msg('agent_not_active', 'This agent is not active yet'), 'This agent is not active yet');
      expect(
        msg('agent_has_no_communities', 'This agent cannot take customers — check with your agent'),
        'This agent cannot take customers — check with your agent',
      );
      expect(msg('same_agent', 'That is already your agent'), 'That is already your agent');
      // No text from the server → the app's own sentence.
      expect(msg('agent_not_found', ''), S.errAgentNotFound);
      expect(msg('network_error', 'socket'), S.errNetwork);
      expect(msg('wrong_status', 'x'), S.errWrongStatus);
      expect(S.errAgentNotFound, contains('code'));
    });
  });

  group('Masters: privacy toggles (SPEC §9.18 D)', () {
    test('privacy_fields and privacy_always_visible parse, grouped by section', () {
      final m = MasterData.fromJson(mastersJson());
      expect(m.hasPrivacy, isTrue);
      expect(m.privacyFields.map((f) => f.key),
          ['name', 'dob', 'community', 'subcaste', 'photos', 'education', 'income', 'star_rasi']);
      expect(m.privacyAlwaysVisible, ['Main photo', 'Age', 'Gender']);
      expect(m.privacyFieldsIn('personal').map((f) => f.label),
          ['Name', 'Date of birth', 'Community', 'Subcaste', 'Other photos']);
      expect(m.privacyFieldsIn('professional').map((f) => f.key), ['education', 'income']);
      expect(m.privacyFieldsIn('horoscope').single.label, 'Star & rasi');
      expect(m.privacyFieldsElsewhere, isEmpty);
      final dob = m.privacyFields[1];
      expect(dob.hint, 'Your age is always shown');
      expect(m.privacyFields[2].hint, isNull);
      expect(m.privacyFields[6].hint, isNull, reason: 'a blank hint is no hint');
    });

    test('an older server sends neither — no toggles, nothing breaks', () {
      final j = mastersJson()
        ..remove('privacy_fields')
        ..remove('privacy_always_visible')
        ..remove('states');
      final m = MasterData.fromJson(j);
      expect(m.hasPrivacy, isFalse);
      expect(m.privacyFields, isEmpty);
      expect(m.privacyAlwaysVisible, isEmpty);
      expect(m.communities, hasLength(3));
      expect(MasterData.empty.hasPrivacy, isFalse);
      expect(MasterData.fromJson(const {}).privacyFields, isEmpty);
    });

    test('malformed rows are skipped; an unknown section is kept (listed last)', () {
      final m = MasterData.fromJson({
        ...mastersJson(),
        'privacy_fields': [
          {'key': 'name', 'label': 'Name', 'section': 'personal'},
          {'label': 'No key'},
          {'key': '', 'label': 'Empty key'},
          'not a map',
          null,
          {'key': 'hobbies', 'label': 'Hobbies', 'section': 'lifestyle', 'hint': 7},
          {'key': 'pets'},
        ],
        'privacy_always_visible': ['Main photo', 3, null, ''],
      });
      expect(m.privacyFields.map((f) => f.key), ['name', 'hobbies', 'pets']);
      expect(m.privacyFieldsElsewhere.single.key, 'hobbies');
      expect(m.privacyFieldsElsewhere.single.hint, isNull);
      expect(m.privacyFields.last.label, 'pets', reason: 'falls back to the key');
      expect(m.privacyFields.last.section, 'personal');
      expect(m.privacyAlwaysVisible, ['Main photo']);
      expect(S.privacySectionTitle('personal'), 'Personal');
      expect(S.privacySectionTitle('professional'), 'Professional');
      expect(S.privacySectionTitle('horoscope'), 'Horoscope');
      expect(S.privacySectionTitle('lifestyle'), S.privacyOtherSection);
    });
  });

  group('A profile with hidden details, as a viewer (SPEC §9.18 D)', () {
    test('a fully masked detail profile parses: every value empty, nothing "null"', () {
      final p = Profile.fromJson(maskedProfileJson());
      expect(p.id, 1042);
      expect(p.fullName, 'Profile 1042');
      expect(p.displayName, 'Profile 1042');
      expect(p.nameHidden, isTrue);
      expect(p.initialsSource, isNull, reason: 'no "P1" initials for a hidden name');
      expect(p.hasMaskedFields, isTrue);
      expect(p.maskedFields, allPrivacyKeys);

      // Always shown.
      expect(p.gender, 'bride');
      expect(p.age, 27);
      expect(p.primaryPhotoUrl, endsWith('/api/customer/photos/7'));
      expect(p.photos, hasLength(1));

      // Everything else is simply absent.
      expect(p.dob, isNull);
      expect(p.dobLabel, isNull);
      expect(p.ageDobLine, '27 yrs', reason: 'age stays without the date');
      expect(p.community, isNull);
      expect(p.subcaste, isNull);
      expect(p.communityLine, isNull);
      expect(p.religion, isNull);
      expect(p.maritalStatus, isNull);
      expect(p.motherTongue, isNull);
      expect(p.knownLanguages, isEmpty);
      expect(p.knownLanguagesLabel, isNull);
      expect(p.heightCm, isNull);
      expect(p.heightLabel, isNull);
      expect(p.heightShort, isNull);
      expect(p.weightLabel, isNull);
      expect(p.complexion, isNull);
      expect(p.foodHabit, isNull);
      expect(p.nationality, isNull);
      expect(p.about, isNull);
      expect(p.education, isNull);
      expect(p.educationLevels, isEmpty);
      expect(p.educationLine, isNull);
      expect(p.profession, isNull);
      expect(p.occupationType, isNull);
      expect(p.professionLine, isNull);
      expect(p.occupationLine, isNull);
      expect(p.jobLabel, isNull);
      expect(p.incomeText, isNull);
      expect(p.otherIncome, isNull);
      expect(p.workCountry, isNull);
      expect(p.isNri, isFalse);
      expect(p.nriLabel, isNull);
      expect(p.placeLine, isNull);
      expect(p.nakshatram, isNull);
      expect(p.zodiac, isNull);
      expect(p.starRasi, isNull);
      expect(p.gothram, isNull);
      expect(p.birthTimeLabel, isNull);
      expect(p.detailsShared, isFalse);
      expect(p.hasPersonalDetails, isFalse);

      // Nothing a screen prints may read "null".
      for (final text in [p.displayName, p.genderLabel, p.ageDobLine, p.communityLine, p.placeLine, p.starRasi]) {
        expect(text ?? '', isNot(contains('null')));
      }
    });

    test('a masked list row (browse card) parses too', () {
      final row = maskedProfileJson()
        ..remove('photos')
        ..remove('interest')
        ..['interest_status'] = null
        ..['is_interested'] = false;
      final page = ProfilePage.fromJson({
        'profiles': [row, publicProfileJson()],
        'total': 2,
        'page': 1,
        'access': 'full',
        'gender': 'bride',
      });
      final p = page.profiles.first;
      expect(p.displayName, 'Profile 1042');
      expect(p.photos, isEmpty);
      expect(p.primaryPhotoUrl, isNotNull);
      expect(p.communityLine, isNull);
      expect(p.isInterested, isFalse);
      // The unmasked row next to it is untouched.
      expect(page.profiles.last.hasMaskedFields, isFalse);
      expect(page.profiles.last.nameHidden, isFalse);
      expect(page.profiles.last.initialsSource, 'Lakshmi Prasanna');
    });

    test('masked values missing altogether (keys absent) are the same as null', () {
      final p = Profile.fromJson({
        'id': 9,
        'gender': 'groom',
        'age': 31,
        'masked_fields': ['name', 'community'],
      });
      expect(p.fullName, '');
      expect(p.displayName, 'Profile 9', reason: 'never an empty title');
      expect(p.initialsSource, isNull);
      expect(p.knownLanguages, isEmpty);
      expect(p.educationLevels, isEmpty);
      expect(p.photos, isEmpty);
      expect(p.primaryPhotoUrl, isNull);
      expect(p.maskedFields, ['name', 'community']);
    });

    test('odd shapes never throw: wrong types are treated as absent', () {
      final p = Profile.fromJson({
        'id': 9,
        'full_name': null,
        'gender': 'bride',
        'age': '27',
        'community': 'Kamma',
        'subcaste': {'id': 9},
        'education': [],
        'known_languages': null,
        'education_levels': 'none',
        'photos': null,
        'zodiac': 'Mesha',
        'about': 12,
        'masked_fields': 'name',
        'hidden_fields': [1, null, 'income', ''],
        'audience_communities': [null, {'id': 2, 'name': 'Reddy'}, 'x'],
      });
      expect(p.age, isNull);
      expect(p.community, isNull);
      expect(p.subcaste, isNull, reason: 'a ref without a name is no ref');
      expect(p.education, isNull);
      expect(p.zodiac, isNull);
      expect(p.about, isNull);
      expect(p.maskedFields, isEmpty);
      expect(p.hiddenFields, ['income']);
      expect(p.audienceCommunities.single.name, 'Reddy');
    });

    test('a partly masked profile keeps what is shown', () {
      final j = publicProfileJson()
        ..['full_name'] = 'Profile 41'
        ..['income_text'] = null
        ..['other_income'] = null
        ..['masked_fields'] = ['name', 'income'];
      final p = Profile.fromJson(j);
      expect(p.nameHidden, isTrue);
      expect(p.displayName, 'Profile 41');
      expect(p.communityLine, 'Kamma · Chowdary');
      expect(p.incomeText, isNull);
      expect(p.educationLine, 'B.Tech / B.E. — CSE, JNTU 2019');
    });

    test('profiles from an older server have no masked_fields', () {
      final p = Profile.fromJson(publicProfileJson());
      expect(p.maskedFields, isEmpty);
      expect(p.hasMaskedFields, isFalse);
      expect(p.nameHidden, isFalse);
      expect(p.displayName, 'Lakshmi Prasanna');
    });

    test('interest rows: a summary with a hidden name (name_hidden) and no community', () {
      final i = Interest.fromJson({
        'id': 5,
        'status': 'pending',
        'profile': {
          'id': 1042,
          'full_name': 'Profile 1042',
          'gender': 'bride',
          'age': 27,
          'community': null,
          'subcaste': null,
          'status': 'active',
          'photo_url': '/api/customer/photos/7',
          'name_hidden': true,
        },
        'from_profile': {...ownSummary(79, 'Ravi', 'groom', 'live'), 'profile_code': 'GN-KA1A-A002'},
      });
      final s = i.profile!;
      expect(s.nameHidden, isTrue);
      expect(s.displayName, 'Profile 1042');
      expect(s.initialsSource, isNull);
      expect(s.communityLine, isNull);
      expect(s.profileCode, isNull, reason: 'the other side never gets an ID');
      expect(i.fromProfile!.nameHidden, isFalse);
      expect(i.fromProfile!.profileCode, 'GN-KA1A-A002');
      expect(i.fromProfile!.initialsSource, 'Ravi');
    });

    test('a bare summary is tolerated', () {
      final s = ProfileSummary.fromJson({'id': 3});
      expect(s.displayName, 'Profile 3');
      expect(s.nameHidden, isFalse);
      expect(s.age, isNull);
      expect(s.photoUrl, isNull);
      final odd = ProfileSummary.fromJson({'id': 3, 'full_name': 'A', 'age': 'x', 'status': 4, 'photo_url': 9});
      expect(odd.age, isNull);
      expect(odd.status, isNull);
      expect(odd.absolutePhotoUrl, isNull);
    });
  });

  group('My own profile: privacy + audience (SPEC §9.18 D / E)', () {
    test('own view carries hidden_fields, audience_all, audience_communities', () {
      final p = Profile.fromJson(ownProfileJson());
      expect(p.hiddenFields, ['income', 'community']);
      expect(p.audienceAll, isFalse);
      expect(p.audienceCommunities.map((c) => c.name), ['Reddy']);
      expect(p.maskedFields, isEmpty, reason: 'nothing is withheld from the owner');
      expect(p.incomeText, '12 LPA', reason: 'my own hidden details still come to me');
    });

    test('defaults when the keys are absent: everything shown, own community only', () {
      final p = Profile.fromJson(publicProfileJson()..['is_mine'] = true);
      expect(p.hiddenFields, isEmpty);
      expect(p.audienceAll, isFalse);
      expect(p.audienceCommunities, isEmpty);
      final s = PrivacySettings.fromProfile(p);
      expect(s.hidden, isEmpty);
      expect(s.audience, AudienceMode.ownCommunity);
      expect(s.communityIds, isEmpty);
    });
  });

  group('Privacy switches ↔ hidden_fields (SPEC §9.18 D / E / G)', () {
    final fields = MasterData.fromJson(mastersJson()).privacyFields;
    Profile own([Map<String, dynamic> extra = const {}]) => Profile.fromJson({...ownProfileJson(), ...extra});

    test('a profile maps to the switches: hidden keys are OFF, the rest ON', () {
      final s = PrivacySettings.fromProfile(own());
      expect(s.isShown('name'), isTrue);
      expect(s.isShown('education'), isTrue);
      expect(s.isShown('income'), isFalse);
      expect(s.isShown('community'), isFalse);
      // The community is hidden → the subcaste is off with it, and locked.
      expect(s.isShown('subcaste'), isFalse);
      expect(s.canToggle('subcaste'), isFalse);
      expect(s.canToggle('community'), isTrue);
      expect(s.audience, AudienceMode.selected);
      expect(s.communityIds, {2});
    });

    test('the request lists exactly the switches that are OFF, in the masters\' order', () {
      final s = PrivacySettings.fromProfile(own());
      expect(s.hiddenFields(fields), ['community', 'subcaste', 'income']);
      expect(s.hiddenCount(fields), 3);
      expect(s.toJson(fields, ownCommunityId: 1), {
        'hidden_fields': ['community', 'subcaste', 'income'],
        'audience_all': false,
        'audience_community_ids': [2],
      });
    });

    test('everything shown → hidden_fields: []', () {
      final s = PrivacySettings.fromProfile(own({'hidden_fields': [], 'audience_communities': []}));
      expect(s.toJson(fields, ownCommunityId: 1), {
        'hidden_fields': <String>[],
        'audience_all': false,
        'audience_community_ids': <int>[],
      });
      for (final f in fields) {
        expect(s.isShown(f.key), isTrue, reason: f.key);
        expect(s.canToggle(f.key), isTrue, reason: f.key);
      }
    });

    test('switching a detail off and on again', () {
      const s = PrivacySettings();
      final off = s.setShown('dob', false);
      expect(off.isShown('dob'), isFalse);
      expect(off.hiddenFields(fields), ['dob']);
      expect(s.isShown('dob'), isTrue, reason: 'values are immutable');
      final on = off.setShown('dob', true);
      expect(on.hiddenFields(fields), isEmpty);
      // Setting a switch to where it already is changes nothing.
      expect(identical(on.setShown('dob', true), on), isTrue);
    });

    test('community OFF takes the subcaste with it and locks it', () {
      const s = PrivacySettings();
      final off = s.setShown('community', false);
      expect(off.isShown('community'), isFalse);
      expect(off.isShown('subcaste'), isFalse);
      expect(off.canToggle('subcaste'), isFalse);
      expect(off.hiddenFields(fields), ['community', 'subcaste']);
      // The locked switch does not move.
      expect(off.setShown('subcaste', true).isShown('subcaste'), isFalse);
      expect(identical(off.setShown('subcaste', true), off), isTrue);
      // Community back on: the subcaste is free again and as it was before.
      final on = off.setShown('community', true);
      expect(on.canToggle('subcaste'), isTrue);
      expect(on.isShown('subcaste'), isTrue);
      expect(on.hiddenFields(fields), isEmpty);
    });

    test('a subcaste hidden by itself stays hidden when the community comes back', () {
      final s = const PrivacySettings().setShown('subcaste', false).setShown('community', false);
      expect(s.hiddenFields(fields), ['community', 'subcaste']);
      final back = s.setShown('community', true);
      expect(back.isShown('subcaste'), isFalse);
      expect(back.canToggle('subcaste'), isTrue);
      expect(back.hiddenFields(fields), ['subcaste']);
    });

    test('a hidden key these masters do not list is kept (never revealed by accident)', () {
      final s = PrivacySettings.fromProfile(own({'hidden_fields': ['income', 'future_key']}));
      expect(s.hiddenFields(fields), ['income', 'future_key']);
      expect(s.setShown('income', true).hiddenFields(fields), ['future_key']);
    });

    test('audience: own community only / selected / all', () {
      const s = PrivacySettings();
      expect(s.toJson(fields, ownCommunityId: 1)['audience_all'], isFalse);
      expect(s.toJson(fields, ownCommunityId: 1)['audience_community_ids'], isEmpty);

      final selected = s.withAudience(AudienceMode.selected).toggleCommunity(3).toggleCommunity(2);
      expect(selected.communityIds, {2, 3});
      expect(selected.toJson(fields, ownCommunityId: 1), {
        'hidden_fields': <String>[],
        'audience_all': false,
        'audience_community_ids': [2, 3],
      });
      // Tapping a chip again removes it.
      expect(selected.toggleCommunity(3).communityIds, {2});
      // The own community is implicit: it cannot be toggled and is never sent.
      expect(selected.toggleCommunity(1, ownCommunityId: 1).communityIds, {2, 3});
      expect(const PrivacySettings(audience: AudienceMode.selected, communityIds: {1, 2}).audienceCommunityIds(ownCommunityId: 1), [2]);

      final all = selected.withAudience(AudienceMode.all);
      expect(all.toJson(fields, ownCommunityId: 1), {
        'hidden_fields': <String>[],
        'audience_all': true,
        'audience_community_ids': <int>[],
      });
      // Back to "my community only": the picks are not sent.
      expect(all.withAudience(AudienceMode.ownCommunity).toJson(fields, ownCommunityId: 1)['audience_community_ids'], isEmpty);
    });

    test('a profile maps to the audience choice', () {
      expect(PrivacySettings.fromProfile(own({'audience_all': true})).audience, AudienceMode.all);
      expect(PrivacySettings.fromProfile(own({'audience_communities': []})).audience, AudienceMode.ownCommunity);
      // The own community in the list (it should not be) is dropped.
      final s = PrivacySettings.fromProfile(own({
        'audience_communities': [
          {'id': 1, 'name': 'Kamma'},
        ],
      }));
      expect(s.audience, AudienceMode.ownCommunity);
      expect(s.communityIds, isEmpty);
    });

    test('"unsaved changes" compares what would be sent', () {
      final saved = PrivacySettings.fromProfile(own());
      expect(saved.sameAs(saved, fields, ownCommunityId: 1), isTrue);
      expect(saved.setShown('name', false).sameAs(saved, fields, ownCommunityId: 1), isFalse);
      expect(saved.setShown('name', false).setShown('name', true).sameAs(saved, fields, ownCommunityId: 1), isTrue);
      expect(saved.withAudience(AudienceMode.all).sameAs(saved, fields, ownCommunityId: 1), isFalse);
      expect(saved.toggleCommunity(3).sameAs(saved, fields, ownCommunityId: 1), isFalse);
      // "Selected" with nothing picked sends the same as "my community only".
      const none = PrivacySettings();
      expect(none.withAudience(AudienceMode.selected).sameAs(none, fields, ownCommunityId: 1), isTrue);
    });

    test('the summary line on My profile', () {
      expect(S.privacySummary(hidden: 3, allCommunities: true), '3 details hidden · shown to all communities');
      expect(S.privacySummary(hidden: 0, allCommunities: false), 'All details shown · shown to your community only');
      expect(S.privacySummary(hidden: 1, allCommunities: false, extraCommunities: 2),
          '1 detail hidden · shown to your community + 2 more');
    });
  });
}
