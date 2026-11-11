import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/config.dart';
import 'package:matrimony_agents/models/agent.dart';
import 'package:matrimony_agents/models/agent_change.dart';
import 'package:matrimony_agents/models/contact_request.dart';
import 'package:matrimony_agents/models/customer.dart';
import 'package:matrimony_agents/models/delete_request.dart';
import 'package:matrimony_agents/models/hold_request.dart';
import 'package:matrimony_agents/models/interest.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/models/profile.dart';
import 'package:matrimony_agents/models/shortlist.dart';
import 'package:matrimony_agents/ui/strings.dart';

/// Wire shapes of release 3.0.0 (SPEC §9.18): agent state + code, profile /
/// customer IDs, privacy toggles (masked_fields / hidden_fields), the
/// community audience and the new masters.
void main() {
  group('brand (SPEC §9.18 A)', () {
    test('the app is Wedbook Agent; the customers\' app is Wedbook Matrimony', () {
      expect(AppConfig.appName, 'Wedbook Agent');
      expect(AppConfig.appVersion, '3.1.0');
      expect(S.brandName, 'Wedbook');
      expect(S.appTagline, 'Agent');
      expect(S.customerAppName, 'Wedbook Matrimony');
      // Nothing an agent reads still says MILI or Mediator.
      for (final text in [
        S.noClientsHint,
        S.noProfileYetBody,
        S.rejectClientBody,
        S.customersSubtitle,
        S.unpaidApproveNote,
        S.paymentRequired,
        S.guestReassignNote,
      ]) {
        expect(text, isNot(contains('MILI')));
        expect(text, isNot(contains('Mediator')));
        expect(text, isNot(contains('Gandharva')));
      }
      expect(S.noProfileYetBody, contains('Wedbook Matrimony'));
    });

    test('search hints mention the ID and the agent code', () {
      expect(S.searchHint, 'Search by name or ID');
      expect(S.searchClients, contains('ID'));
      expect(S.searchAgentsAdmin, 'Search name, phone or agent code');
    });
  });

  group('MasterData states and privacy fields (SPEC §9.18 B / D)', () {
    const json = {
      'communities': [
        {'id': 1, 'name': 'Reddy'},
      ],
      'professions': [],
      'educations': [],
      'marital_statuses': [],
      'zodiac_signs': [],
      'nakshatrams': [],
      'states': [
        {'id': 1, 'name': 'Karnataka', 'code': 'KA', 'active': true, 'sort_order': 1},
        {'id': 2, 'name': 'Andhra Pradesh', 'code': 'AP', 'active': true, 'sort_order': 2},
        {'id': 9, 'name': 'Old State', 'code': 'OS', 'active': false, 'sort_order': 99},
      ],
      'privacy_fields': [
        {'key': 'name', 'label': 'Name', 'section': 'personal', 'hint': null},
        {'key': 'dob', 'label': 'Date of birth', 'section': 'personal', 'hint': 'Age stays visible'},
        {'key': 'community', 'label': 'Community', 'section': 'personal', 'hint': 'Also hides the subcaste'},
        {'key': 'subcaste', 'label': 'Subcaste', 'section': 'personal', 'hint': null},
        {'key': 'education', 'label': 'Education', 'section': 'professional', 'hint': null},
        {'key': 'star_rasi', 'label': 'Star / Rasi', 'section': 'horoscope', 'hint': ''},
      ],
      'privacy_always_visible': ['Main photo', 'Age', 'Gender'],
    };

    test('states parse with their codes; only active ones are offered', () {
      final m = MasterData.fromJson(json);
      expect(m.states.map((s) => s.code), ['KA', 'AP', 'OS']);
      expect(m.activeStates.map((s) => s.name), ['Karnataka', 'Andhra Pradesh']);
      expect(m.states.first.label, 'KA — Karnataka');
      expect(m.stateById(2)?.name, 'Andhra Pradesh');
      expect(m.stateById(77), isNull);
      expect(m.stateById(null), isNull);
    });

    test('privacy fields keep the served order and group by section', () {
      final m = MasterData.fromJson(json);
      expect(m.privacyFields.map((f) => f.key),
          ['name', 'dob', 'community', 'subcaste', 'education', 'star_rasi']);
      expect(m.privacySections, ['personal', 'professional', 'horoscope']);
      expect(m.privacyFieldsIn('personal').length, 4);
      expect(m.privacyFieldsIn('horoscope').single.label, 'Star / Rasi');
      expect(m.privacyFields[1].hint, 'Age stays visible');
      expect(m.privacyFields.first.hint, isNull);
      expect(m.privacyFields.last.hint, isNull, reason: 'an empty hint is no hint');
      expect(m.privacyAlwaysVisible, ['Main photo', 'Age', 'Gender']);
      expect(PrivacyField.sectionLabel('professional'), 'Professional');
      expect(PrivacyField.sectionLabel('lifestyle'), 'Lifestyle');
    });

    test('a server older than v2.8 sends none of this — everything is empty', () {
      final m = MasterData.fromJson(const {
        'communities': [],
        'professions': [],
        'educations': [],
        'marital_statuses': [],
        'zodiac_signs': [],
        'nakshatrams': [],
      });
      expect(m.states, isEmpty);
      expect(m.activeStates, isEmpty);
      expect(m.privacyFields, isEmpty);
      expect(m.privacySections, isEmpty);
      expect(m.privacyAlwaysVisible, isEmpty);
      expect(MasterData.empty.states, isEmpty);
    });

    test('junk rows are skipped instead of crashing', () {
      final m = MasterData.fromJson(const {
        'states': [
          {'id': null, 'name': 'No id', 'code': 'XX'},
          'nonsense',
          {'id': 3, 'name': 'Kerala', 'code': 'KL'},
        ],
        'privacy_fields': [
          {'label': 'No key', 'section': 'personal'},
          {'key': 'about', 'section': 'personal'},
        ],
      });
      expect(m.states.single.code, 'KL');
      expect(m.states.single.active, isTrue, reason: 'active defaults to true');
      expect(m.privacyFields.single.key, 'about');
      expect(m.privacyFields.single.label, 'about', reason: 'label falls back to the key');
    });
  });

  group('Agent state and code (SPEC §9.18 B)', () {
    Map<String, dynamic> agentJson({Object? state, Object? code, String status = 'active'}) => {
          'id': 4,
          'full_name': 'Lakshmi',
          'phone': '9000000004',
          'role': 'agent',
          'status': status,
          'state': state,
          'agent_code': code,
        };

    test('an agent with a state and a code', () {
      final a = Agent.fromJson(agentJson(
        state: {'id': 1, 'name': 'Karnataka', 'code': 'KA'},
        code: 'KA1A',
      ));
      expect(a.state?.name, 'Karnataka');
      expect(a.state?.code, 'KA');
      expect(a.agentCode, 'KA1A');
      expect(a.hasAgentCode, isTrue);
      expect(a.needsState, isFalse);
    });

    test('an active agent from before v2.8 (null code) must choose a state', () {
      final a = Agent.fromJson(agentJson());
      expect(a.state, isNull);
      expect(a.agentCode, isNull);
      expect(a.knowsAgentCodes, isTrue);
      expect(a.needsState, isTrue);
    });

    test('pending and suspended agents are not asked — only active ones', () {
      expect(Agent.fromJson(agentJson(status: 'pending')).needsState, isFalse);
      expect(Agent.fromJson(agentJson(status: 'suspended')).needsState, isFalse);
    });

    test('an older server (no agent_code key at all) never triggers the gate', () {
      final a = Agent.fromJson(const {
        'id': 4,
        'full_name': 'Lakshmi',
        'phone': '9000000004',
        'status': 'active',
      });
      expect(a.knowsAgentCodes, isFalse);
      expect(a.agentCode, isNull);
      expect(a.needsState, isFalse);
    });

    test('an empty code or a state without an id counts as none', () {
      final a = Agent.fromJson(agentJson(state: {'id': null, 'name': null, 'code': null}, code: ''));
      expect(a.state, isNull);
      expect(a.hasAgentCode, isFalse);
      expect(a.needsState, isTrue);
    });

    test('admin agent rows carry the code and the state', () {
      final row = AdminAgent.fromJson({
        ...agentJson(state: {'id': 2, 'name': 'Andhra Pradesh', 'code': 'AP'}, code: 'AP12B'),
        'profile_count': 7,
      });
      expect(row.agent.agentCode, 'AP12B');
      expect(row.agent.state?.label, 'AP — Andhra Pradesh');
      expect(row.profileCount, 7);
    });

    test('confirmation text names the state and its prefix', () {
      expect(
        S.confirmStateBody('KA', 'Karnataka'),
        'KA — Karnataka. Your agent code will start with KA and cannot be changed later.',
      );
      expect(S.stateHelper, 'Decides your agent code — it cannot be changed later');
    });
  });

  group('Profile IDs, hidden details and audience (SPEC §9.18 C / D / E)', () {
    const base = {
      'id': 1042,
      'full_name': 'Sravani Reddy',
      'gender': 'bride',
      'status': 'active',
      'dob': '1998-04-12',
      'age': 27,
      'community': {'id': 1, 'name': 'Reddy'},
    };

    test('owner side: profile_code, hidden_fields and the audience', () {
      final p = Profile.fromJson({
        ...base,
        'is_mine': true,
        'profile_code': 'GN-KA1A-A001',
        'masked_fields': [],
        'hidden_fields': ['name', 'income'],
        'audience_all': false,
        'audience_communities': [
          {'id': 2, 'name': 'Kamma'},
          {'id': 5, 'name': 'Kapu'},
        ],
      });
      expect(p.profileCode, 'GN-KA1A-A001');
      expect(p.hasProfileCode, isTrue);
      expect(S.idLabel(p.profileCode!), 'ID GN-KA1A-A001');
      expect(p.maskedFields, isEmpty);
      expect(p.hasMaskedFields, isFalse);
      expect(p.nameHidden, isFalse, reason: 'the owner side sees the real name');
      expect(p.fullName, 'Sravani Reddy');
      expect(p.hiddenFields, ['name', 'income']);
      expect(p.audienceAll, isFalse);
      expect(p.audienceCommunities.map((c) => c.name), ['Kamma', 'Kapu']);
    });

    test('all communities audience', () {
      final p = Profile.fromJson({...base, 'hidden_fields': [], 'audience_all': true});
      expect(p.audienceAll, isTrue);
      expect(p.hiddenFields, isEmpty);
      expect(p.audienceCommunities, isEmpty);
    });

    test('other agents: no profile_code key, no hidden_fields, audience defaults', () {
      final p = Profile.fromJson({...base, 'masked_fields': []});
      expect(p.profileCode, isNull);
      expect(p.hasProfileCode, isFalse);
      expect(p.hiddenFields, isNull, reason: 'null = the server did not say');
      expect(p.audienceAll, isFalse);
      expect(p.audienceCommunities, isEmpty);
    });

    test('an older server without masked_fields means nothing is masked', () {
      final p = Profile.fromJson(base);
      expect(p.maskedFields, isEmpty);
      expect(p.hasMaskedFields, isFalse);
      expect(p.isMasked('community'), isFalse);
    });

    test('a fully masked profile parses and every helper stays null-safe', () {
      // Everything the family can switch off is off and I have no access:
      // values arrive as null / [] / false, the name as a neutral label.
      final p = Profile.fromJson(const {
        'id': 1042,
        'full_name': 'Profile 1042',
        'gender': 'groom',
        'status': 'active',
        'age': 31,
        'dob': null,
        'marital_status': null,
        'religion': null,
        'community': null,
        'subcaste': null,
        'mother_tongue': null,
        'known_languages': [],
        'height_cm': null,
        'weight_kg': null,
        'complexion': null,
        'food_habit': null,
        'nationality': null,
        'about': null,
        'education': null,
        'education_details': null,
        'education_levels': [],
        'profession': null,
        'profession_details': null,
        'occupation_type': null,
        'income_text': null,
        'other_income': null,
        'work_country': null,
        'is_nri': false,
        'nri_country': null,
        'nakshatram': null,
        'zodiac': null,
        'gothram': null,
        'birth_time': null,
        'photos': [
          {'id': 9, 'url': '/api/photos/9', 'is_primary': true},
        ],
        'contact_access': 'none',
        'masked_fields': [
          'name', 'dob', 'marital_status', 'religion', 'community', 'subcaste', 'mother_tongue',
          'known_languages', 'height', 'weight', 'complexion', 'food_habit', 'nationality',
          'about', 'photos', 'education', 'profession', 'income', 'work_location', 'star_rasi',
          'gothram', 'birth_time',
        ],
      });

      expect(p.fullName, 'Profile 1042');
      expect(p.nameHidden, isTrue);
      expect(p.hasMaskedFields, isTrue);
      expect(p.isMasked('community'), isTrue);
      expect(p.isMasked('income'), isTrue);
      expect(p.genderLabel, 'Groom');
      expect(p.age, 31, reason: 'age is always shown');
      expect(p.photos.single.isPrimary, isTrue, reason: 'the main photo is always shown');

      // Every display helper copes with the missing values.
      expect(p.dob, isNull);
      expect(p.dobLabel, isNull);
      expect(p.ageDobLine, '31 yrs');
      expect(p.community, isNull);
      expect(p.subcaste, isNull);
      expect(p.communityLine, isNull);
      expect(p.heightLabel, isNull);
      expect(p.heightShort, isNull);
      expect(p.weightLabel, isNull);
      expect(p.knownLanguages, isEmpty);
      expect(p.knownLanguagesLabel, isNull);
      expect(p.education, isNull);
      expect(p.educationLine, isNull);
      expect(p.educationLevels, isEmpty);
      expect(p.educationLevelsLabel, isNull);
      expect(p.profession, isNull);
      expect(p.professionLine, isNull);
      expect(p.isNri, isFalse);
      expect(p.nriLabel, isNull);
      expect(p.placeLine, isNull);
      expect(p.worksIn, isNull);
      expect(p.starRasi, isNull);
      expect(p.birthTimeLabel, isNull);
      expect(p.nativePlace, isNull);
      expect(p.birthPlaceLine, isNull);
      expect(p.siblingsLabel, isNull);
      expect(p.hasPersonalDetails, isFalse);
      expect(p.contactAccess, ContactAccess.none);
      expect(p.profileCode, isNull);

      // Nothing an agent reads may say "null".
      for (final text in [p.fullName, p.genderLabel, p.ageDobLine, p.status.label]) {
        expect(text, isNot(contains('null')));
      }
    });

    test('a missing name never prints "null" — the neutral label is used', () {
      final p = Profile.fromJson(const {'id': 7, 'gender': 'bride', 'status': 'active'});
      expect(p.fullName, 'Profile 7');
      final q = Profile.fromJson(const {'id': 8, 'full_name': '  ', 'gender': 'bride'});
      expect(q.fullName, 'Profile 8');
    });

    test('malformed masked values are tolerated', () {
      // Lists where objects are expected, and the other way round.
      final p = Profile.fromJson(const {
        'id': 5,
        'full_name': 'Kiran',
        'gender': 'groom',
        'community': [],
        'education': [],
        'zodiac': [],
        'known_languages': null,
        'education_levels': null,
        'photos': null,
        'masked_fields': null,
        'audience_communities': null,
        'hidden_fields': 'name',
      });
      expect(p.community, isNull);
      expect(p.education, isNull);
      expect(p.zodiac, isNull);
      expect(p.knownLanguages, isEmpty);
      expect(p.photos, isEmpty);
      expect(p.maskedFields, isEmpty);
      expect(p.hiddenFields, isNull, reason: 'not a list → treated as absent');
      expect(p.primaryPhotoUrl, isNull);
    });

    test('list pages of masked rows parse', () {
      final page = ProfilePage.fromJson(const {
        'profiles': [
          {
            'id': 1,
            'full_name': 'Profile 1',
            'gender': 'bride',
            'age': 24,
            'community': null,
            'masked_fields': ['name', 'community', 'subcaste'],
          },
          {
            'id': 2,
            'full_name': 'Anusha',
            'gender': 'bride',
            'age': 26,
            'community': {'id': 1, 'name': 'Reddy'},
            'masked_fields': [],
            'profile_code': 'GN-KA1A-A002',
            'is_mine': true,
          },
        ],
        'total': 2,
        'page': 1,
      });
      expect(page.profiles[0].nameHidden, isTrue);
      expect(page.profiles[0].communityLine, isNull);
      expect(page.profiles[0].profileCode, isNull);
      expect(page.profiles[1].nameHidden, isFalse);
      expect(page.profiles[1].profileCode, 'GN-KA1A-A002');
    });
  });

  group('Embedded summaries and request rows (SPEC §9.18 C / D)', () {
    test('profile summary: owner side has the ID; a hidden name is flagged', () {
      final mine = ProfileSummary.fromJson(const {
        'id': 9,
        'full_name': 'Priya',
        'gender': 'bride',
        'age': 25,
        'community': {'id': 1, 'name': 'Reddy'},
        'profile_code': 'GN-KA1A-A009',
      });
      expect(mine.profileCode, 'GN-KA1A-A009');
      expect(mine.idLabel, 'ID GN-KA1A-A009');
      expect(mine.nameHidden, isFalse);

      final theirs = ProfileSummary.fromJson(const {
        'id': 1042,
        'full_name': 'Profile 1042',
        'gender': 'groom',
        'age': 30,
        'community': null,
        'subcaste': null,
        'name_hidden': true,
      });
      expect(theirs.nameHidden, isTrue);
      expect(theirs.fullName, 'Profile 1042');
      expect(theirs.community, isNull);
      expect(theirs.profileCode, isNull);
      expect(theirs.idLabel, isNull);
      expect(theirs.subtitle, 'Groom · 30 yrs', reason: 'no dangling separator, no "null"');
    });

    test('a summary without a name falls back to the neutral label', () {
      final s = ProfileSummary.fromJson(const {'id': 3});
      expect(s.fullName, 'Profile 3');
      expect(s.subtitle, '');
    });

    test('interest rows: both summaries and the other agent\'s code', () {
      final it = Interest.fromJson(const {
        'id': 5,
        'status': 'pending',
        'customer': {'id': 2, 'full_name': 'Profile 9', 'agent_id': 8},
        'profile': {
          'id': 7,
          'full_name': 'Ravi Teja',
          'gender': 'groom',
          'profile_code': 'GN-KA1A-A007',
        },
        'customer_profile': {
          'id': 9,
          'full_name': 'Profile 9',
          'gender': 'bride',
          'community': null,
          'name_hidden': true,
        },
        'customer_agent': {
          'id': 8,
          'full_name': 'Suresh',
          'agency_name': 'Om Bureau',
          'phone': '9000000008',
          'agent_code': 'AP3C',
        },
        'can_decide': true,
      });
      expect(it.profile?.profileCode, 'GN-KA1A-A007');
      expect(it.customerProfile?.nameHidden, isTrue);
      expect(it.customerProfile?.profileCode, isNull);
      expect(it.otherAgent?.agentCode, 'AP3C');
      expect(it.otherAgent?.nameWithCode, 'Suresh (AP3C)');
      expect(it.otherAgent?.labelCommaWithCode, 'Suresh (AP3C), Om Bureau');
      expect(it.otherAgent?.labelWithCode, 'Suresh (AP3C) · Om Bureau');
    });

    test('an agent card without a code reads as before', () {
      final card = AgentCard.fromJson(const {'id': 1, 'full_name': 'Ravi', 'agency_name': 'Sri Bureau'});
      expect(card.agentCode, isNull);
      expect(card.hasAgentCode, isFalse);
      expect(card.nameWithCode, 'Ravi');
      expect(card.labelCommaWithCode, 'Ravi, Sri Bureau');
      final nullCode = AgentCard.fromJson(const {'id': 1, 'full_name': 'Ravi', 'agent_code': null});
      expect(nullCode.nameWithCode, 'Ravi');
    });

    test('agent-change rows carry both agents\' codes', () {
      final r = AgentChangeRequest.fromJson(const {
        'id': 3,
        'status': 'pending',
        'box': 'outgoing',
        'from_agent': {'id': 1, 'full_name': 'Lakshmi', 'agent_code': 'KA1A'},
        'to_agent': {'id': 2, 'full_name': 'Suresh', 'agency_name': 'Om Bureau', 'agent_code': 'TS2B'},
        'customer': {'id': 5, 'full_name': 'Priya'},
        'customer_profile': {'id': 9, 'full_name': 'Priya', 'profile_code': 'GN-KA1A-A009'},
        'can_decide': true,
      });
      expect(r.fromAgent.agentCode, 'KA1A');
      expect(r.toAgent.nameWithCode, 'Suresh (TS2B)');
      expect(r.customerProfile?.profileCode, 'GN-KA1A-A009');
    });

    test('client rows: customer_code, and the first profile\'s ID as a fallback', () {
      final c = Customer.fromJson(const {
        'id': 5,
        'full_name': 'Priya',
        'phone': '9000000005',
        'status': 'active',
        'customer_code': 'GN-KA1A-A009',
        'profiles': [
          {'id': 9, 'full_name': 'Priya', 'profile_code': 'GN-KA1A-A009', 'paid': true},
        ],
      });
      expect(c.customerCode, 'GN-KA1A-A009');
      expect(c.code, 'GN-KA1A-A009');
      expect(c.idLabel, 'ID GN-KA1A-A009');
      expect(c.allProfiles.single.profileCode, 'GN-KA1A-A009');

      final fallback = Customer.fromJson(const {
        'id': 6,
        'full_name': 'Anil',
        'phone': '9000000006',
        'customer_code': null,
        'profile': {'id': 10, 'full_name': 'Anil', 'profile_code': 'GN-AP2B-B114'},
      });
      expect(fallback.customerCode, isNull);
      expect(fallback.code, 'GN-AP2B-B114');

      final none = Customer.fromJson(const {'id': 7, 'full_name': 'New', 'phone': '9000000007'});
      expect(none.code, isNull);
      expect(none.idLabel, isNull);
    });

    test('delete requests embed the profile with its ID', () {
      final r = ProfileDeleteRequest.fromJson(const {
        'id': 2,
        'status': 'pending',
        'profile': {'id': 9, 'full_name': 'Priya', 'profile_code': 'GN-KA1A-A009'},
        'customer': {'id': 5, 'full_name': 'Priya'},
      });
      expect(r.profile?.profileCode, 'GN-KA1A-A009');
      expect(r.profileName, 'Priya');
    });

    test('shortlist rows: hidden name, null community', () {
      final g = ShortlistGroup.fromJson(const {
        'client_label': 'Ramesh',
        'profiles': [
          {
            'shortlist_id': 1,
            'profile_id': 1042,
            'full_name': 'Profile 1042',
            'gender': 'bride',
            'status': 'active',
            'age': 24,
            'community': null,
            'work_country': null,
            'name_hidden': true,
          },
          {
            'shortlist_id': 2,
            'profile_id': 8,
            'full_name': 'Anusha',
            'gender': 'bride',
            'status': 'active',
            'community': 'Reddy',
          },
        ],
      });
      expect(g.profiles[0].nameHidden, isTrue);
      expect(g.profiles[0].community, isNull);
      expect(g.profiles[0].placeLine, isNull);
      expect(g.profiles[1].nameHidden, isFalse);
      expect(g.profiles[1].community, 'Reddy');
    });

    test('contact and hold request rows: profile_name_hidden, null community', () {
      final c = ContactRequest.fromJson(const {
        'id': 1,
        'profile_id': 1042,
        'profile_name': 'Profile 1042',
        'profile_name_hidden': true,
        'profile_gender': 'groom',
        'profile_community': null,
        'status': 'pending',
      });
      expect(c.profileNameHidden, isTrue);
      expect(c.profileName, 'Profile 1042');
      expect(c.profileCommunity, isNull);

      final h = HoldRequest.fromJson(const {
        'id': 2,
        'profile_id': 1042,
        'profile_name': null,
        'profile_name_hidden': true,
        'profile_community': null,
        'status': 'approved',
      });
      expect(h.profileNameHidden, isTrue);
      expect(h.profileName, 'Profile 1042', reason: 'never "null", never empty');
      expect(h.profileCommunity, isNull);

      // Rows from an older server read as before.
      final old = ContactRequest.fromJson(const {
        'id': 3,
        'profile_id': 4,
        'profile_name': 'Ravi',
        'profile_community': 'Kamma',
        'status': 'approved',
      });
      expect(old.profileNameHidden, isFalse);
      expect(old.profileCommunity, 'Kamma');
    });
  });
}
