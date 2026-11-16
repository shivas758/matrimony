import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/agent.dart';
import 'package:matrimony_agents/models/customer.dart';
import 'package:matrimony_agents/models/gift_code.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/models/notifications.dart';
import 'package:matrimony_agents/models/profile.dart';
import 'package:matrimony_agents/services/admin_service.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/clients_service.dart';
import 'package:matrimony_agents/services/link_launcher.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/state/auth_state.dart';
import 'package:matrimony_agents/state/home_nav.dart';
import 'package:matrimony_agents/state/masters_state.dart';
import 'package:matrimony_agents/state/notification_routes.dart';
import 'package:matrimony_agents/state/profiles_state.dart';
import 'package:matrimony_agents/ui/screens/admin/admin_agents_screen.dart';
import 'package:matrimony_agents/ui/screens/clients/client_detail_screen.dart';
import 'package:matrimony_agents/ui/screens/gift_codes_screen.dart';
import 'package:matrimony_agents/ui/screens/more_screen.dart';
import 'package:matrimony_agents/ui/screens/notifications_screen.dart';
import 'package:matrimony_agents/ui/screens/profiles/profile_list_screen.dart';
import 'package:matrimony_agents/ui/screens/settings_screen.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:matrimony_agents/ui/widgets/approval_banner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SPEC §9.23 A / B / F — agents work from signup, "approved" at 10 live
/// clients (banner, Settings, admin rows and actions), gift codes (screen,
/// client action, notifications).

// ---------------------------------------------------------------- wire shapes

Map<String, dynamic> _agentJson({
  int id = 4,
  String name = 'Lakshmi Devi',
  bool approved = false,
  int live = 3,
  bool admin = false,
  bool newServer = true,
  int unused = 7,
  int used = 3,
  String status = 'active',
}) =>
    {
      'id': id,
      'full_name': name,
      'agency_name': 'Sri Lakshmi Marriage Bureau',
      'phone': '900000000$id',
      'role': admin ? 'admin' : 'agent',
      'status': status,
      'communities': [
        {'id': 1, 'name': 'Reddy'},
      ],
      'state': {'id': 1, 'name': 'Karnataka', 'code': 'KA'},
      'agent_code': 'KA${id}A',
      'created_at': '2026-11-01T10:00:00Z',
      if (newServer) ...{
        'approved': approved,
        'approved_at': approved ? '2026-11-16T08:00:00Z' : null,
        'live_clients': live,
        'approval_clients': 10,
        'gift_codes': {'unused': unused, 'used': used, 'total': unused + used},
      },
    };

Agent _agent({bool approved = false, int live = 3, bool admin = false, bool newServer = true}) =>
    Agent.fromJson(_agentJson(approved: approved, live: live, admin: admin, newServer: newServer));

const _shareText = 'Your free Wedbook Matrimony gift code: WB-K7M2QX. Install Wedbook Matrimony, '
    'fill in your profile and enter this code when you publish it — no ₹150 fee. '
    'Your agent: Lakshmi Devi (KA4A)';

Map<String, dynamic> _giftCodesJson() => {
      'gift_codes': [
        {
          'id': 1,
          'code': 'WB-K7M2QX',
          'status': 'unused',
          'created_at': '2026-11-16T08:00:00Z',
          'used_at': null,
          'customer': null,
          'profile': null,
          'share_text': _shareText,
        },
        {
          'id': 2,
          'code': 'WB-9PQRST',
          'status': 'unused',
          'created_at': '2026-11-16T08:00:00Z',
          'share_text': 'Your free Wedbook Matrimony gift code: WB-9PQRST.',
        },
        {
          'id': 3,
          'code': 'WB-ABC234',
          'status': 'used',
          'created_at': '2026-11-01T08:00:00Z',
          'used_at': '2026-11-12T09:30:00Z',
          'customer': {'id': 5, 'full_name': 'Priya Venkata Lakshmi'},
          'profile': {'id': 9, 'full_name': 'Priya Venkata Lakshmi'},
          'share_text': 'x',
        },
      ],
      'unused': 2,
      'used': 1,
      'total': 3,
    };

Map<String, dynamic> _clientJson({bool paid = false, String? paidVia}) => {
      'id': 5,
      'full_name': 'Priya Venkata Lakshmi',
      'phone': '9000000005',
      'status': 'active',
      'source': 'form',
      'agent_id': 4,
      'profiles': [
        {
          'id': 9,
          'full_name': 'Priya Venkata Lakshmi',
          'gender': 'bride',
          'age': 25,
          'community': {'id': 1, 'name': 'Reddy'},
          'status': paid ? 'active' : 'hidden',
          'paid': paid,
          'paid_via': paidVia,
          'profile_code': 'GN-KA4A-A009',
        },
      ],
      'created_at': '2026-10-01T10:00:00Z',
    };

