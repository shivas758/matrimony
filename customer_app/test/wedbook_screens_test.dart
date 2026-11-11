import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/models/master_data.dart';
import 'package:gandharva/models/profile.dart';
import 'package:gandharva/services/agents_service.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/services/customer_auth_service.dart';
import 'package:gandharva/services/payment_service.dart';
import 'package:gandharva/services/profile_service.dart';
import 'package:gandharva/state/auth_state.dart';
import 'package:gandharva/state/masters_state.dart';
import 'package:gandharva/ui/screens/agent/change_agent_screen.dart';
import 'package:gandharva/ui/screens/auth/phone_screen.dart';
import 'package:gandharva/ui/screens/browse/profile_card.dart';
import 'package:gandharva/ui/screens/browse/profile_detail_screen.dart';
import 'package:gandharva/ui/screens/get_started/get_started_screen.dart';
import 'package:gandharva/ui/screens/more_screen.dart';
import 'package:gandharva/ui/screens/my_profile/my_profile_screen.dart';
import 'package:gandharva/ui/screens/my_profile/privacy_screen.dart';
import 'package:gandharva/ui/screens/my_profile/profile_form_screen.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:gandharva/ui/widgets/app_logo.dart';
import 'package:gandharva/ui/widgets/common.dart';
import 'package:gandharva/ui/widgets/profile_sections.dart';
import 'package:gandharva/ui/widgets/step_header.dart';
import 'package:provider/provider.dart';

import 'guest_mode_test.dart' show guestMeJson;
import 'models_test.dart' show publicProfileJson;
import 'wedbook_test.dart' show mastersJson, maskedProfileJson, ownProfileJson, wedbookMeJson;

/// AuthState with a fixed customer and no network.
class _FakeAuth extends AuthState {
  _FakeAuth(this._c, ApiClient api) : super(api: api, auth: CustomerAuthService(api));

  Customer _c;

  @override
  Customer? get customer => _c;

  @override
  AgentCard? get agent => _c.agent;

  @override
  Future<bool> refresh() async => true;

  @override
  Future<void> refreshCustomer() async {}

  @override
  void setCustomer(Customer customer) {
    _c = customer;
    notifyListeners();
  }
}

/// The profile routes without the network; remembers what was sent.
class _FakeProfiles extends ProfileService {
  _FakeProfiles(super.api, {Map<String, dynamic>? masters, Map<String, dynamic>? own, this.other})
      : _masters = masters ?? mastersJson(),
        _own = own ?? ownProfileJson();

  final Map<String, dynamic> _masters;
  final Map<String, dynamic> _own;

  /// What `detail()` answers (another family's profile).
  final Map<String, dynamic>? other;

  Map<String, dynamic>? created;
  List<String>? createdPhotos;
  Map<String, dynamic>? patched;
  ApiException? failWith;

  @override
  Future<MasterData> masters() async => MasterData.fromJson(_masters);

  @override
  Future<Profile> myProfile(int id) async => Profile.fromJson(_own);

  @override
  Future<Profile> detail(int id) async => Profile.fromJson(other ?? maskedProfileJson());

  @override
  Future<Profile> createProfile(Map<String, dynamic> fields, List<String> photoPaths) async {
    if (failWith != null) throw failWith!;
    created = fields;
    createdPhotos = photoPaths;
    return Profile.fromJson({
      ..._own,
      'full_name': fields['full_name'],
      'paid': false,
      'visibility': 'payment_pending',
      'hidden_fields': [],
      'audience_all': false,
      'audience_communities': [],
    });
  }

  @override
  Future<Profile> updateProfile(int id, Map<String, dynamic> fields) async {
    if (failWith != null) throw failWith!;
    patched = fields;
    return Profile.fromJson({
      ..._own,
      if (fields['full_name'] != null) 'full_name': fields['full_name'],
      if (fields['hidden_fields'] != null) 'hidden_fields': fields['hidden_fields'],
      if (fields['audience_all'] != null) 'audience_all': fields['audience_all'],
      if (fields['audience_community_ids'] != null)
        'audience_communities': [
          for (final id in fields['audience_community_ids'] as List) {'id': id, 'name': 'Community $id'},
        ],
    });
  }
}

/// Linking an agent without the network; remembers what was asked.
class _FakeAgents extends AgentsService {
  _FakeAgents(super.api, this._linked);

  final Customer _linked;
  String? phone;
  String? code;
  int? agentId;
  ApiException? failWith;

  @override
  Future<Customer> linkAgent({String? agentPhone, String? agentCode, int? agentId}) async {
    if (failWith != null) throw failWith!;
    phone = agentPhone;
    code = agentCode;
    this.agentId = agentId;
    return _linked;
  }

