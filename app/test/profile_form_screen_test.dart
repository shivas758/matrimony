import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/agent.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/models/parsed_profile.dart';
import 'package:matrimony_agents/models/profile.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/state/auth_state.dart';
import 'package:matrimony_agents/state/masters_state.dart';
import 'package:matrimony_agents/ui/screens/auth/choose_state_screen.dart';
import 'package:matrimony_agents/ui/screens/auth/pending_screen.dart';
import 'package:matrimony_agents/ui/screens/profiles/profile_card.dart';
import 'package:matrimony_agents/ui/screens/profiles/profile_detail_screen.dart';
import 'package:matrimony_agents/ui/screens/profiles/profile_form_screen.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:matrimony_agents/ui/widgets/common.dart';
import 'package:matrimony_agents/ui/widgets/step_header.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------- fakes

/// The 22 switchable details of SPEC §9.18 D, as GET /masters serves them.
const _privacyFields = [
  {'key': 'name', 'label': 'Name', 'section': 'personal', 'hint': 'Shown as "Profile 1042" instead'},
  {'key': 'dob', 'label': 'Date of birth', 'section': 'personal', 'hint': 'Age stays visible'},
  {'key': 'marital_status', 'label': 'Marital status', 'section': 'personal', 'hint': null},
  {'key': 'religion', 'label': 'Religion', 'section': 'personal', 'hint': null},
  {'key': 'community', 'label': 'Community', 'section': 'personal', 'hint': 'Also hides the subcaste'},
  {'key': 'subcaste', 'label': 'Subcaste', 'section': 'personal', 'hint': null},
  {'key': 'mother_tongue', 'label': 'Mother tongue', 'section': 'personal', 'hint': null},
  {'key': 'known_languages', 'label': 'Languages known', 'section': 'personal', 'hint': null},
  {'key': 'height', 'label': 'Height', 'section': 'personal', 'hint': null},
  {'key': 'weight', 'label': 'Weight', 'section': 'personal', 'hint': null},
  {'key': 'complexion', 'label': 'Complexion', 'section': 'personal', 'hint': null},
  {'key': 'food_habit', 'label': 'Food habit', 'section': 'personal', 'hint': null},
  {'key': 'nationality', 'label': 'Nationality', 'section': 'personal', 'hint': null},
  {'key': 'about', 'label': 'About', 'section': 'personal', 'hint': null},
  {'key': 'photos', 'label': 'Other photos', 'section': 'personal', 'hint': 'The main photo is always shown'},
  {'key': 'education', 'label': 'Education', 'section': 'professional', 'hint': null},
  {'key': 'profession', 'label': 'Profession', 'section': 'professional', 'hint': null},
  {'key': 'income', 'label': 'Income', 'section': 'professional', 'hint': null},
  {'key': 'work_location', 'label': 'Work country / NRI', 'section': 'professional', 'hint': null},
  {'key': 'star_rasi', 'label': 'Star and rasi', 'section': 'horoscope', 'hint': null},
  {'key': 'gothram', 'label': 'Gothram', 'section': 'horoscope', 'hint': null},
  {'key': 'birth_time', 'label': 'Birth time', 'section': 'horoscope', 'hint': null},
];

MasterData _masters({bool privacy = true}) => MasterData.fromJson({
      'communities': [
        {'id': 1, 'name': 'Reddy'},
        {'id': 2, 'name': 'Kamma'},
        {'id': 3, 'name': 'Kapu'},
      ],
      'subcastes': [
        {'id': 1, 'community_id': 1, 'name': 'Motati'},
      ],
      'professions': [
        {'id': 1, 'name': 'Software Engineer'},
      ],
      'educations': [
        {'id': 1, 'name': 'B.Tech / B.E.'},
      ],
      'marital_statuses': [
        {'id': 1, 'name': 'Never married'},
      ],
      'complexions': [
        {'id': 1, 'name': 'Fair'},
      ],
      'countries': [
        {'id': 1, 'name': 'India'},
        {'id': 2, 'name': 'United States of America'},
      ],
      'religions': [
        {'id': 1, 'name': 'Hindu'},
      ],
      'languages': [
        {'id': 1, 'name': 'Telugu'},
        {'id': 2, 'name': 'English'},
        {'id': 3, 'name': 'Hindi'},
      ],
      'food_habits': [
        {'id': 1, 'name': 'Vegetarian'},
      ],
      'occupation_types': [
        {'id': 1, 'name': 'Private job'},
      ],
      'zodiac_signs': [
        {'id': 1, 'english_name': 'Aries', 'indian_name': 'Mesha'},
      ],
      'nakshatrams': [
        {'id': 1, 'name': 'Ashwini'},
      ],
      'states': [
        {'id': 1, 'name': 'Karnataka', 'code': 'KA', 'active': true, 'sort_order': 1},
        {'id': 2, 'name': 'Andhra Pradesh', 'code': 'AP', 'active': true, 'sort_order': 2},
        {
          'id': 3,
          'name': 'Dadra and Nagar Haveli and Daman and Diu',
          'code': 'DD',
          'active': true,
          'sort_order': 3,
        },
      ],
      if (privacy) 'privacy_fields': _privacyFields,
      if (privacy) 'privacy_always_visible': ['Main photo', 'Age', 'Gender'],
    });

