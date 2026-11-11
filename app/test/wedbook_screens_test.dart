import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/agent.dart';
import 'package:matrimony_agents/models/agent_change.dart';
import 'package:matrimony_agents/models/customer.dart';
import 'package:matrimony_agents/models/interest.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/services/admin_service.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/clients_service.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/state/auth_state.dart';
import 'package:matrimony_agents/state/home_nav.dart';
import 'package:matrimony_agents/state/masters_state.dart';
import 'package:matrimony_agents/ui/screens/admin/admin_agents_screen.dart';
import 'package:matrimony_agents/ui/screens/auth/login_screen.dart';
import 'package:matrimony_agents/ui/screens/auth/signup_screen.dart';
import 'package:matrimony_agents/ui/screens/clients/client_detail_screen.dart';
import 'package:matrimony_agents/ui/screens/clients/clients_screen.dart';
import 'package:matrimony_agents/ui/screens/more_screen.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:matrimony_agents/ui/widgets/common.dart';
import 'package:provider/provider.dart';

/// Screen-level checks for release 3.0.0 (SPEC §9.18 G): the rebrand, the
/// State dropdown on signup, agent codes on the admin and client screens.

class _FakeProfiles extends ProfileService {
  _FakeProfiles(this.data) : super(ApiClient());

  final MasterData data;

  @override
  Future<MasterData> masters() async => data;
}

class _FakeAuthService extends AuthService {
  _FakeAuthService() : super(ApiClient());

  @override
  Future<OtpSendResult> sendSignupOtp(String phone) async =>
      const OtpSendResult(retryAfter: 0, expiresIn: 300, mock: true, mockCode: '123456');

  @override
  Future<String> verifySignupOtp(String phone, String code) async => 'verified-token';
}

class _FakeAuth extends AuthState {
  _FakeAuth(this.me, ProfileService profiles, AuthService service)
      : super(api: ApiClient(), auth: service, profiles: profiles);

  Agent? me;
  Map<String, Object?>? signedUp;

  @override
  Agent? get agent => me;

  @override
  Future<void> signup({
    required String fullName,
    required String phone,
    required String password,
    required List<int> communityIds,
    required String phoneVerificationToken,
    String? agencyName,
    int? stateId,
  }) async {
    signedUp = {
      'full_name': fullName,
      'phone': phone,
      'community_ids': communityIds,
      'token': phoneVerificationToken,
      'state_id': stateId,
    };
  }
}

class _FakeAdmin extends AdminService {
  _FakeAdmin(this.rows) : super(ApiClient());

  final List<AdminAgent> rows;
  final queries = <String?>[];

  @override
  Future<List<AdminAgent>> agents({String? status, String? q}) async {
    queries.add(q);
    final needle = (q ?? '').toLowerCase();
    return rows
        .where((r) =>
            needle.isEmpty ||
            r.agent.fullName.toLowerCase().contains(needle) ||
            (r.agent.agentCode ?? '').toLowerCase().contains(needle))
        .toList();
  }
}

class _FakeClients extends ClientsService {
  _FakeClients(this.client) : super(ApiClient());

  final Customer client;

  @override
  Future<Customer> detail(int id) async => client;
}

MasterData _masters({bool states = true}) => MasterData.fromJson({
      'communities': [
        {'id': 1, 'name': 'Reddy'},
        {'id': 2, 'name': 'Kamma'},
      ],
      'professions': [],
      'educations': [],
      'marital_statuses': [],
      'zodiac_signs': [],
      'nakshatrams': [],
      if (states)
        'states': [
          {'id': 1, 'name': 'Karnataka', 'code': 'KA', 'active': true, 'sort_order': 1},
          {'id': 2, 'name': 'Andhra Pradesh', 'code': 'AP', 'active': true, 'sort_order': 2},
          {'id': 3, 'name': 'Telangana', 'code': 'TS', 'active': true, 'sort_order': 3},
        ],
    });

Agent _me({bool admin = false}) => Agent.fromJson({
      'id': 4,
      'full_name': 'Lakshmi Devi',
      'agency_name': 'Sri Lakshmi Marriage Bureau',
      'phone': '9000000004',
      'role': admin ? 'admin' : 'agent',
      'status': 'active',
      'communities': [
        {'id': 1, 'name': 'Reddy'},
      ],
      'state': {'id': 1, 'name': 'Karnataka', 'code': 'KA'},
      'agent_code': 'KA1A',
    });

class _World {
  _World({MasterData? masters, Agent? me}) : profiles = _FakeProfiles(masters ?? _masters()) {
    auth = _FakeAuth(me ?? _me(), profiles, authService);
  }

  final _FakeProfiles profiles;
  final authService = _FakeAuthService();
  late final _FakeAuth auth;