  @override
  Future<List<AgentCard>> directory({String? q, int? communityId, String? city}) async => [
        AgentCard.fromJson({
          'id': 8,
          'full_name': 'Anitha',
          'agency_name': 'Anitha Matrimony',
          'city': 'Mysuru',
          'phone': '9000000008',
          'agent_code': 'KA2B',
          'communities': [
            {'id': 1, 'name': 'Kamma'},
          ],
        }),
      ];
}

class _Host {
  _Host(this.customer, {Map<String, dynamic>? masters, Map<String, dynamic>? own, Map<String, dynamic>? other}) {
    profiles = _FakeProfiles(api, masters: masters, own: own, other: other);
    agents = _FakeAgents(api, Customer.fromJson(wedbookMeJson()..['status'] = 'pending'));
  }

  final Customer customer;
  final api = ApiClient();
  late final _FakeProfiles profiles;
  late final _FakeAgents agents;

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<ProfileService>.value(value: profiles),
          Provider<AgentsService>.value(value: agents),
          Provider<PaymentService>.value(value: PaymentService(api)),
          ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profiles)),
          ChangeNotifierProvider<AuthState>(create: (_) => _FakeAuth(customer, api)),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: child),
      );
}

/// A phone-sized surface (360 × 800 dp), or [size] in physical pixels at 3x.
Future<void> _phone(WidgetTester tester, {Size size = const Size(1080, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

/// No widget on screen prints a raw "null".
void _expectNoNullText() {
  expect(find.textContaining('null'), findsNothing);
}

/// A page that opens [open] from a button and shows what came back.
class _Launcher extends StatefulWidget {
  const _Launcher({required this.open});

  final Future<Object?> Function(BuildContext context) open;

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  String _result = 'nothing yet';

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('result: $_result'),
              TextButton(
                onPressed: () async {
                  final r = await widget.open(context);
                  if (mounted) setState(() => _result = r is Profile ? 'profile ${r.fullName}' : '$r');
                },
                child: const Text('open'),
              ),
            ],
          ),
        ),
      );
}