class _FakeProfiles extends ProfileService {
  _FakeProfiles(this.data) : super(ApiClient());

  MasterData data;
  Map<String, dynamic>? created;
  int? updatedId;
  Map<String, dynamic>? updated;
  ApiException? failure;
  Profile? detailProfile;

  /// What the AI import answers; null = the server has no AI key.
  ParsedProfile? aiDraft;

  @override
  Future<MasterData> masters() async => data;

  @override
  Future<bool> aiEnabled() async => aiDraft != null;

  @override
  Future<ParsedProfile> parseBioData({String? filePath, String? text}) async => aiDraft!;

  @override
  Future<Profile> detail(int id) async => detailProfile!;

  @override
  Future<Profile> create(Map<String, dynamic> fields, List<String> photoPaths) async {
    if (failure != null) throw failure!;
    created = Map.of(fields);
    return Profile.fromJson({'id': 99, 'full_name': fields['full_name'], 'gender': fields['gender']});
  }

  @override
  Future<Profile> update(int id, Map<String, dynamic> fields) async {
    if (failure != null) throw failure!;
    updatedId = id;
    updated = Map.of(fields);
    return Profile.fromJson({'id': id, 'full_name': fields['full_name'], 'gender': fields['gender']});
  }

  @override
  Future<void> addPhotos(int profileId, List<String> photoPaths) async {}
}

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(ApiClient());

  int? chosenStateId;
  Agent? answer;
  ApiException? failure;

  @override
  Future<Agent> chooseState(int stateId) async {
    chosenStateId = stateId;
    if (failure != null) throw failure!;
    return answer!;
  }

  @override
  Future<Agent> me() async => answer!;
}

class _FakeAuth extends AuthState {
  _FakeAuth(this.me, ProfileService profiles, {_FakeAuthService? service})
      : super(api: ApiClient(), auth: service ?? _FakeAuthService(), profiles: profiles);

  Agent? me;
  Agent? handedOver;
  bool loggedOut = false;

  @override
  Agent? get agent => me;

  @override
  void updateAgent(Agent agent) {
    handedOver = agent;
    me = agent;
    notifyListeners();
  }

  @override
  Future<void> logout() async => loggedOut = true;
}

Agent _agent({List<int> communities = const [1], bool admin = false, String? code = 'KA1A'}) =>
    Agent.fromJson({
      'id': 4,
      'full_name': 'Lakshmi Devi',
      'phone': '9000000004',
      'role': admin ? 'admin' : 'agent',
      'status': 'active',
      'communities': [
        for (final id in communities) {'id': id, 'name': const {1: 'Reddy', 2: 'Kamma', 3: 'Kapu'}[id]},
      ],
      'state': code == null ? null : {'id': 1, 'name': 'Karnataka', 'code': 'KA'},
      'agent_code': code,
    });