  Widget app(Widget home, {List<Provider<Object>> extra = const []}) => MultiProvider(
        providers: [
          Provider<ApiClient>(create: (_) => ApiClient()),
          Provider<ProfileService>.value(value: profiles),
          Provider<AuthService>.value(value: authService),
          ChangeNotifierProvider<HomeNav>(create: (_) => HomeNav()),
          ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profiles)),
          ChangeNotifierProvider<AuthState>.value(value: auth),
          ...extra,
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );
}

void _phone(WidgetTester tester, [Size size = const Size(320, 640)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('rebrand (SPEC §9.18 A)', () {
    testWidgets('login shows the rings, "Wedbook" and "AGENT" — on a narrow phone too',
        (tester) async {
      _phone(tester, const Size(320, 568));
      await tester.pumpWidget(_World().app(const LoginScreen()));
      await tester.pump();

      expect(find.text('Wedbook'), findsOneWidget);
      expect(find.text('AGENT'), findsOneWidget);
      expect(find.textContaining('Mediator'), findsNothing);
      expect(find.textContaining('MATRIMONY PARTNERS'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.endsWith('logo_mark.png'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('More: the agent code chip and "Wedbook Agent · v3.1.0"', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_World().app(const MoreScreen()));
      await tester.pump();

      expect(find.text('KA1A'), findsOneWidget);
      expect(find.byType(AgentCodeChip), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Wedbook Agent · v3.1.0'), 200);
      expect(find.text('Wedbook Agent · v3.1.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('signup State dropdown (SPEC §9.18 B)', () {
    Future<void> reachDetails(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(TextFormField, S.phone), '9000000001');
      await _tap(tester, _button(S.sendOtp));
      await tester.enterText(find.widgetWithText(TextFormField, S.otpCode), '123456');
      await _tap(tester, _button(S.verifyOtp));
      expect(find.text(S.detailsStepTitle), findsOneWidget);
    }

    Future<void> fillDetails(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(TextFormField, S.fullName), 'New Agent');
      await tester.enterText(find.widgetWithText(TextFormField, S.password), 'secret1');
      await tester.enterText(find.widgetWithText(TextFormField, S.confirmPassword), 'secret1');
      await _tap(tester, find.widgetWithText(FilterChip, 'Reddy'));
    }

    testWidgets('the state is required and travels as state_id', (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const SignupScreen()));
      await tester.pumpAndSettle();
      await reachDetails(tester);

      expect(find.text(S.state), findsOneWidget);
      expect(find.text(S.stateHelper), findsOneWidget);
      await fillDetails(tester);

      // Without a state the form does not submit.
      await _tap(tester, _button(S.signup));
      expect(find.text(S.stateRequired), findsOneWidget);
      expect(w.auth.signedUp, isNull);

      await _tap(tester, find.byType(DropdownButtonFormField<int>));
      await tester.tap(find.text('TS — Telangana').last);
      await tester.pumpAndSettle();
      await _tap(tester, _button(S.signup));

      expect(w.auth.signedUp?['state_id'], 3);
      expect(w.auth.signedUp?['community_ids'], [1]);
      expect(w.auth.signedUp?['token'], 'verified-token');
      expect(tester.takeException(), isNull);
    });

    testWidgets('an older server sends no states: no dropdown, signup still works', (tester) async {
      _phone(tester);
      final w = _World(masters: _masters(states: false));
      await tester.pumpWidget(w.app(const SignupScreen()));
      await tester.pumpAndSettle();
      await reachDetails(tester);

      expect(find.text(S.state), findsNothing);
      await fillDetails(tester);
      await _tap(tester, _button(S.signup));
      expect(w.auth.signedUp, isNotNull);
      expect(w.auth.signedUp?['state_id'], isNull);
    });
  });

  group('admin agents (SPEC §9.18 G)', () {
    final rows = [
      AdminAgent.fromJson(const {
        'id': 4,
        'full_name': 'Venkata Subrahmanyam Sharma',
        'agency_name': 'Sri Venkateswara Marriage Bureau',
        'phone': '9000000004',
        'status': 'active',
        'communities': [
          {'id': 1, 'name': 'Reddy'},
        ],
        'state': {'id': 3, 'name': 'Dadra and Nagar Haveli and Daman and Diu', 'code': 'DD'},
        'agent_code': 'DD999ZZ',
        'profile_count': 12,
      }),
      AdminAgent.fromJson(const {
        'id': 5,
        'full_name': 'Old Agent',
        'phone': '9000000005',
        'status': 'active',
        'communities': [],
        'state': null,
        'agent_code': null,
        'profile_count': 0,
      }),
    ];

    testWidgets('rows show the code chip and the state; search asks the server', (tester) async {
      _phone(tester);
      final w = _World(me: _me(admin: true));
      final admin = _FakeAdmin(rows);
      await tester.pumpWidget(
        w.app(const AdminAgentsScreen(), extra: [Provider<AdminService>.value(value: admin)]),
      );
      await tester.pumpAndSettle();

      expect(find.text(S.searchAgentsAdmin), findsOneWidget);
      expect(find.text('DD999ZZ'), findsOneWidget);
      expect(find.text('Dadra and Nagar Haveli and Daman and Diu'), findsOneWidget);
      expect(find.byType(AgentCodeChip), findsOneWidget, reason: 'the old agent has no code yet');
      expect(find.text('Old Agent'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'dd999');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(admin.queries.last, 'dd999');
      expect(find.text('Old Agent'), findsNothing);
      expect(find.text('DD999ZZ'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text(S.noAgentsFound), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('clients: IDs and the other agent\'s code (SPEC §9.18 C / G)', () {
    final interest = Interest.fromJson(const {
      'id': 5,
      'status': 'pending',
      'customer': {'id': 2, 'full_name': 'Priya Venkata Lakshmi', 'agent_id': 8},
      'profile': {
        'id': 7,
        'full_name': 'Ravi Teja Subrahmanyam Chowdary',
        'gender': 'groom',
        'age': 29,
        'community': {'id': 1, 'name': 'Reddy'},
        'profile_code': 'GN-KA1A-A007',
      },
      'customer_profile': {
        'id': 1042,
        'full_name': 'Profile 1042',
        'gender': 'bride',
        'age': 25,
        'community': null,
        'name_hidden': true,
      },
      'customer_agent': {
        'id': 8,
        'full_name': 'Suresh Kumar Venkateswarlu',
        'agency_name': 'Om Sai Ram Marriage Bureau',
        'phone': '9000000008',
        'agent_code': 'AP999ZZ',
      },
      'can_decide': true,
    });

    final transfer = AgentChangeRequest.fromJson(const {
      'id': 3,
      'status': 'pending',
      'box': 'outgoing',
      'from_agent': {'id': 4, 'full_name': 'Lakshmi Devi', 'agent_code': 'KA1A'},
      'to_agent': {
        'id': 8,
        'full_name': 'Suresh',
        'agency_name': 'Om Bureau',
        'city': 'Vijayawada',
        'agent_code': 'AP3C',
      },
      'customer': {'id': 5, 'full_name': 'Priya', 'phone': '9000000005'},
      'can_decide': true,
    });

    testWidgets('interest card: IDs on the summaries, the agent\'s code beside the name',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        _World().app(
          Scaffold(
            body: ListView(
              children: [
                InterestCard(interest: interest, busy: false, onAccept: () {}, onDecline: () {}),
                TransferTile(request: transfer, busy: false, onApprove: () {}, onReject: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ID GN-KA1A-A007'), findsOneWidget, reason: 'my upload carries its ID');
      expect(find.text('Profile 1042'), findsOneWidget);
      expect(find.text('Bride · 25 yrs'), findsOneWidget, reason: 'a hidden community leaves no gap');
      expect(find.text('AP999ZZ'), findsOneWidget);
      expect(find.byType(AgentCodeChip), findsOneWidget);
      expect(
        find.textContaining('Suresh (AP3C), Om Bureau', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('null'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('client detail: the customer ID on the header and on the profile row',
        (tester) async {
      _phone(tester);
      final client = Customer.fromJson(const {
        'id': 5,
        'full_name': 'Priya Venkata Lakshmi',
        'phone': '9000000005',
        'status': 'active',
        'source': 'app',
        'customer_code': 'GN-KA1A-A009',
        'agent_id': 4,
        'agent': {
          'id': 4,
          'full_name': 'Lakshmi Devi',
          'agency_name': 'Sri Lakshmi Marriage Bureau',
          'agent_code': 'KA1A',
        },
        'profiles': [
          {
            'id': 9,
            'full_name': 'Priya Venkata Lakshmi',
            'gender': 'bride',
            'age': 25,
            'community': {'id': 1, 'name': 'Reddy'},
            'status': 'active',
            'paid': true,
            'profile_code': 'GN-KA1A-A009',
          },
        ],
        'created_at': '2026-10-01T10:00:00Z',
      });
      await tester.pumpWidget(
        _World().app(
          const ClientDetailScreen(customerId: 5),
          extra: [Provider<ClientsService>.value(value: _FakeClients(client))],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IdChip), findsOneWidget);
      expect(find.text('ID GN-KA1A-A009'), findsNWidgets(2), reason: 'header chip + profile row');
      expect(find.textContaining('Lakshmi Devi (KA1A)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