void main() {
  final active = Customer.fromJson(wedbookMeJson());
  final guest = Customer.fromJson(guestMeJson());

  // ================================================================ hidden details as a viewer

  group('Hidden details as a viewer (SPEC §9.18 D)', () {
    testWidgets('browse card of a fully masked profile: neutral name, no empty rows, a lock line', (tester) async {
      await _phone(tester);
      final host = _Host(active);
      final masked = Profile.fromJson(maskedProfileJson());
      await tester.pumpWidget(host.wrap(Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ProfileCard(profile: masked, onTap: () {}),
            const SizedBox(height: 12),
            ProfileCard(profile: Profile.fromJson(publicProfileJson()), onTap: () {}, interested: true),
          ],
        ),
      )));
      expect(find.text('Profile 1042'), findsOneWidget);
      expect(find.text('27 yrs'), findsOneWidget, reason: 'age without the date of birth');
      expect(find.text(S.someDetailsHiddenShort), findsOneWidget, reason: 'only on the masked card');
      expect(find.text('—'), findsNothing, reason: 'a hidden detail leaves no dash row');
      expect(find.text('P1'), findsNothing, reason: 'no initials from the neutral label');
      // The full card next to it is unchanged.
      expect(find.text('Lakshmi Prasanna'), findsOneWidget);
      expect(find.text('Kamma · Chowdary'), findsOneWidget);
      expect(find.text('B.Tech / B.E.'), findsOneWidget);
      expect(find.text('Software Engineer'), findsOneWidget);
      _expectNoNullText();
      expect(tester.takeException(), isNull);
    });

    testWidgets('guest card with a hidden community, job and package shows gender · age only', (tester) async {
      await _phone(tester);
      final host = _Host(guest);
      final bare = Profile.fromJson({
        'id': 74,
        'gender': 'groom',
        'age': 30,
        'community': null,
        'subcaste': null,
        'profession': null,
        'occupation_type': null,
        'income_text': null,
        'primary_photo_url': '/api/customer/photos/31',
        'locked': true,
      });
      await tester.pumpWidget(host.wrap(Scaffold(body: Center(child: GuestProfileCard(profile: bare, onTap: () {})))));
      expect(find.text('Groom · 30 yrs'), findsOneWidget);
      expect(find.text(S.lockedProfile), findsOneWidget);
      expect(find.text('—'), findsNothing);
      _expectNoNullText();
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail sections of a fully masked profile render nothing empty', (tester) async {
      await _phone(tester);
      final host = _Host(active);
      final masked = Profile.fromJson(maskedProfileJson());
      await tester.pumpWidget(host.wrap(Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ProfileChipRow(profile: masked),
            ProfileFactGrid(profile: masked),
            ProfilePublicCards(profile: masked),
          ],
        ),
      )));
      expect(find.text('Bride'), findsOneWidget);
      expect(find.text('27 yrs'), findsWidgets);
      // Only the age row is left of "Personal"; no career / horoscope / about cards.
      expect(find.text(S.personal.toUpperCase()), findsOneWidget);
      expect(find.byType(DetailRow), findsOneWidget);
      expect(find.text(S.educationCareer.toUpperCase()), findsNothing);
      expect(find.text(S.horoscope.toUpperCase()), findsNothing);
      expect(find.text(S.about.toUpperCase()), findsNothing);
      expect(find.byType(FactTile), findsNothing);
      _expectNoNullText();
      expect(tester.takeException(), isNull);
    });

    testWidgets('profile detail: neutral name in the title and the lock note', (tester) async {
      await _phone(tester);
      final host = _Host(active);
      await tester.pumpWidget(host.wrap(const ProfileDetailScreen(profileId: 1042)));
      await tester.pump(); // detail answered
      await tester.pump();
      expect(find.text('Profile 1042'), findsOneWidget);
      expect(find.text(S.someDetailsHidden), findsOneWidget);
      expect(find.text(S.imInterested), findsOneWidget);
      _expectNoNullText();
      expect(tester.takeException(), isNull);
    });

    testWidgets('profile detail of an unmasked profile has no lock note', (tester) async {
      await _phone(tester);
      final host = _Host(active, other: publicProfileJson()..['masked_fields'] = []);
      await tester.pumpWidget(host.wrap(const ProfileDetailScreen(profileId: 41)));
      await tester.pump();
      await tester.pump();
      expect(find.text('Lakshmi Prasanna'), findsOneWidget);
      expect(find.text(S.someDetailsHidden), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ================================================================ IDs and agent code

  group('IDs and agent codes on screen (SPEC §9.18 B / C / G)', () {
    testWidgets('My profile shows Your ID (tap to copy) and the Privacy card with its summary', (tester) async {
      await _phone(tester);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add('${(call.arguments as Map)['text']}');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final host = _Host(active);
      await tester.pumpWidget(host.wrap(const MyProfileScreen(profileId: 77)));
      await tester.pump(); // masters + profile answered
      await tester.pump();
      expect(find.text(S.yourId), findsOneWidget);
      expect(find.text('GN-KA1A-A001'), findsOneWidget);
      expect(find.text(S.privacyTitle), findsOneWidget);
      // income + community (+ subcaste with it) hidden; shown to Kamma + Reddy.
      expect(find.text('3 details hidden · shown to your community + 1 more'), findsOneWidget);

      await tester.tap(find.text('GN-KA1A-A001'));
      await tester.pump();
      expect(copied, ['GN-KA1A-A001']);
      expect(find.text(S.idCopied), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('My profile on an older server: no ID yet, no Privacy entry', (tester) async {
      await _phone(tester);
      final oldMasters = mastersJson()
        ..remove('privacy_fields')
        ..remove('privacy_always_visible');
      final oldOwn = ownProfileJson()
        ..remove('profile_code')
        ..remove('hidden_fields')
        ..remove('audience_all')
        ..remove('audience_communities')
        ..remove('masked_fields');
      final host = _Host(Customer.fromJson(wedbookMeJson()..['profiles'] = []), masters: oldMasters, own: oldOwn);
      await tester.pumpWidget(host.wrap(const MyProfileScreen(profileId: 77)));
      await tester.pump();
      await tester.pump();
      expect(find.text('Priya'), findsWidgets);
      expect(find.text(S.yourId), findsNothing);
      expect(find.text(S.privacyTitle), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('More shows my ID and my agent\'s code', (tester) async {
      await _phone(tester);
      final host = _Host(active);
      await tester.pumpWidget(host.wrap(const MoreScreen()));
      expect(find.text('ID GN-KA1A-A001'), findsOneWidget);
      expect(find.text(S.agentCode), findsOneWidget);
      expect(find.text('KA1A'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Wedbook Matrimony · v3.1.0'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Wedbook Matrimony · v3.1.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('More on a narrow phone (320 dp) with a long status does not overflow', (tester) async {
      await _phone(tester, size: const Size(960, 1800));
      final pending = Customer.fromJson(wedbookMeJson()
        ..['status'] = 'pending'
        ..['full_name'] = 'Venkata Subrahmanya Lakshmi Narasimha Rao'
        ..['customer_code'] = 'GN-KA999ZZ-AA999');
      final host = _Host(pending);
      await tester.pumpWidget(host.wrap(const MoreScreen()));
      expect(find.text('ID GN-KA999ZZ-AA999'), findsOneWidget);
      expect(find.text(S.statusPending), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the agent row (waiting / get-started / directory) shows the agent code', (tester) async {
      await _phone(tester);
      final host = _Host(active);
      await tester.pumpWidget(host.wrap(Scaffold(body: Center(child: AgentRow(agent: active.agent!)))));
      expect(find.text('Agent code KA1A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the directory lists each agent\'s code and its search mentions the code', (tester) async {
      await _phone(tester);
      final host = _Host(guest);
      await tester.pumpWidget(host.wrap(const ChangeAgentScreen(link: true)));
      await tester.pump();
      await tester.pump();
      expect(find.text(S.searchAgents), findsOneWidget);
      expect(S.searchAgents, contains('agent code'));
      await tester.scrollUntilVisible(find.text('Agent code KA2B'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Agent code KA2B'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  // ================================================================ get started: number or code

  group('Get started → choose your agent by number or code (SPEC §9.18 G)', () {
    Future<_Host> open(WidgetTester tester) async {
      await _phone(tester);
      final host = _Host(guest);
      await tester.pumpWidget(host.wrap(const GetStartedScreen()));
      await tester.pump();
      return host;
    }

    testWidgets('the one field is labelled for both and a code links by agent_code', (tester) async {
      final host = await open(tester);
      expect(find.text(S.agentPhoneOrCode), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'ka1a');
      await tester.tap(find.text(S.agentPhoneLink));
      await tester.pump();
      await tester.pump();
      expect(host.agents.code, 'KA1A');
      expect(host.agents.phone, isNull);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('ten digits link by agent_phone', (tester) async {
      final host = await open(tester);
      await tester.enterText(find.byType(TextField).first, '+91 98765 43210');
      await tester.tap(find.text(S.agentPhoneLink));
      await tester.pump();
      await tester.pump();
      expect(host.agents.phone, '9876543210');
      expect(host.agents.code, isNull);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('neither a number nor a code: an inline message, nothing is sent', (tester) async {
      final host = await open(tester);
      await tester.enterText(find.byType(TextField).first, '98765');
      await tester.tap(find.text(S.agentPhoneLink));
      await tester.pump();
      expect(find.text(S.agentPhoneOrCodeInvalid), findsOneWidget);
      expect(host.agents.phone, isNull);
      expect(host.agents.code, isNull);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('the server\'s message is shown when the code is unknown', (tester) async {
      final host = await open(tester);
      host.agents.failWith = ApiException('agent_not_found', 'No agent has the code KA9Z', status: 404);
      await tester.enterText(find.byType(TextField).first, 'KA9Z');
      await tester.tap(find.text(S.agentPhoneLink));
      await tester.pump();
      await tester.pump();
      expect(find.text('No agent has the code KA9Z'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  // ================================================================ the four-step form

  group('Four-step profile form (SPEC §9.18 F)', () {
    Finder field(String label) => find.widgetWithText(TextFormField, label);

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.text(S.next));
      await tester.pumpAndSettle();
    }

    Future<void> pickDob(WidgetTester tester) async {
      await tester.tap(find.text(S.selectDate));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('the step header widget: current, done, upcoming and taps', (tester) async {
      await _phone(tester, size: const Size(960, 1800)); // 320 dp wide
      final taps = <int>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StepHeader(
            labels: const [S.stepPersonalShort, S.stepProfessionalShort, S.stepHoroscopeShort, S.stepFamilyShort],
            current: 1,
            completed: const {0},
            onTap: taps.add,
            canTap: (i) => i <= 2,
          ),
        ),
      ));
      for (final label in [S.stepPersonalShort, S.stepProfessionalShort, S.stepHoroscopeShort, S.stepFamilyShort]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byIcon(Icons.check_rounded), findsOneWidget, reason: 'step 1 is ticked');
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      await tester.tap(find.text(S.stepPersonalShort));
      await tester.tap(find.text(S.stepProfessionalShort)); // the current step: nothing
      await tester.tap(find.text(S.stepHoroscopeShort));
      await tester.tap(find.text(S.stepFamilyShort)); // not allowed by canTap
      expect(taps, [0, 2]);
      expect(tester.takeException(), isNull, reason: 'four labels fit 320 dp');
    });

    testWidgets('registering: Next validates step 1, the steps keep their state, the last step saves', (tester) async {
      await _phone(tester);
      // No account name to start from: the name field is empty.
      final host = _Host(active);
      await tester.pumpWidget(host.wrap(_Launcher(open: (c) => ProfileFormScreen.create(c))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(S.newProfileTitle), findsOneWidget);
      expect(find.text(S.stepOf(1, 4)), findsOneWidget);
      expect(find.text(S.stepPersonal), findsOneWidget);
      expect(find.text(S.back), findsNothing, reason: 'nothing to go back to on step 1');
      expect(find.text(S.save), findsNothing, reason: 'Save in the app bar is for editing');

      // Next with nothing filled in: stays on step 1 and says what is missing.
      await next(tester);
      expect(find.text(S.stepOf(1, 4)), findsOneWidget);
      expect(find.text(S.nameRequired), findsOneWidget);
      expect(find.text(S.dobRequired), findsOneWidget);
      expect(find.text(S.stepHasErrors(S.stepPersonal)), findsOneWidget);

      await tester.enterText(field('${S.fullName} *'), 'Asha Rao');
      await pickDob(tester);
      expect(find.text(S.dobRequired), findsNothing);

      // The agent has one community → it is already chosen. On to step 2.
      await next(tester);
      expect(find.text(S.stepOf(2, 4)), findsOneWidget);
      expect(find.text(S.stepProfessional), findsOneWidget);
      expect(find.text(S.back), findsOneWidget);
      expect(find.text(S.stepHasErrors(S.stepPersonal)), findsNothing);
      await tester.enterText(field(S.salary), '9 LPA');

      await next(tester);
      expect(find.text(S.stepOf(3, 4)), findsOneWidget);
      await tester.enterText(field(S.gothram), 'Kashyapa');

      await next(tester);
      expect(find.text(S.stepOf(4, 4)), findsOneWidget);
      expect(find.text(S.onRequestNote), findsOneWidget, reason: 'the on-request note lives on step 4');
      expect(find.text(S.next), findsNothing);
      expect(find.text(S.saveProfile), findsOneWidget);

      // Back to step 1 through the header: what was typed is still there.
      await tester.tap(find.text(S.stepPersonalShort));
      await tester.pumpAndSettle();
      expect(find.text(S.stepOf(1, 4)), findsOneWidget);
      expect(find.text('Asha Rao'), findsOneWidget);
      // … and forward again to the last step.
      await tester.tap(find.text(S.stepFamilyShort));
      await tester.pumpAndSettle();
      expect(find.text(S.stepOf(4, 4)), findsOneWidget);

      await tester.tap(find.text(S.saveProfile));
      await tester.pumpAndSettle();

      final sent = host.profiles.created!;
      expect(sent['full_name'], 'Asha Rao');
      expect(sent['gender'], 'bride');
      expect(sent['dob'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(sent['community_id'], 1);
      expect(sent['income_text'], '9 LPA');
      expect(sent['gothram'], 'Kashyapa');
      expect(sent['nationality_id'], 1, reason: 'a new profile defaults to India');
      expect(sent.containsKey('hidden_fields'), isFalse, reason: 'privacy is its own screen');

      // Right after the registration the Privacy settings open once.
      expect(find.text(S.privacyTitle), findsOneWidget);
      expect(find.text(S.privacyAfterCreateTitle), findsOneWidget);
      expect(find.text(S.continueLabel), findsOneWidget);
      await tester.tap(find.text(S.skipForNow));
      await tester.pumpAndSettle();
      expect(find.text('result: profile Asha Rao'), findsOneWidget, reason: 'the caller gets the new profile');
      expect(host.profiles.patched, isNull, reason: 'skipping saves nothing');
      expect(tester.takeException(), isNull);
    });

    testWidgets('registering on a server without privacy toggles goes straight back', (tester) async {
      await _phone(tester);
      final host = _Host(active, masters: mastersJson()..remove('privacy_fields'));
      await tester.pumpWidget(host.wrap(_Launcher(open: (c) => ProfileFormScreen.create(c, prefillName: true))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // prefillName: the account's name is already there.
      expect(find.text('Test Guest'), findsOneWidget);
      await pickDob(tester);
      await next(tester);
      await next(tester);
      await next(tester);
      await tester.tap(find.text(S.saveProfile));
      await tester.pumpAndSettle();
      expect(find.text(S.privacyTitle), findsNothing);
      expect(find.text('result: profile Test Guest'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('registering: a step that was not reached yet cannot be jumped to', (tester) async {
      await _phone(tester);
      final host = _Host(active);
      await tester.pumpWidget(host.wrap(const ProfileFormScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.stepHoroscopeShort));
      await tester.pumpAndSettle();
      expect(find.text(S.stepOf(1, 4)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('leaving with unsaved changes asks first; an untouched form just closes', (tester) async {
      await _phone(tester);
      final host = _Host(active);
      await tester.pumpWidget(host.wrap(_Launcher(open: (c) => ProfileFormScreen.create(c))));

      // Untouched (the defaults the form fills in do not count).
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(S.discardTitle), findsNothing);
      expect(find.text('result: null'), findsOneWidget);

      // Touched.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(field('${S.fullName} *'), 'Asha');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(S.discardTitle), findsOneWidget);
      await tester.tap(find.text(S.keepEditing));
      await tester.pumpAndSettle();
      expect(find.text(S.newProfileTitle), findsOneWidget, reason: 'still on the form');
      expect(find.text('Asha'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.discard));
      await tester.pumpAndSettle();
      expect(find.text(S.newProfileTitle), findsNothing);
      expect(host.profiles.created, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('editing: jump anywhere from the header, Save on every step, an error on a hidden step opens it', (tester) async {
      await _phone(tester);
      final host = _Host(active);
      final existing = Profile.fromJson(ownProfileJson());
      await tester.pumpWidget(host.wrap(_Launcher(
        open: (c) => Navigator.of(c).push<Profile>(
          MaterialPageRoute(builder: (_) => ProfileFormScreen(existing: existing)),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(S.editProfileTitle), findsOneWidget);
      expect(find.text(S.save), findsOneWidget, reason: 'Save from step 1');
      expect(find.text('Priya'), findsOneWidget);

      // Straight to step 4, then to step 3 — no Next needed.
      await tester.tap(find.text(S.stepFamilyShort));
      await tester.pumpAndSettle();
      expect(find.text(S.stepOf(4, 4)), findsOneWidget);
      expect(find.text(S.saveChanges), findsOneWidget);
      expect(find.text('Venkat Rao'), findsWidgets, reason: 'the on-request fields are filled in');
      await tester.tap(find.text(S.stepHoroscopeShort));
      await tester.pumpAndSettle();
      expect(find.text(S.stepOf(3, 4)), findsOneWidget);
      expect(find.text(S.birthPlaceNote), findsOneWidget, reason: 'the birth place is marked on request');
      expect(find.text(S.save), findsOneWidget, reason: 'Save from step 3 too');

      // Break step 1, go away, save from step 3 → taken back to step 1.
      await tester.tap(find.text(S.stepPersonalShort));
      await tester.pumpAndSettle();
      await tester.enterText(field('${S.fullName} *'), '');
      await tester.tap(find.text(S.stepHoroscopeShort));
      await tester.pumpAndSettle();
      expect(find.text(S.stepOf(3, 4)), findsOneWidget, reason: 'editing jumps without validating');
      await tester.tap(find.text(S.save));
      await tester.pumpAndSettle();
      expect(find.text(S.stepOf(1, 4)), findsOneWidget);
      expect(find.text(S.nameRequired), findsOneWidget);
      expect(find.text(S.stepHasErrors(S.stepPersonal)), findsOneWidget);
      expect(host.profiles.patched, isNull, reason: 'nothing is sent until it is valid');

      // Fix it and save from step 2.
      await tester.enterText(field('${S.fullName} *'), 'Priya Rao');
      await tester.tap(find.text(S.stepProfessionalShort));
      await tester.pumpAndSettle();
      expect(find.text(S.afterApprovalOnly), findsOneWidget, reason: 'the work place is marked on request');
      await tester.tap(find.text(S.save));
      await tester.pumpAndSettle();
      final sent = host.profiles.patched!;
      expect(sent['full_name'], 'Priya Rao');
      expect(sent['community_id'], 1);
      expect(sent['father_name'], 'Venkat Rao');
      expect(sent['known_language_ids'], isA<List>(), reason: 'JSON on edit');
      expect(sent['has_siblings'], isTrue);
      expect(find.text('result: profile Priya Rao'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a field the server rejects opens the step it lives on', (tester) async {
      await _phone(tester);
      final host = _Host(active);
      host.profiles.failWith = ApiException(
        'validation_failed',
        'Validation failed',
        status: 400,
        fieldErrors: {'income_text': 'Income is too long'},
      );
      await tester.pumpWidget(host.wrap(ProfileFormScreen(existing: Profile.fromJson(ownProfileJson()))));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.save));
      await tester.pumpAndSettle();
      expect(find.text(S.stepOf(2, 4)), findsOneWidget);
      expect(find.text('Income is too long'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('all four steps fit a narrow phone (320 dp) without overflowing', (tester) async {
      await _phone(tester, size: const Size(960, 1700));
      final host = _Host(active);
      await tester.pumpWidget(host.wrap(ProfileFormScreen(existing: Profile.fromJson(ownProfileJson()))));
      await tester.pumpAndSettle();
      for (final label in [S.stepProfessionalShort, S.stepHoroscopeShort, S.stepFamilyShort, S.stepPersonalShort]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
    });
  });

  // ================================================================ privacy screen

  group('Privacy settings (SPEC §9.18 D / E / G)', () {
    Finder toggle(String label) => find.widgetWithText(SwitchListTile, label);
    final list = find.byType(Scrollable).first;

    /// Scrolls the (lazy) list until [target] is built and fully in view.
    Future<void> show(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(target, 150, scrollable: list);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }

    Future<void> flip(WidgetTester tester, String label) async {
      await show(tester, toggle(label));
      await tester.tap(toggle(label));
      await tester.pumpAndSettle();
    }

    Future<_Host> open(WidgetTester tester, {Map<String, dynamic>? own}) async {
      await _phone(tester);
      final host = _Host(active, own: own);
      final profile = Profile.fromJson(own ?? ownProfileJson());
      await tester.pumpWidget(host.wrap(_Launcher(open: (c) => PrivacyScreen.open(c, profile))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return host;
    }

    Map<String, dynamic> everythingShown() => ownProfileJson()
      ..['hidden_fields'] = []
      ..['audience_communities'] = [];

    testWidgets('lists the always-shown details and one switch per masters entry, by section', (tester) async {
      await open(tester);
      expect(find.text(S.privacyIntro), findsOneWidget);
      expect(find.text(S.privacyAlwaysShown.toUpperCase()), findsOneWidget);
      for (final label in ['Main photo', 'Age', 'Gender']) {
        final row = tester.widget<SwitchListTile>(toggle(label));
        expect(row.value, isTrue, reason: label);
        expect(row.onChanged, isNull, reason: '$label is locked on');
      }
      expect(find.text('PERSONAL'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(toggle('Name')).value, isTrue);
      expect(find.text('Your age is always shown'), findsOneWidget, reason: 'the hint from the masters');

      await show(tester, toggle('Community'));
      expect(tester.widget<SwitchListTile>(toggle('Community')).value, isFalse, reason: 'hidden on this profile');
      // The subcaste goes with the community: off and locked.
      await show(tester, toggle('Subcaste'));
      final subcaste = tester.widget<SwitchListTile>(toggle('Subcaste'));
      expect(subcaste.value, isFalse);
      expect(subcaste.onChanged, isNull);
      expect(find.text(S.privacyHiddenWithCommunity), findsOneWidget);

      await show(tester, find.text('PROFESSIONAL'));
      await show(tester, toggle('Income'));
      expect(tester.widget<SwitchListTile>(toggle('Income')).value, isFalse);
      await show(tester, find.text('HOROSCOPE'));
      await show(tester, find.text(S.privacySearchNote));
      await show(tester, find.text(S.audienceOwn));
      await show(tester, find.text(S.audienceSelected));
      // "Selected communities" is this profile's choice: its chips are open,
      // the own community locked in, the other communities selectable.
      await show(tester, find.widgetWithText(FilterChip, 'Kapu'));
      expect(find.widgetWithText(Chip, 'Kamma'), findsOneWidget);
      expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Reddy')).selected, isTrue);
      expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Kapu')).selected, isFalse);
      expect(find.widgetWithText(FilterChip, 'Kamma'), findsNothing, reason: 'the own community cannot be toggled');
      await show(tester, find.text(S.audienceAll));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Save is off until something changes; switches and audience map to the PATCH body', (tester) async {
      final host = await open(tester, own: everythingShown());
      FilledButton saveButton() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, S.save));
      expect(saveButton().onPressed, isNull, reason: 'nothing changed yet');

      // Hide the name and the community (the subcaste follows).
      await flip(tester, 'Name');
      expect(saveButton().onPressed, isNotNull);
      expect(find.text(S.privacyHidden), findsOneWidget);
      await show(tester, toggle('Subcaste'));
      expect(tester.widget<SwitchListTile>(toggle('Subcaste')).onChanged, isNotNull);
      await flip(tester, 'Community');
      await show(tester, toggle('Subcaste'));
      expect(tester.widget<SwitchListTile>(toggle('Subcaste')).value, isFalse);
      expect(tester.widget<SwitchListTile>(toggle('Subcaste')).onChanged, isNull);

      // Selected communities → pick Kapu.
      await show(tester, find.text(S.audienceSelected));
      await tester.tap(find.text(S.audienceSelected));
      await tester.pumpAndSettle();
      await show(tester, find.widgetWithText(FilterChip, 'Kapu'));
      await tester.tap(find.widgetWithText(FilterChip, 'Kapu'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, S.save));
      await tester.pumpAndSettle();
      expect(host.profiles.patched, {
        'hidden_fields': ['name', 'community', 'subcaste'],
        'audience_all': false,
        'audience_community_ids': [3],
      });
      expect(find.text(S.privacySaved), findsOneWidget);
      expect(find.text('result: profile Priya'), findsOneWidget, reason: 'pops the updated profile');
      expect(tester.takeException(), isNull);
    });

    testWidgets('"All communities" sends audience_all and no list', (tester) async {
      final host = await open(tester);
      await show(tester, find.text(S.audienceAll));
      await tester.tap(find.text(S.audienceAll));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Reddy'), findsNothing, reason: 'the chips belong to "Selected"');
      await tester.tap(find.widgetWithText(FilledButton, S.save));
      await tester.pumpAndSettle();
      expect(host.profiles.patched, {
        'hidden_fields': ['community', 'subcaste', 'income'],
        'audience_all': true,
        'audience_community_ids': <int>[],
      });
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 403 shows the server\'s message and keeps the screen', (tester) async {
      final host = await open(tester, own: everythingShown());
      host.profiles.failWith =
          ApiException('account_rejected', 'Your account is not approved — privacy cannot be changed', status: 403);
      await flip(tester, 'Name');
      await tester.tap(find.widgetWithText(FilledButton, S.save));
      await tester.pumpAndSettle();
      expect(find.text('Your account is not approved — privacy cannot be changed'), findsOneWidget);
      expect(find.text(S.privacyTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('back with unsaved changes asks first', (tester) async {
      final host = await open(tester, own: everythingShown());
      // Untouched: just closes.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(S.discardTitle), findsNothing);
      expect(find.text('result: null'), findsOneWidget);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await flip(tester, 'Name');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(S.discardTitle), findsOneWidget);
      await tester.tap(find.text(S.discard));
      await tester.pumpAndSettle();
      expect(find.text(S.privacyTitle), findsNothing);
      expect(host.profiles.patched, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('right after registering: Save and continue once something is switched', (tester) async {
      await _phone(tester);
      final host = _Host(active);
      final profile = Profile.fromJson(everythingShown());
      await tester.pumpWidget(host.wrap(PrivacyScreen(profile: profile, afterCreate: true)));
      await tester.pumpAndSettle();
      expect(find.text(S.privacyAfterCreateTitle), findsOneWidget);
      expect(find.text(S.privacyIntro), findsOneWidget);
      expect(find.text(S.skipForNow), findsOneWidget);
      expect(find.widgetWithText(FilledButton, S.continueLabel), findsOneWidget);
      await flip(tester, 'Name');
      expect(find.widgetWithText(FilledButton, S.saveAndContinue), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a narrow phone (320 dp)', (tester) async {
      await _phone(tester, size: const Size(960, 1700));
      final host = _Host(active);
      await tester.pumpWidget(host.wrap(PrivacyScreen(profile: Profile.fromJson(ownProfileJson()))));
      await tester.pumpAndSettle();
      await show(tester, find.text(S.audienceAll));
      expect(tester.takeException(), isNull);
    });
  });

  // ================================================================ brand

  group('Wedbook Matrimony brand (SPEC §9.18 A)', () {
    testWidgets('the logo assets exist; small sizes use the rings-only tile', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.wine,
          body: Column(
            children: [
              AppLogo(size: 136, onDark: true),
              AppLogo(size: 30, shadow: false),
              AppWordmark(size: 22, showTagline: false),
              AppWordmark(size: 30, onDark: true),
            ],
          ),
        ),
      ));
      final images = tester.widgetList<Image>(find.byType(Image)).map((i) => (i.image as AssetImage).assetName);
      expect(images, ['assets/logo/logo.png', 'assets/logo/logo_mark.png']);
      expect(find.text('Wedbook'), findsNWidgets(2));
      expect(find.text('Matrimony'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('the palette is the logo\'s wine, on the unchanged gold and cream', () {
      expect(AppColors.wine, const Color(0xFF540729));
      expect(AppColors.wineDeep, const Color(0xFF3A0419));
      expect(AppColors.wineLight, const Color(0xFF7A1B45));
      expect(AppColors.gold, const Color(0xFFC8A056));
      expect(AppColors.goldDark, const Color(0xFF94702F));
      expect(AppColors.goldLight, const Color(0xFFF4E6C4));
      expect(AppColors.cream, const Color(0xFFFFF8EE));
      expect(AppColors.creamDeep, const Color(0xFFFBEEDB));

      // WCAG contrast of the text colours on the surfaces they sit on.
      double lum(Color c) {
        double lin(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
      }

      double contrast(Color a, Color b) {
        final hi = math.max(lum(a), lum(b));
        final lo = math.min(lum(a), lum(b));
        return (hi + 0.05) / (lo + 0.05);
      }

      expect(contrast(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrast(AppColors.wine, Colors.white), greaterThan(4.5));
      expect(contrast(AppColors.wine, AppColors.cream), greaterThan(4.5));
      expect(contrast(AppColors.wine, AppColors.goldLight), greaterThan(4.5));
      expect(contrast(AppColors.wine, AppColors.rose), greaterThan(4.5));
      expect(contrast(AppColors.ink, AppColors.rose), greaterThan(4.5));
      expect(contrast(AppColors.wineDeep, AppColors.gold), greaterThan(4.5), reason: 'the gold FAB / guest button');
      expect(contrast(Colors.white, AppColors.wineLight), greaterThan(4.5), reason: 'text on the header gradient');
      expect(contrast(AppColors.goldDark, Colors.white), greaterThan(4.5));
    });

    testWidgets('the phone screen shows the logo on the wine header', (tester) async {
      await _phone(tester);
      final host = _Host(guest);
      await tester.pumpWidget(host.wrap(const PhoneScreen()));
      final logo = tester.widget<AppLogo>(find.byType(AppLogo));
      expect(logo.onDark, isTrue, reason: 'a gold rim on the wine header');
      expect(find.text(S.appIntro), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