/// A fully filled profile as its uploader gets it back (owner side).
Profile _existing() => Profile.fromJson(const {
      'id': 12,
      'full_name': 'Sravani Venkata Lakshmi Reddy',
      'gender': 'bride',
      'status': 'active',
      'dob': '1998-04-12',
      'age': 27,
      'height_cm': 160,
      'weight_kg': 55,
      'community': {'id': 1, 'name': 'Reddy'},
      'subcaste': {'id': 1, 'name': 'Motati'},
      'religion': {'id': 1, 'name': 'Hindu'},
      'mother_tongue': {'id': 1, 'name': 'Telugu'},
      'known_languages': [
        {'id': 1, 'name': 'Telugu'},
        {'id': 2, 'name': 'English'},
      ],
      'marital_status': {'id': 1, 'name': 'Never married'},
      'complexion': {'id': 1, 'name': 'Fair'},
      'food_habit': {'id': 1, 'name': 'Vegetarian'},
      'nationality': {'id': 1, 'name': 'India'},
      'education': {'id': 1, 'name': 'B.Tech / B.E.'},
      'education_details': 'CSE, JNTU Hyderabad, 2018',
      'education_levels': [
        {
          'level': 'graduation',
          'details': 'B.Tech CSE, JNTU Hyderabad',
          'country': {'id': 2, 'name': 'United States of America'},
        },
      ],
      'profession': {'id': 1, 'name': 'Software Engineer'},
      'profession_details': 'Senior engineer at TCS',
      'occupation_type': {'id': 1, 'name': 'Private job'},
      'income_text': '12 LPA',
      'other_income': 'Rent',
      'work_country': {'id': 2, 'name': 'United States of America'},
      'work_place': 'Edison, New Jersey',
      'is_nri': true,
      'nri_country': {'id': 2, 'name': 'United States of America'},
      'nri_place': 'New Jersey',
      'zodiac': {'id': 1, 'english_name': 'Aries', 'indian_name': 'Mesha'},
      'nakshatram': {'id': 1, 'name': 'Ashwini'},
      'gothram': 'Bharadwaja',
      'birth_time': '22:40',
      'birth_place': 'Guntur',
      'birth_state': 'Andhra Pradesh',
      'birth_country': {'id': 1, 'name': 'India'},
      'about': 'Soft spoken, family oriented.',
      'father_name': 'Venkata Reddy',
      'father_occupation': 'Farmer',
      'father_phone': '9000000001',
      'mother_name': 'Lakshmi',
      'mother_phone': '9000000003',
      'has_siblings': true,
      'siblings_count': 2,
      'elder_sisters': 1,
      'younger_brothers': 1,
      'siblings_details': 'Elder sister married, lives in Bengaluru',
      'family_details': 'Agricultural family from Nalgonda',
      'property_share': 'Equal share',
      'city': 'Nalgonda',
      'state': 'Telangana',
      'contact_name': 'Ramesh',
      'contact_phone': '9000000002',
      'is_mine': true,
      'can_edit': true,
      'can_delete': true,
      'contact_access': 'granted',
      'profile_code': 'GN-KA1A-A012',
      'masked_fields': [],
      'hidden_fields': ['name'],
      'audience_all': false,
      'audience_communities': [
        {'id': 2, 'name': 'Kamma'},
      ],
    });

// ---------------------------------------------------------------- harness

class _Harness {
  _Harness(this.profiles, this.auth);

  final _FakeProfiles profiles;
  final _FakeAuth auth;

  /// What the form route popped with; 'open' while it is still showing.
  Object? popped = 'open';
}