// ---------------------------------------------------------------- fakes

class _FakeProfiles extends ProfileService {
  _FakeProfiles() : super(ApiClient());

  int listCalls = 0;

  @override
  Future<MasterData> masters() async => MasterData.fromJson({
        'communities': [
          {'id': 1, 'name': 'Reddy'},
        ],
        'professions': [],
        'educations': [],
        'marital_statuses': [],
        'zodiac_signs': [],
        'nakshatrams': [],
      });

  @override
  Future<ProfilePage> list(Map<String, dynamic> query) async {
    listCalls++;
    return ProfilePage.fromJson({'profiles': [], 'total': 0, 'page': 1});
  }

  @override
  Future<NotificationFeed> notifications() async => NotificationFeed.empty;
}

class _FakeAuthService extends AuthService {
  _FakeAuthService(this.agent) : super(ApiClient());

  Agent agent;
  int meCalls = 0;

  @override
  Future<Agent> me() async {
    meCalls++;
    return agent;
  }

  @override
  Future<AuthResult> signup({
    required String fullName,
    required String phone,
    required String password,
    required List<int> communityIds,
    required String phoneVerificationToken,
    String? agencyName,
    int? stateId,
    bool acceptedTerms = false,
  }) async =>
      AuthResult(token: 't', agent: agent);
}

class _FakeAuth extends AuthState {
  _FakeAuth(this.me) : super(api: ApiClient(), auth: _FakeAuthService(me!), profiles: _FakeProfiles());

  Agent? me;
  NotificationFeed feed = NotificationFeed.empty;

  /// What refreshAgent() switches to (the server's fresh /auth/me).
  Agent? next;
  int refreshes = 0;

  @override
  Agent? get agent => me;

  @override
  bool get isAdmin => me?.isAdmin ?? false;

  @override
  NotificationFeed get notifications => feed;

  @override
  Future<void> refreshAgent() async {
    refreshes++;
    if (next != null) {
      me = next;
      notifyListeners();
    }
  }

  @override
  Future<void> refreshNotifications() async {}

  void become(Agent agent) {
    me = agent;
    notifyListeners();
  }
}

class _FakeAccount extends MyAccountService {
  _FakeAccount() : super(ApiClient());

  Map<String, dynamic> json = _giftCodesJson();
  int calls = 0;

  @override
  Future<GiftCodeList> giftCodes() async {
    calls++;
    return GiftCodeList.fromJson(json);
  }

  @override
  Future<MyCommunities> communities() async => MyCommunities.fromJson({
        'communities': [
          {'id': 1, 'name': 'Reddy'},
        ],
        'requests': [],
      });
}

class _FakeLauncher implements LinkLauncher {
  final launched = <Uri>[];
  bool result = true;

  @override
  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return result;
  }
}

class _FakeAdmin extends AdminService {
  _FakeAdmin(this.rows) : super(ApiClient());

  final List<AdminAgent> rows;
  final approvedFilters = <bool?>[];
  final approvedIds = <int>[];
  final added = <(int, int)>[];
  ApiException? approveError;

  @override
  Future<List<AdminAgent>> agents({String? status, String? q, bool? approved}) async {
    approvedFilters.add(approved);
    return rows.where((r) => approved == null || r.agent.isApproved == approved).toList();
  }

  @override
  Future<Agent?> approveAgent(int id) async {
    if (approveError != null) throw approveError!;
    approvedIds.add(id);
    return null;
  }

  @override
  Future<GiftCodeCounts> addGiftCodes(int id, int count) async {
    added.add((id, count));
    return GiftCodeCounts(unused: count);
  }
}

class _FakeClients extends ClientsService {
  _FakeClients(this.client) : super(ApiClient());

  Customer client;
  Customer? afterGift;
  ApiException? error;
  final used = <(int, int)>[];

  @override
  Future<Customer> detail(int id) async => client;

  @override
  Future<Customer> useGiftCode(int clientId, int profileId, {String? code}) async {
    used.add((clientId, profileId));
    if (error != null) throw error!;
    client = afterGift ?? client;
    return client;
  }
}

class _World {
  _World({Agent? me}) : auth = _FakeAuth(me ?? _agent()) {
    profilesState = ProfilesState(profiles);
  }

  final _FakeAuth auth;
  final profiles = _FakeProfiles();
  late final ProfilesState profilesState;
  final account = _FakeAccount();
  final launcher = _FakeLauncher();