Widget _app(_Harness h, Widget home) => MultiProvider(
      providers: [
        Provider<ApiClient>(create: (_) => ApiClient()),
        Provider<ProfileService>.value(value: h.profiles),
        ChangeNotifierProvider<MastersState>(create: (_) => MastersState(h.profiles)),
        ChangeNotifierProvider<AuthState>.value(value: h.auth),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    );

/// Pumps a page with an "open" button and opens the profile form from it.
Future<_Harness> _openForm(
  WidgetTester tester, {
  Profile? existing,
  MasterData? masters,
  Agent? agent,
  ParsedProfile? aiDraft,
  Size size = const Size(360, 780),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  final profiles = _FakeProfiles(masters ?? _masters())..aiDraft = aiDraft;
  final h = _Harness(profiles, _FakeAuth(agent ?? _agent(), profiles));
  await tester.pumpWidget(
    _app(
      h,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                h.popped = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => ProfileFormScreen(existing: existing)),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return h;
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The tappable field (picker or dropdown) labelled [label].
Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InputDecorator)).first;

Finder _privacySwitch(String key) =>
    find.descendant(of: find.byKey(ValueKey('privacy-$key')), matching: find.byType(Switch));

String _stepLine(int n) => 'STEP $n OF 4';

void main() {
  group('Profile form — four steps (SPEC §9.18 F)', () {
    testWidgets('new profile: Next validates step 1 and shows what is missing', (tester) async {
      // Two communities, so nothing is pre-selected.
      await _openForm(tester, agent: _agent(communities: [1, 2]));
      expect(find.text(_stepLine(1)), findsOneWidget);
      expect(find.text('Personal details'), findsOneWidget);
      // A new profile has only Next on the first step.
      expect(_button('Next'), findsOneWidget);
      expect(_button('Save'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Back'), findsNothing);

      await tester.tap(_button('Next'));
      await tester.pumpAndSettle();

      expect(find.text(_stepLine(1)), findsOneWidget, reason: 'still on step 1');
      expect(find.text(S.fullNameRequired), findsOneWidget);
      expect(find.text(S.dobRequired), findsOneWidget);
      expect(find.text(S.communityRequired), findsOneWidget);
      expect(find.text(S.checkHighlighted), findsOneWidget);
    });

    testWidgets('new profile: walk the steps, input survives, Save sends the privacy fields',
        (tester) async {
      final h = await _openForm(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Full name *'), 'Sravani Reddy');
      await _tap(tester, _field('Date of birth *'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(_button('Next'));
      await tester.pumpAndSettle();
      expect(find.text(_stepLine(2)), findsOneWidget);
      expect(find.text('Professional details'), findsOneWidget);
      expect(find.text(S.onRequestWorkNote), findsOneWidget, reason: 'the on-request note moved here');
      await tester.enterText(find.widgetWithText(TextFormField, 'Income'), '8 LPA');

      await tester.tap(_button('Next'));
      await tester.pumpAndSettle();
      expect(find.text(_stepLine(3)), findsOneWidget);
      expect(find.text(S.onRequestBirthNote), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Gothram'), 'Bharadwaja');

      // Back keeps what was typed on both steps.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
      await tester.pumpAndSettle();
      expect(find.text(_stepLine(2)), findsOneWidget);
      expect(find.text('8 LPA'), findsOneWidget);
      await tester.tap(_button('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Bharadwaja'), findsOneWidget);

      await tester.tap(_button('Next'));
      await tester.pumpAndSettle();
      expect(find.text(_stepLine(4)), findsOneWidget);
      expect(find.text(S.onRequestFamilyNote), findsOneWidget);
      expect(_button('Next'), findsNothing, reason: 'the last step saves');
      expect(find.text(S.profileStatus.toUpperCase()), findsNothing, reason: 'status is edit-only');

      // The Privacy card: always-shown line, sections, switches.
      expect(find.text(S.privacy), findsOneWidget);
      expect(find.textContaining('Main photo, Age, Gender', findRichText: true), findsOneWidget);
      expect(find.text('PERSONAL'), findsOneWidget);
      expect(find.text('PROFESSIONAL'), findsOneWidget);
      expect(find.text('HOROSCOPE'), findsOneWidget);
      expect(tester.widget<Switch>(_privacySwitch('income')).value, isTrue);
      await _tap(tester, _privacySwitch('income'));
      expect(tester.widget<Switch>(_privacySwitch('income')).value, isFalse);
      await _tap(tester, find.byKey(const ValueKey('audience-all')));

      await tester.tap(_button('Save'));
      await tester.pumpAndSettle();

      final sent = h.profiles.created!;
      expect(sent['full_name'], 'Sravani Reddy');
      expect(sent['gender'], 'bride');
      expect(sent['dob'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(sent['community_id'], 1, reason: "the agent's only community is pre-selected");
      expect(sent['work_country_id'], 1, reason: 'a new profile works in India by default');
      expect(sent['income_text'], '8 LPA');
      expect(sent['gothram'], 'Bharadwaja');
      // Multipart create: JSON array strings and "true" / "false".
      expect(sent['hidden_fields'], '["income"]');
      expect(sent['audience_all'], 'true');
      expect(sent['audience_community_ids'], '[]');
      expect(h.popped, isTrue);
    });

    testWidgets('new profile: a step not reached yet cannot be opened from the header',
        (tester) async {
      await _openForm(tester);
      await tester.tap(find.text('Family &\ncontact'));
      await tester.pumpAndSettle();
      expect(find.text(_stepLine(1)), findsOneWidget);
    });

    testWidgets('AI import: fills all steps, says which to check, and opens them from the header',
        (tester) async {
      final h = await _openForm(
        tester,
        aiDraft: ParsedProfile.fromJson(const {
          'draft': {
            'full_name': 'Kiran Kumar',
            'gender': 'groom',
            'dob': '1995-03-02',
            'income_text': '15 LPA',
            'gothram': 'Kashyapa',
            'father_name': 'Raghava Rao',
          },
          'unmatched': {'zodiac': 'Simha', 'father_phone': '98480 xxxxx'},
          'warnings': ['The date of birth was hard to read — please check it.'],
        }),
      );
      expect(find.text(S.fillFromBiodata), findsOneWidget, reason: 'the banner is on step 1');

      await tester.tap(find.text(S.fillFromBiodata));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Name: Kiran Kumar …');
      await tester.pumpAndSettle();
      await tester.tap(_button(S.aiUseText));
      await tester.pumpAndSettle();

      expect(find.text('Kiran Kumar'), findsOneWidget);
      expect(find.text('The date of birth was hard to read — please check it.'), findsOneWidget);
      expect(find.text('${S.aiCheckSteps}Horoscope, Family & contact.'), findsOneWidget);

      // Every step can now be opened to look at the hints.
      await tester.tap(find.text('Horoscope'));
      await tester.pumpAndSettle();
      expect(find.text(_stepLine(3)), findsOneWidget);
      expect(find.text('Kashyapa'), findsOneWidget);
      expect(find.text('${S.aiUnmatchedPrefix}Simha'), findsOneWidget);

      await tester.tap(find.text('Family &\ncontact'));
      await tester.pumpAndSettle();
      expect(find.text('Raghava Rao'), findsOneWidget);
      expect(find.text('${S.aiUnmatchedPrefix}98480 xxxxx'), findsOneWidget);

      // Saving from the last step still checks step 1 — and it is complete.
      await tester.tap(_button('Save'));
      await tester.pumpAndSettle();
      expect(h.profiles.created?['full_name'], 'Kiran Kumar');
      expect(h.profiles.created?['gender'], 'groom');
      expect(h.profiles.created?['dob'], '1995-03-02');
      expect(h.profiles.created?['income_text'], '15 LPA');
      expect(h.popped, isTrue);
    });

    testWidgets('hiding the community switches the subcaste off and locks it', (tester) async {
      await _openForm(tester, existing: _existing());
      await tester.tap(find.text('Family &\ncontact'));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(_privacySwitch('subcaste')).value, isTrue);
      expect(tester.widget<Switch>(_privacySwitch('subcaste')).onChanged, isNotNull);
      await _tap(tester, _privacySwitch('community'));
      expect(tester.widget<Switch>(_privacySwitch('community')).value, isFalse);
      expect(tester.widget<Switch>(_privacySwitch('subcaste')).value, isFalse);
      expect(tester.widget<Switch>(_privacySwitch('subcaste')).onChanged, isNull, reason: 'disabled');
      expect(find.text(S.hiddenWithCommunity), findsOneWidget);

      await _tap(tester, _privacySwitch('community'));
      expect(tester.widget<Switch>(_privacySwitch('subcaste')).value, isTrue);
    });

    testWidgets('edit: any step opens from the header, privacy is pre-filled, Save works anywhere',
        (tester) async {
      final h = await _openForm(tester, existing: _existing());
      // Step 1 of an edit offers Save next to Next.
      expect(_button('Save'), findsOneWidget);
      expect(_button('Next'), findsOneWidget);

      await tester.tap(find.text('Family &\ncontact'));
      await tester.pumpAndSettle();
      expect(find.text(_stepLine(4)), findsOneWidget);
      expect(find.text(S.profileStatus.toUpperCase()), findsOneWidget);

      // Pre-filled from hidden_fields / audience_communities.
      expect(tester.widget<Switch>(_privacySwitch('name')).value, isFalse);
      expect(tester.widget<Switch>(_privacySwitch('dob')).value, isTrue);
      expect(find.widgetWithText(FilterChip, 'Reddy'), findsNothing, reason: 'own community is implicit');
      expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Kamma')).selected, isTrue);
      expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Kapu')).selected, isFalse);
      await _tap(tester, find.widgetWithText(FilterChip, 'Kapu'));

      await tester.tap(find.text('Professional\ndetails'));
      await tester.pumpAndSettle();
      expect(find.text(_stepLine(2)), findsOneWidget);
      expect(find.text('12 LPA'), findsOneWidget);
      // Back, Save and Next share the bar on a middle step.
      expect(find.widgetWithText(OutlinedButton, 'Back'), findsOneWidget);
      expect(_button('Save'), findsOneWidget);
      expect(_button('Next'), findsOneWidget);

      await tester.tap(_button('Save'));
      await tester.pumpAndSettle();

      final sent = h.profiles.updated!;
      expect(h.profiles.updatedId, 12);
      expect(sent['full_name'], 'Sravani Venkata Lakshmi Reddy');
      expect(sent['dob'], '1998-04-12');
      expect(sent['status'], 'active');
      expect(sent['known_language_ids'], [1, 2]);
      // JSON PATCH: real values.
      expect(sent['hidden_fields'], ['name']);
      expect(sent['audience_all'], isFalse);
      expect(sent['audience_community_ids'], [2, 3]);
      expect(h.popped, isTrue);
    });

    testWidgets('Save from another step goes to the step with the error', (tester) async {
      final h = await _openForm(tester, existing: _existing());
      // Break a required field on step 1, then save from step 3.
      await tester.enterText(find.widgetWithText(TextFormField, 'Full name *'), 'S');
      await tester.tap(find.text('Horoscope'));
      await tester.pumpAndSettle();
      expect(find.text(_stepLine(3)), findsOneWidget);

      await tester.tap(_button('Save'));
      await tester.pumpAndSettle();

      expect(find.text(_stepLine(1)), findsOneWidget);
      expect(find.text(S.fullNameRequired), findsOneWidget);
      expect(h.profiles.updated, isNull, reason: 'nothing was sent');
    });

    testWidgets('a field the server refuses takes the agent to its step', (tester) async {
      final h = await _openForm(tester, existing: _existing());
      h.profiles.failure = ApiException(
        'validation_failed',
        'Validation failed',
        status: 400,
        fieldErrors: {'father_phone': 'Phone number is not valid'},
      );
      await tester.tap(_button('Save'));
      await tester.pumpAndSettle();

      expect(find.text(_stepLine(4)), findsOneWidget);
      expect(find.text('Phone number is not valid'), findsOneWidget);
      expect(h.popped, 'open');
    });

    testWidgets('an older server (no privacy_fields): no card, nothing sent', (tester) async {
      final h = await _openForm(tester, existing: _existing(), masters: _masters(privacy: false));
      await tester.tap(find.text('Family &\ncontact'));
      await tester.pumpAndSettle();
      expect(find.text(S.privacy), findsNothing);
      expect(find.text(S.showProfileTo), findsNothing);

      await tester.tap(_button('Save'));
      await tester.pumpAndSettle();
      final sent = h.profiles.updated!;
      expect(sent.containsKey('hidden_fields'), isFalse);
      expect(sent.containsKey('audience_all'), isFalse);
      expect(sent.containsKey('audience_community_ids'), isFalse);
    });

    testWidgets('leaving: an untouched form closes; unsaved changes ask first', (tester) async {
      final h = await _openForm(tester);
      // Untouched (the defaults the app applied do not count).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(h.popped, isNull);
      expect(find.text('open'), findsOneWidget);

      h.popped = 'open';
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Full name *'), 'Anusha');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(S.discardChangesTitle), findsOneWidget);
      await tester.tap(find.text(S.keepEditing));
      await tester.pumpAndSettle();
      expect(h.popped, 'open');
      expect(find.text('Anusha'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.discard));
      await tester.pumpAndSettle();
      expect(h.popped, isNull);
    });

    testWidgets('edit: an unchanged profile closes without asking; a privacy change asks',
        (tester) async {
      final h = await _openForm(tester, existing: _existing());
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(h.popped, isNull);

      h.popped = 'open';
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Family &\ncontact'));
      await tester.pumpAndSettle();
      await _tap(tester, _privacySwitch('income'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(S.discardChangesTitle), findsOneWidget);
    });

    testWidgets('narrow phone, large text: every step lays out without overflow', (tester) async {
      for (final existing in [_existing(), null]) {
        await _openForm(
          tester,
          existing: existing,
          size: const Size(320, 568),
          textScale: 1.3,
          agent: _agent(communities: [1, 2, 3], admin: true),
        );
        if (existing == null) {
          // Reach every step of a new profile through Next.
          await tester.enterText(find.widgetWithText(TextFormField, 'Full name *'), 'Sravani');
          await _tap(tester, _field('Date of birth *'));
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          await _tap(tester, _field('Community *'));
          await tester.tap(find.text('Kamma').last);
          await tester.pumpAndSettle();
        }
        for (var n = 1; n <= 4; n++) {
          expect(find.text(_stepLine(n)), findsOneWidget);
          // Scroll the whole step past the viewport.
          await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -6000));
          await tester.pumpAndSettle();
          if (n < 4) {
            await tester.tap(_button('Next'));
            await tester.pumpAndSettle();
          }
        }
        // "Selected communities" opens the chip picker.
        await _tap(tester, find.byKey(const ValueKey('audience-selected')));
        expect(find.byType(FilterChip), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('StepHeader', () {
    Future<List<int>> pump(WidgetTester tester, {bool Function(int)? canTap, double width = 300}) async {
      final taps = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: StepHeader(
                  labels: const [
                    S.stepPersonalShort,
                    S.stepProfessionalShort,
                    S.stepHoroscopeShort,
                    S.stepFamilyShort,
                  ],
                  current: 1,
                  completed: const {0},
                  onStepTapped: taps.add,
                  canTap: canTap,
                ),
              ),
            ),
          ),
        ),
      );
      return taps;
    }

    testWidgets('numbers the steps, ticks completed ones, fits a very narrow screen',
        (tester) async {
      await pump(tester, width: 260);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget, reason: 'step 1 is completed');
      expect(find.text('1'), findsNothing);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Professional\ndetails'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('taps reach the callback, except on the current step and where canTap says no',
        (tester) async {
      final taps = await pump(tester, canTap: (i) => i != 3);
      await tester.tap(find.text('Personal\ndetails'));
      await tester.tap(find.text('Professional\ndetails')); // current
      await tester.tap(find.text('Horoscope'));
      await tester.tap(find.text('Family &\ncontact')); // not allowed
      expect(taps, [0, 2]);
    });
  });

  group('IDs and hidden details on screen (SPEC §9.18 C / D)', () {
    Widget host(_Harness h, Widget child) => _app(h, Scaffold(body: Center(child: child)));

    _Harness harness() {
      final profiles = _FakeProfiles(_masters());
      return _Harness(profiles, _FakeAuth(_agent(), profiles));
    }

    final masked = Profile.fromJson(const {
      'id': 1042,
      'full_name': 'Profile 1042',
      'gender': 'groom',
      'status': 'active',
      'age': 31,
      'dob': null,
      'community': null,
      'subcaste': null,
      'education': null,
      'profession': null,
      'is_nri': false,
      'known_languages': [],
      'education_levels': [],
      'photos': [],
      'contact_access': 'none',
      'masked_fields': ['name', 'dob', 'community', 'subcaste', 'education', 'profession', 'height'],
    });

    testWidgets('profile card: a masked profile shows no "null"; my upload shows its ID',
        (tester) async {
      final h = harness();
      await tester.pumpWidget(
        host(h, SizedBox(width: 150, height: 242, child: ProfileCard(profile: masked, onTap: () {}))),
      );
      expect(find.text('Profile 1042'), findsOneWidget);
      expect(find.text('31 yrs'), findsOneWidget);
      expect(find.text(S.hiddenByFamily), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('ID '), findsNothing, reason: 'not my upload — no ID');

      await tester.pumpWidget(
        host(h, SizedBox(width: 150, height: 242, child: ProfileCard(profile: _existing(), onTap: () {}))),
      );
      expect(find.text('ID GN-KA1A-A012'), findsOneWidget);
      expect(find.text('Reddy · Motati'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('profile detail: the lock note for a masked profile, no empty rows', (tester) async {
      final h = harness()..profiles.detailProfile = masked;
      await tester.pumpWidget(_app(h, const ProfileDetailScreen(profileId: 1042)));
      await tester.pumpAndSettle();

      expect(find.text(S.maskedNote), findsOneWidget);
      expect(find.text('Profile 1042'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      // Age is always shown; the masked details have no row at all.
      expect(find.widgetWithText(DetailRow, S.age), findsOneWidget);
      expect(find.widgetWithText(DetailRow, S.community), findsNothing);
      expect(find.widgetWithText(DetailRow, S.dob), findsNothing);
      expect(find.widgetWithText(DetailRow, S.education), findsNothing);
      expect(find.byType(IdChip), findsNothing);
    });

    testWidgets('profile detail: my upload shows the ID, tap copies it', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add('${(call.arguments as Map)['text']}');
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      final h = harness()..profiles.detailProfile = _existing();
      await tester.pumpWidget(_app(h, const ProfileDetailScreen(profileId: 12)));
      await tester.pumpAndSettle();

      expect(find.text(S.maskedNote), findsNothing);
      expect(find.text('ID GN-KA1A-A012'), findsOneWidget);
      await tester.tap(find.text('ID GN-KA1A-A012'));
      await tester.pump();
      expect(copied, ['GN-KA1A-A012']);
      expect(find.text(S.idCopied), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('status chips shorten inside a narrow wrap and stay natural in a row',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 180,
                  child: Wrap(
                    children: const [
                      StatusChip(
                        label: 'Agent: Venkata Subrahmanyam (KA999ZZ) · Sri Lakshmi Marriage Bureau',
                        color: Colors.blue,
                        icon: Icons.support_agent_rounded,
                      ),
                      IdChip(code: 'GN-KA999ZZ-ZZ999', copyable: true),
                    ],
                  ),
                ),
                // Unbounded width (a plain Row child): the chip takes its natural size.
                const Row(
                  children: [
                    Expanded(child: Text('name')),
                    StatusChip(label: 'Active', color: Colors.green),
                    AgentCodeChip(code: 'KA1A'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(StatusChip).first).width, lessThanOrEqualTo(180));
      expect(find.text('KA1A'), findsOneWidget);
    });
  });

  group('Choose your State (SPEC §9.18 B)', () {
    Future<(_Harness, _FakeAuthService)> pump(WidgetTester tester, {MasterData? masters}) async {
      final profiles = _FakeProfiles(masters ?? _masters());
      final service = _FakeAuthService();
      final h = _Harness(profiles, _FakeAuth(_agent(code: null), profiles, service: service));
      await tester.pumpWidget(_app(h, const ChooseStateScreen()));
      await tester.pumpAndSettle();
      return (h, service);
    }

    testWidgets('pick a state, confirm, see the code, continue', (tester) async {
      final (h, service) = await pump(tester);
      service.answer = _agent(code: 'KA12B');

      expect(find.text(S.chooseStateTitle), findsOneWidget);
      expect(find.text(S.stateHelper), findsOneWidget);
      expect(find.byTooltip(S.logout), findsOneWidget);
      // Continue is disabled until a state is picked.
      expect(tester.widget<FilledButton>(_button(S.continueLabel)).onPressed, isNull);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('KA — Karnataka').last);
      await tester.pumpAndSettle();
      await tester.tap(_button(S.continueLabel));
      await tester.pumpAndSettle();

      // The confirmation names the state and its prefix.
      expect(find.text(S.confirmStateBody('KA', 'Karnataka')), findsOneWidget);
      expect(service.chosenStateId, isNull, reason: 'nothing is sent before the confirmation');
      await tester.tap(_button(S.confirm));
      await tester.pumpAndSettle();

      expect(service.chosenStateId, 1);
      expect(find.text(S.agentCodeIssued('KA12B')), findsOneWidget);
      expect(find.text('KA12B'), findsOneWidget);
      expect(h.auth.handedOver, isNull, reason: 'Home opens only after Continue');

      await tester.tap(_button(S.continueLabel));
      await tester.pump();
      expect(h.auth.handedOver?.agentCode, 'KA12B');
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final (_, service) = await pump(tester);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AP — Andhra Pradesh').last);
      await tester.pumpAndSettle();
      await tester.tap(_button(S.continueLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.cancel));
      await tester.pumpAndSettle();
      expect(service.chosenStateId, isNull);
      expect(find.text(S.chooseStateTitle), findsOneWidget);
    });

    testWidgets('invalid_state shows the server message and stays on the form', (tester) async {
      final (h, service) = await pump(tester);
      service.failure = ApiException('invalid_state', 'That state is not available', status: 400);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('KA — Karnataka').last);
      await tester.pumpAndSettle();
      await tester.tap(_button(S.continueLabel));
      await tester.pumpAndSettle();
      await tester.tap(_button(S.confirm));
      await tester.pumpAndSettle();
      expect(find.text('That state is not available'), findsOneWidget);
      expect(h.auth.handedOver, isNull);
    });

    testWidgets('no states from the server: a retry, and logout still works', (tester) async {
      final (h, _) = await pump(tester, masters: _masters().copyWithoutStates());
      expect(find.text(S.statesNotLoaded), findsOneWidget);
      expect(find.text(S.retry), findsOneWidget);
      await tester.tap(find.byTooltip(S.logout));
      await tester.pump();
      expect(h.auth.loggedOut, isTrue);
    });

    testWidgets('a long state name fits the dropdown on a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DD — Dadra and Nagar Haveli and Daman and Diu').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('pending screen shows the agent code, tap to copy (SPEC §9.18 G)', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add('${(call.arguments as Map)['text']}');
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final profiles = _FakeProfiles(_masters());
    final pending = Agent.fromJson(const {
      'id': 9,
      'full_name': 'New Agent',
      'phone': '9000000009',
      'status': 'pending',
      'state': {'id': 2, 'name': 'Andhra Pradesh', 'code': 'AP'},
      'agent_code': 'AP7C',
    });
    final h = _Harness(profiles, _FakeAuth(pending, profiles));
    await tester.pumpWidget(_app(h, const PendingScreen()));
    await tester.pump();

    expect(find.text(S.pendingTitle), findsOneWidget);
    expect(find.text(S.yourAgentCode.toUpperCase()), findsOneWidget);
    expect(find.text('AP7C'), findsOneWidget);
    expect(find.text('Andhra Pradesh'), findsOneWidget);
    await tester.tap(find.text('AP7C'));
    await tester.pump();
    expect(copied, ['AP7C']);
    expect(find.text(S.agentCodeCopied), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}

extension on MasterData {
  /// The same masters as an older server sends them: no states.
  MasterData copyWithoutStates() => MasterData(
        communities: communities,
        professions: professions,
        educations: educations,
        maritalStatuses: maritalStatuses,
        zodiacSigns: zodiacSigns,
        nakshatrams: nakshatrams,
      );
}