  Widget app(Widget home, {List<Provider<Object>> extra = const []}) => MultiProvider(
        providers: [
          Provider<ApiClient>(create: (_) => ApiClient()),
          Provider<ProfileService>.value(value: profiles),
          Provider<MyAccountService>.value(value: account),
          Provider<LinkLauncher>.value(value: launcher),
          ChangeNotifierProvider<HomeNav>(create: (_) => HomeNav()),
          ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profiles)),
          ChangeNotifierProvider<ProfilesState>.value(value: profilesState),
          ChangeNotifierProvider<AuthState>.value(value: auth),
          ...extra,
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );
}

void _phone(WidgetTester tester, [Size size = const Size(360, 760)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _inDialog(Finder f) => find.descendant(of: find.byType(AlertDialog), matching: f);

void main() {
  // ================================================================ wire

  group('agent wire (SPEC §9.23 A)', () {
    test('/auth/me: approved, approved_at, live_clients, approval_clients, gift_codes', () {
      final a = Agent.fromJson(_agentJson(approved: false, live: 3, unused: 7, used: 3));
      expect(a.knowsApproval, isTrue);
      expect(a.approved, isFalse);
      expect(a.isApproved, isFalse);
      expect(a.needsApproval, isTrue);
      expect(a.approvedAt, isNull);
      expect(a.liveClients, 3);
      expect(a.liveClientCount, 3);
      expect(a.approvalClients, 10);
      expect(a.giftCodes?.unused, 7);
      expect(a.giftCodes?.used, 3);
      expect(a.giftCodes?.total, 10);
      expect(a.knowsGiftCodes, isTrue);

      final b = Agent.fromJson(_agentJson(approved: true, live: 12));
      expect(b.isApproved, isTrue);
      expect(b.needsApproval, isFalse);
      expect(b.approvedAt, DateTime.utc(2026, 11, 16, 8).toLocal());
    });

    test('an older server (no keys): approved, no counts, no gift codes', () {
      final a = Agent.fromJson(_agentJson(newServer: false));
      expect(a.knowsApproval, isFalse);
      expect(a.approved, isTrue);
      expect(a.isApproved, isTrue);
      expect(a.needsApproval, isFalse);
      expect(a.liveClients, isNull);
      expect(a.liveClientCount, 0);
      expect(a.approvalClients, 10);
      expect(a.giftCodes, isNull);
      expect(a.knowsGiftCodes, isFalse);
    });

    test('admins count as approved; defaults for missing counters', () {
      final admin = Agent.fromJson(_agentJson(admin: true, approved: false));
      expect(admin.isApproved, isTrue);
      expect(admin.needsApproval, isFalse);

      final j = _agentJson()
        ..remove('approval_clients')
        ..['gift_codes'] = {'unused': 2, 'used': 1};
      final a = Agent.fromJson(j);
      expect(a.approvalClients, 10);
      expect(a.giftCodes?.total, 3, reason: 'total = unused + used when not sent');
    });

    test('admin rows: approved, live_clients, gift_codes_unused / _used', () {
      final row = AdminAgent.fromJson({
        ..._agentJson(approved: false, live: 4, newServer: true),
        'gift_codes': null,
        'gift_codes_unused': 6,
        'gift_codes_used': 4,
        'profile_count': 12,
      });
      expect(row.agent.knowsApproval, isTrue);
      expect(row.agent.liveClients, 4);
      expect(row.giftCodesUnused, 6);
      expect(row.giftCodesUsed, 4);
      expect(row.profileCount, 12);

      final nested = AdminAgent.fromJson(_agentJson(unused: 2, used: 8));
      expect(nested.giftCodesUnused, 2, reason: 'falls back to the nested counts');

      final old = AdminAgent.fromJson(_agentJson(newServer: false));
      expect(old.giftCodesUnused, isNull);
      expect(old.agent.knowsApproval, isFalse);
    });

    test('admin stats: unapproved_agents (null on an older server)', () {
      expect(AdminStats.fromJson({'unapproved_agents': 5}).unapprovedAgents, 5);
      expect(AdminStats.fromJson(const {}).unapprovedAgents, isNull);
    });

    test('GET /my/gift-codes: rows, counts, share text, who used it', () {
      final list = GiftCodeList.fromJson(_giftCodesJson());
      expect(list.codes.map((c) => c.code), ['WB-K7M2QX', 'WB-9PQRST', 'WB-ABC234']);
      expect(list.unusedCodes.map((c) => c.id), [1, 2]);
      expect(list.usedCodes.single.usedByName, 'Priya Venkata Lakshmi');
      expect(list.usedCodes.single.usedAt, DateTime.utc(2026, 11, 12, 9, 30).toLocal());
      expect(list.counts.unused, 2);
      expect(list.counts.used, 1);
      expect(list.counts.total, 3);
      expect(list.codes.first.shareText, _shareText);
      expect(list.codes.first.customer, isNull);

      // No share text → the bare code; no counts → counted from the rows.
      final bare = GiftCodeList.fromJson({
        'gift_codes': [
          {'id': 7, 'code': 'WB-XYZ234', 'status': 'unused'},
        ],
      });
      expect(bare.codes.single.shareText, 'WB-XYZ234');
      expect(bare.counts.unused, 1);
      expect(bare.counts.total, 1);
    });

    test('client profile rows: paid_via and its label', () {
      final c = Customer.fromJson(_clientJson(paid: true, paidVia: 'gift'));
      expect(c.allProfiles.single.paidVia, 'gift');
      expect(Customer.fromJson(_clientJson()).allProfiles.single.paidVia, isNull);
      expect(S.paidVia('gift'), 'Paid · gift code');
      expect(S.paidVia('cash'), 'Paid · cash');
      expect(S.paidVia('upi'), 'Paid · UPI');
      expect(S.paidVia('mock'), 'Paid · in app');
      expect(S.paidVia('razorpay'), 'Paid · in app');
      expect(S.paidVia('waived'), 'Fee waived');
      expect(S.paidVia(null), S.feePaid);
    });
  });

  // ================================================================ signup

  group('signup goes straight to Home (SPEC §9.23 A)', () {
    test('a fresh signup comes back active: Home is reachable, no waiting screen', () async {
      final service = _FakeAuthService(_agent());
      final auth = AuthState(api: ApiClient(), auth: service, profiles: _FakeProfiles());
      await auth.signup(
        fullName: 'Lakshmi Devi',
        phone: '9000000004',
        password: 'secret1',
        communityIds: const [1],
        phoneVerificationToken: 'verified-token',
        stateId: 1,
        acceptedTerms: true,
      );
      expect(auth.phase, AuthPhase.loggedIn);
      expect(auth.isActive, isTrue);
      expect(auth.agent!.isPending, isFalse);
      expect(auth.canUseApp, isTrue, reason: 'the root shows HomeShell, not PendingScreen');
      expect(auth.agent!.needsApproval, isTrue, reason: 'but not approved yet: the banner shows');
      await pumpEventQueue();
      auth.dispose();
    });

    test('while not approved, the poll also re-reads /auth/me; once approved it stops',
        () async {
      final service = _FakeAuthService(_agent());
      final auth = AuthState(api: ApiClient(), auth: service, profiles: _FakeProfiles());
      await auth.signup(
        fullName: 'Lakshmi Devi',
        phone: '9000000004',
        password: 'secret1',
        communityIds: const [1],
        phoneVerificationToken: 'verified-token',
      );
      await auth.refreshNotifications();
      final calls = service.meCalls;
      expect(calls, greaterThan(0));

      service.agent = _agent(approved: true, live: 10);
      await auth.refreshNotifications();
      expect(auth.agent!.isApproved, isTrue);
      final after = service.meCalls;
      await auth.refreshNotifications();
      expect(service.meCalls, after, reason: 'approved: no extra /auth/me');
      await pumpEventQueue();
      auth.dispose();
    });
  });

  // ================================================================ banner

  group('Not approved yet banner (SPEC §9.23 F)', () {
    test('shown only for a non-admin agent below the mark on a new server', () {
      expect(showsApprovalBanner(_agent()), isTrue);
      expect(showsApprovalBanner(_agent(approved: true, live: 10)), isFalse);
      expect(showsApprovalBanner(_agent(admin: true)), isFalse);
      expect(showsApprovalBanner(_agent(newServer: false)), isFalse);
      expect(showsApprovalBanner(null), isFalse);
    });

    testWidgets('Profiles tab: the text, the progress, Gift codes opens the screen',
        (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const ProfileListScreen()));
      await tester.pumpAndSettle();

      expect(find.text(S.notApprovedTitle), findsOneWidget);
      expect(
        find.text(
          "3 of 10 clients live. Until you have 10, you see only your own profiles and clients, "
          "and families can't find you in the agents list. Give your free gift codes to "
          'families to get started.',
        ),
        findsOneWidget,
      );
      expect(find.text('3/10 clients'), findsOneWidget);

      await _tap(tester, find.widgetWithText(TextButton, S.giftCodes));
      expect(find.byType(GiftCodesScreen), findsOneWidget);
      expect(w.account.calls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('approved, admin or an older server: no banner', (tester) async {
      _phone(tester);
      for (final me in [
        _agent(approved: true, live: 11),
        _agent(admin: true),
        _agent(newServer: false),
      ]) {
        await tester.pumpWidget(_World(me: me).app(const ProfileListScreen()));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('approval-banner')), findsNothing);
        expect(find.text(S.notApprovedTitle), findsNothing);
      }
    });

    testWidgets('becoming approved hides the banner and reloads the list', (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const ProfileListScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('approval-banner')), findsOneWidget);
      final before = w.profiles.listCalls;

      w.auth.become(_agent(approved: true, live: 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('approval-banner')), findsNothing);
      expect(w.profiles.listCalls, before + 1);
    });

    testWidgets('More: the banner and Gift codes with the unused count', (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const MoreScreen()));
      await tester.pump();
      expect(find.byKey(const ValueKey('approval-banner')), findsOneWidget);
      expect(find.widgetWithText(ListTile, S.giftCodes), findsOneWidget);
      expect(find.text(S.unusedCount(7)), findsOneWidget);

      await _tap(tester, find.widgetWithText(ListTile, S.giftCodes));
      expect(find.byType(GiftCodesScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('More against an older server: no banner, no Gift codes', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_World(me: _agent(newServer: false)).app(const MoreScreen()));
      await tester.pump();
      expect(find.byKey(const ValueKey('approval-banner')), findsNothing);
      expect(find.widgetWithText(ListTile, S.giftCodes), findsNothing);
    });
  });

  // ================================================================ settings

  group('Settings: approval status (SPEC §9.23 F)', () {
    testWidgets('"3 / 10 clients" while not approved; "Approved agent ✓" after', (tester) async {
      _phone(tester, const Size(360, 1400));
      final w = _World();
      await tester.pumpWidget(w.app(const SettingsScreen()));
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey('approval-status'));
      await tester.scrollUntilVisible(tile, 200);
      expect(find.descendant(of: tile, matching: find.text('3 / 10 clients')), findsOneWidget);
      expect(find.text(S.approvedAgent), findsNothing);

      w.auth.become(_agent(approved: true, live: 10));
      await tester.pumpAndSettle();
      expect(find.text(S.approvedAgent), findsOneWidget);
      expect(find.text('3 / 10 clients'), findsNothing);
    });

    testWidgets('an older server: no approval line', (tester) async {
      _phone(tester, const Size(360, 1400));
      await tester.pumpWidget(_World(me: _agent(newServer: false)).app(const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('approval-status')), findsNothing);
    });
  });

  // ================================================================ gift codes screen

  group('Gift codes screen (SPEC §9.23 B / F)', () {
    testWidgets('counts, unused codes with Copy and Share, used ones with name and date',
        (tester) async {
      _phone(tester, const Size(360, 1200));
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') copied.add('${(call.arguments as Map)['text']}');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final w = _World(me: Agent.fromJson(_agentJson(unused: 2, used: 1)));
      await tester.pumpWidget(w.app(const GiftCodesScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('gift-unused')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('gift-unused'))).data, '2');
      expect(tester.widget<Text>(find.byKey(const ValueKey('gift-used'))).data, '1');
      expect(find.text('WB-K7M2QX'), findsOneWidget);
      expect(find.text('WB-9PQRST'), findsOneWidget);
      expect(find.text('WB-ABC234'), findsOneWidget);
      // Monospace, so codes read out clearly.
      expect(tester.widget<Text>(find.text('WB-K7M2QX')).style?.fontFamily, 'monospace');
      expect(find.widgetWithText(OutlinedButton, S.copy), findsNWidgets(2));
      expect(find.text('Used by Priya Venkata Lakshmi on 12 Nov 2026'), findsOneWidget);
      expect(w.auth.refreshes, 0, reason: 'counts match /auth/me — nothing to refresh');

      await _tap(tester, find.widgetWithText(OutlinedButton, S.copy).first);
      expect(copied, ['WB-K7M2QX']);
      expect(find.text(S.giftCodeCopied), findsOneWidget);

      await _tap(tester, find.widgetWithText(FilledButton, S.share).first);
      expect(w.launcher.launched, hasLength(1));
      final uri = w.launcher.launched.single;
      expect(uri.host, 'wa.me');
      expect(uri.queryParameters['text'], _shareText);
      expect(tester.takeException(), isNull);
    });

    testWidgets('WhatsApp missing: a message; stale counts refresh /auth/me', (tester) async {
      _phone(tester, const Size(360, 1200));
      final w = _World(); // /auth/me says 7 unused, the list 2
      w.launcher.result = false;
      await tester.pumpWidget(w.app(const GiftCodesScreen()));
      await tester.pumpAndSettle();
      expect(w.auth.refreshes, 1);

      await _tap(tester, find.widgetWithText(FilledButton, S.share).first);
      expect(find.text(S.cannotOpenWhatsApp), findsOneWidget);
    });

    testWidgets('all used: the hint; none at all: the empty state', (tester) async {
      _phone(tester);
      final w = _World();
      w.account.json = {
        'gift_codes': [(_giftCodesJson()['gift_codes'] as List)[2]],
        'unused': 0,
        'used': 1,
        'total': 1,
      };
      await tester.pumpWidget(w.app(const GiftCodesScreen()));
      await tester.pumpAndSettle();
      expect(find.text(S.allCodesUsed), findsOneWidget);
      expect(find.widgetWithText(FilledButton, S.share), findsNothing);

      w.account.json = {'gift_codes': [], 'unused': 0, 'used': 0, 'total': 0};
      await tester.pumpWidget(w.app(const GiftCodesScreen(key: ValueKey('again'))));
      await tester.pumpAndSettle();
      expect(find.text(S.noGiftCodes), findsOneWidget);
    });
  });

  // ================================================================ client detail

  group('Client detail: Use a gift code (SPEC §9.23 B / F)', () {
    Future<_FakeClients> open(WidgetTester tester, _World w, Customer client) async {
      final clients = _FakeClients(client);
      await tester.pumpWidget(
        w.app(
          // A fresh screen each time (the state would survive a re-pump).
          ClientDetailScreen(key: UniqueKey(), customerId: 5),
          extra: [Provider<ClientsService>.value(value: clients)],
        ),
      );
      await tester.pumpAndSettle();
      return clients;
    }

    testWidgets('unpaid: next to Mark paid (cash); confirm with the count; goes live',
        (tester) async {
      _phone(tester, const Size(360, 1000));
      final w = _World();
      final clients = await open(tester, w, Customer.fromJson(_clientJson()));
      clients.afterGift = Customer.fromJson(_clientJson(paid: true, paidVia: 'gift'));

      expect(find.widgetWithText(OutlinedButton, S.markPaidCash), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, S.useGiftCode), findsOneWidget);
      expect(find.text(S.feeNotPaid), findsOneWidget);

      await _tap(tester, find.widgetWithText(OutlinedButton, S.useGiftCode));
      expect(
        _inDialog(find.text('Use one of your free gift codes (7 left)? The profile goes live now.')),
        findsOneWidget,
      );
      await _tap(tester, _inDialog(find.widgetWithText(FilledButton, S.useGiftCodeConfirmLabel)));

      expect(clients.used, [(5, 9)]);
      expect(find.text(S.giftCodeApplied), findsOneWidget);
      expect(w.auth.refreshes, 1, reason: 'my count and live clients changed');
      expect(find.text('Paid · gift code'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, S.useGiftCode), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancel sends nothing; no_gift_codes shows the server message', (tester) async {
      _phone(tester, const Size(360, 1000));
      final w = _World();
      final clients = await open(tester, w, Customer.fromJson(_clientJson()));

      await _tap(tester, find.widgetWithText(OutlinedButton, S.useGiftCode));
      await _tap(tester, _inDialog(find.widgetWithText(TextButton, S.cancel)));
      expect(clients.used, isEmpty);

      clients.error = ApiException(
        'no_gift_codes',
        'You have no gift codes left — ask the admin for more',
        status: 409,
      );
      await _tap(tester, find.widgetWithText(OutlinedButton, S.useGiftCode));
      await _tap(tester, _inDialog(find.widgetWithText(FilledButton, S.useGiftCodeConfirmLabel)));
      expect(clients.used, [(5, 9)]);
      expect(find.text('You have no gift codes left — ask the admin for more'), findsOneWidget);
    });

    testWidgets('0 left: re-reads /auth/me first, then says so without asking', (tester) async {
      _phone(tester, const Size(360, 1000));
      final w = _World(me: Agent.fromJson(_agentJson(unused: 0, used: 10)));
      final clients = await open(tester, w, Customer.fromJson(_clientJson()));

      await _tap(tester, find.widgetWithText(OutlinedButton, S.useGiftCode));
      expect(w.auth.refreshes, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(S.noGiftCodesLeft), findsOneWidget);
      expect(clients.used, isEmpty);
    });

    testWidgets('paid rows say how; an older server shows no gift-code button', (tester) async {
      _phone(tester, const Size(360, 1000));
      await open(tester, _World(), Customer.fromJson(_clientJson(paid: true, paidVia: 'cash')));
      expect(find.text('Paid · cash'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, S.useGiftCode), findsNothing);

      await open(tester, _World(me: _agent(newServer: false)), Customer.fromJson(_clientJson()));
      expect(find.widgetWithText(OutlinedButton, S.markPaidCash), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, S.useGiftCode), findsNothing);
    });
  });

  // ================================================================ admin

  group('Admin → Agents (SPEC §9.23 A / F)', () {
    final rows = [
      AdminAgent.fromJson({
        ..._agentJson(id: 5, name: 'Suresh Kumar', approved: false, live: 3),
        'gift_codes_unused': 7,
        'gift_codes_used': 3,
        'profile_count': 4,
      }),
      AdminAgent.fromJson({
        ..._agentJson(id: 6, name: 'Ravi Teja', approved: true, live: 14),
        'gift_codes_unused': 0,
        'gift_codes_used': 10,
        'profile_count': 30,
      }),
    ];

    Future<_FakeAdmin> open(WidgetTester tester, {bool? initialApproved}) async {
      final admin = _FakeAdmin(rows);
      await tester.pumpWidget(
        _World(me: _agent(admin: true)).app(
          AdminAgentsScreen(initialApproved: initialApproved),
          extra: [Provider<AdminService>.value(value: admin)],
        ),
      );
      await tester.pumpAndSettle();
      return admin;
    }

    testWidgets('rows: "Approved" or "3/10 clients", gift codes left', (tester) async {
      _phone(tester, const Size(400, 1400));
      await open(tester);
      expect(
        find.descendant(of: find.byKey(const ValueKey('approval-5')), matching: find.text('3/10 clients')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const ValueKey('approval-6')), matching: find.text(S.approved)),
        findsOneWidget,
      );
      expect(find.textContaining(S.giftCodesLeft(7)), findsOneWidget);
      expect(find.textContaining(S.giftCodesLeft(0)), findsOneWidget);
      // Approve now only where it is needed; Add gift codes on both.
      expect(find.byKey(const ValueKey('approve-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('approve-6')), findsNothing);
      expect(find.byKey(const ValueKey('add-codes-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-codes-6')), findsOneWidget);
      // The existing actions stay.
      expect(find.widgetWithText(OutlinedButton, S.suspend), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Approve now: confirm, then POST …/approve; 409 shows the message', (tester) async {
      _phone(tester, const Size(400, 1400));
      final admin = await open(tester);

      await _tap(tester, find.byKey(const ValueKey('approve-5')));
      expect(_inDialog(find.text(S.approveAgentTitle('Suresh Kumar'))), findsOneWidget);
      await _tap(tester, _inDialog(find.widgetWithText(FilledButton, S.approveNow)));
      expect(admin.approvedIds, [5]);
      expect(find.text(S.agentApproved('Suresh Kumar')), findsOneWidget);

      admin.approveError =
          ApiException('already_approved', 'This agent is already approved', status: 409);
      await _tap(tester, find.byKey(const ValueKey('approve-5')));
      await _tap(tester, _inDialog(find.widgetWithText(FilledButton, S.approveNow)));
      expect(find.text('This agent is already approved'), findsOneWidget);
    });

    testWidgets('Add gift codes: 1–50 validated, then POST …/gift-codes {count}', (tester) async {
      _phone(tester, const Size(400, 1400));
      final admin = await open(tester);

      await _tap(tester, find.byKey(const ValueKey('add-codes-6')));
      expect(_inDialog(find.text(S.addGiftCodesTitle('Ravi Teja'))), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('gift-count')), '0');
      await _tap(tester, _inDialog(find.widgetWithText(FilledButton, S.add)));
      expect(find.text(S.giftCodesCountInvalid), findsOneWidget);
      expect(admin.added, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('gift-count')), '51');
      await _tap(tester, _inDialog(find.widgetWithText(FilledButton, S.add)));
      expect(admin.added, isEmpty);

      await tester.enterText(find.byKey(const ValueKey('gift-count')), '5');
      await _tap(tester, _inDialog(find.widgetWithText(FilledButton, S.add)));
      expect(admin.added, [(6, 5)]);
      expect(find.text(S.giftCodesAdded(5, 'Ravi Teja')), findsOneWidget);
    });

    testWidgets('filter Approved / Not approved asks the server with ?approved=',
        (tester) async {
      _phone(tester, const Size(400, 1400));
      final admin = await open(tester);
      expect(admin.approvedFilters.last, isNull);

      await _tap(tester, find.byKey(const ValueKey('approved-filter-false')));
      expect(admin.approvedFilters.last, isFalse);
      expect(find.text('Suresh Kumar'), findsOneWidget);
      expect(find.text('Ravi Teja'), findsNothing);
      expect(find.text(S.notApprovedAgents), findsOneWidget, reason: 'the title says so');

      await _tap(tester, find.byKey(const ValueKey('approved-filter-true')));
      expect(admin.approvedFilters.last, isTrue);
      expect(find.text('Ravi Teja'), findsOneWidget);
      expect(find.text('Suresh Kumar'), findsNothing);

      // Tapping the selected filter again shows both.
      await _tap(tester, find.byKey(const ValueKey('approved-filter-true')));
      expect(admin.approvedFilters.last, isNull);
      expect(find.text('Suresh Kumar'), findsOneWidget);
      expect(find.text('Ravi Teja'), findsOneWidget);
    });

    testWidgets('opened on Not approved (Admin home)', (tester) async {
      _phone(tester, const Size(400, 1400));
      final admin = await open(tester, initialApproved: false);
      expect(admin.approvedFilters.single, isFalse);
      expect(find.text('Ravi Teja'), findsNothing);
    });

    testWidgets('an older server: no pill, no Approve now / Add gift codes', (tester) async {
      _phone(tester, const Size(400, 1400));
      final admin = _FakeAdmin([
        AdminAgent.fromJson({..._agentJson(id: 7, newServer: false), 'profile_count': 1}),
      ]);
      await tester.pumpWidget(
        _World(me: _agent(admin: true)).app(
          const AdminAgentsScreen(),
          extra: [Provider<AdminService>.value(value: admin)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('approval-7')), findsNothing);
      expect(find.byKey(const ValueKey('approve-7')), findsNothing);
      expect(find.byKey(const ValueKey('add-codes-7')), findsNothing);
      expect(find.textContaining('gift code'), findsNothing);
    });
  });

  // ================================================================ notifications

  group('notifications: agent_approved, gift_code_used (SPEC §9.23 A)', () {
    NotificationItem item(String type, {String title = 't'}) => NotificationItem.fromJson({
          'type': type,
          'title': title,
          'body': 'b',
          'at': DateTime.now().toUtc().toIso8601String(),
        });

    test('informational, routed to Profiles and to Gift codes', () {
      for (final admin in [false, true]) {
        expect(notificationGroup('agent_approved', isAdmin: admin), NotificationGroup.update);
        expect(notificationGroup('gift_code_used', isAdmin: admin), NotificationGroup.update);
        expect(
          notificationTarget(item('agent_approved'), isAdmin: admin),
          const TabTarget(HomeTab.profiles),
        );
        expect(notificationTarget(item('gift_code_used'), isAdmin: admin), const GiftCodesTarget());
      }
      expect(screenForTarget(const GiftCodesTarget()), isA<GiftCodesScreen>());
      expect(screenForTarget(const TabTarget(HomeTab.profiles)), isNull);
    });

    test('a missing title is empty, never "null"', () {
      final i = NotificationItem.fromJson(const {'type': 'gift_code_used'});
      expect(i.title, '');
      expect(i.body, '');
    });

    testWidgets('the feed shows both; gift_code_used opens Gift codes, agent_approved pops '
        'to Profiles', (tester) async {
      _phone(tester);
      SharedPreferences.setMockInitialValues({});
      final w = _World(me: _agent(approved: true, live: 10));
      w.auth.feed = NotificationFeed.fromJson(<String, dynamic>{
        'badge': 0,
        'items': [
          {
            'type': 'gift_code_used',
            'title': 'Gift code used',
            'body': 'Priya used gift code WB-K7M2QX — their profile is live',
            'at': DateTime.now().toUtc().toIso8601String(),
          },
          {
            'type': 'agent_approved',
            'title': '',
            'body': 'Families can now find you in the agents list',
            'at': DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(),
          },
        ],
        'counts': <String, dynamic>{},
      });

      TabTarget? popped;
      await tester.pumpWidget(w.app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => popped = await Navigator.of(context).push<TabTarget>(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            child: const Text('open'),
          ),
        ),
      )));
      await _tap(tester, find.text('open'));

      expect(find.text(S.needsYourAction.toUpperCase()), findsNothing);
      expect(find.text(S.updates.toUpperCase()), findsOneWidget);
      expect(find.byIcon(Icons.card_giftcard_rounded), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.text(S.agentApprovedTitle), findsOneWidget, reason: 'fallback for an empty title');

      await _tap(tester, find.text('Gift code used'));
      expect(find.byType(GiftCodesScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _tap(tester, find.text(S.agentApprovedTitle));
      expect(popped, const TabTarget(HomeTab.profiles));
      expect(tester.takeException(), isNull);
    });
  });
}
