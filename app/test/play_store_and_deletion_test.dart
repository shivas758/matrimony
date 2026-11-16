import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/config.dart';
import 'package:matrimony_agents/models/agent.dart';
import 'package:matrimony_agents/models/deletion_request.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/models/notifications.dart';
import 'package:matrimony_agents/services/admin_service.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/link_launcher.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/state/auth_state.dart';
import 'package:matrimony_agents/state/home_nav.dart';
import 'package:matrimony_agents/state/masters_state.dart';
import 'package:matrimony_agents/state/notification_routes.dart';
import 'package:matrimony_agents/state/store_config.dart';
import 'package:matrimony_agents/ui/screens/admin/admin_deletion_requests_screen.dart';
import 'package:matrimony_agents/ui/screens/admin/admin_home_screen.dart';
import 'package:matrimony_agents/ui/screens/auth/pending_screen.dart';
import 'package:matrimony_agents/ui/screens/auth/signup_screen.dart';
import 'package:matrimony_agents/ui/screens/community_payment_screen.dart';
import 'package:matrimony_agents/ui/screens/more_screen.dart';
import 'package:matrimony_agents/ui/screens/notifications_screen.dart';
import 'package:matrimony_agents/ui/screens/settings_screen.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:matrimony_agents/ui/widgets/upi_payment.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SPEC §9.20 F (account deletion) and G (Play Store build: no non-Google
/// payment).

// ---------------------------------------------------------------- wire shapes

const _upi = {
  'vpa': 'wedbook@ybl',
  'name': 'Wedbook',
  'amount_inr': 1000,
  'reference': 'WB12',
  'uri': 'upi://pay?pa=wedbook%40ybl&pn=Wedbook&am=1000.00&cu=INR&tn=Wedbook%20WB12',
};

Map<String, dynamic> _feeRequest(String paymentStatus, {String? reason}) => {
  'id': 31,
  'status': 'pending',
  'community_id': 4,
  'community_name': 'Brahmin',
  'fee_inr': 1000,
  'payment': {
    'id': 12,
    'status': paymentStatus,
    'utr': paymentStatus == 'created' ? null : '111111111111',
    'reject_reason': reason,
    'upi': _upi,
  },
};

const _three = [
  {'id': 1, 'name': 'Reddy'},
  {'id': 2, 'name': 'Kamma'},
  {'id': 3, 'name': 'Kapu'},
];

MyCommunities _mine(
  List<Map<String, dynamic>> requests, {
  List<Map<String, dynamic>> communities = _three,
}) => MyCommunities.fromJson({
  'communities': communities,
  'requests': requests,
  'free_limit': 3,
  'extra_fee_inr': 1000,
});

Map<String, dynamic> _deletion({
  int id = 7,
  String app = 'customer',
  String status = 'pending',
  bool exists = true,
  String? note,
}) => {
  'id': id,
  'app': app,
  'phone': '9876543210',
  'full_name': 'Sravani Reddy',
  'reason': 'Marriage fixed, please remove my details',
  'status': status,
  'note': note,
  'created_at': '2026-11-13T08:00:00.000Z',
  'handled_at': status == 'pending' ? null : '2026-11-13T12:00:00.000Z',
  'account_exists': exists,
};

// ---------------------------------------------------------------- fakes

class _FakeProfiles extends ProfileService {
  _FakeProfiles() : super(ApiClient());

  @override
  Future<MasterData> masters() async => MasterData.fromJson({
    'communities': [
      ..._three,
      {'id': 4, 'name': 'Brahmin'},
    ],
    'professions': [],
    'educations': [],
    'marital_statuses': [],
    'zodiac_signs': [],
    'nakshatrams': [],
  });
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
  NotificationFeed feed = NotificationFeed.empty;

  @override
  Agent? get agent => me;

  @override
  bool get isAdmin => me?.isAdmin ?? false;

  @override
  NotificationFeed get notifications => feed;

  @override
  Future<void> refreshAgent() async {}
}

class _FakeAccount extends MyAccountService {
  _FakeAccount(this.state) : super(ApiClient());

  MyCommunities state;
  CommunityRequest? nextRequest;
  final requested = <int>[];

  @override
  Future<MyCommunities> communities() async => state;

  @override
  Future<CommunityRequest> requestCommunity(int communityId) async {
    requested.add(communityId);
    return nextRequest!;
  }
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
  _FakeAdmin() : super(ApiClient());

  Map<String, List<DeletionRequest>> byStatus = {};
  AdminStats statsResult = AdminStats.fromJson(const {});
  final statuses = <String>[];
  final completed = <int>[];
  final rejected = <(int, String)>[];
  ApiException? completeError;

  @override
  Future<AdminStats> stats() async => statsResult;

  @override
  Future<List<DeletionRequest>> deletionRequests({String status = 'pending'}) async {
    statuses.add(status);
    return [...?byStatus[status]];
  }

  @override
  Future<DeletionDecision> completeDeletion(int id) async {
    completed.add(id);
    if (completeError != null) throw completeError!;
    byStatus['pending']?.removeWhere((r) => r.id == id);
    return DeletionDecision.fromJson({
      'id': id,
      'status': 'done',
      'note': 'Customer account, 1 profile and 4 photos deleted',
      'handled_at': '2026-11-13T12:00:00Z',
    });
  }

  @override
  Future<void> rejectDeletion(int id, String note) async {
    rejected.add((id, note));
    byStatus['pending']?.removeWhere((r) => r.id == id);
  }
}

Agent _agent({bool admin = false, String status = 'active'}) => Agent.fromJson({
  'id': 4,
  'full_name': 'Lakshmi Devi',
  'agency_name': 'Sri Lakshmi Marriage Bureau',
  'phone': '9000000004',
  'role': admin ? 'admin' : 'agent',
  'status': status,
  'communities': _three,
  'state': {'id': 1, 'name': 'Telangana', 'code': 'TS'},
  'agent_code': 'TS1A',
});

class _World {
  _World({bool admin = false, String status = 'active', MyCommunities? account, this.play})
    : account = _FakeAccount(account ?? _mine(const [])) {
    auth = _FakeAuth(_agent(admin: admin, status: status), profiles, authService);
    masters = MastersState(profiles);
  }

  /// null: no StoreConfig provider at all (the build flag decides).
  final bool? play;
  final profiles = _FakeProfiles();
  final authService = _FakeAuthService();
  final launcher = _FakeLauncher();
  final admin = _FakeAdmin();
  final _FakeAccount account;
  late final _FakeAuth auth;
  late final MastersState masters;

  Widget app(Widget home) => MultiProvider(
    providers: [
      Provider<ApiClient>(create: (_) => ApiClient()),
      Provider<ProfileService>.value(value: profiles),
      Provider<AuthService>.value(value: authService),
      Provider<MyAccountService>.value(value: account),
      Provider<AdminService>.value(value: admin),
      Provider<LinkLauncher>.value(value: launcher),
      if (play != null) Provider<StoreConfig>.value(value: StoreConfig(playStore: play!)),
      ChangeNotifierProvider<HomeNav>(create: (_) => HomeNav()),
      ChangeNotifierProvider<MastersState>.value(value: masters),
      ChangeNotifierProvider<AuthState>.value(value: auth),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );
}

void _phone(WidgetTester tester, [Size size = const Size(360, 720)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

Finder _inDialog(Finder matching) =>
    find.descendant(of: find.byType(AlertDialog), matching: matching);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  // ---------------------------------------------------------------- G: Play Store build

  group('Play Store build (SPEC §9.20 G)', () {
    testWidgets('the flag is injectable; without a provider the build flag decides', (
      tester,
    ) async {
      late BuildContext ctx;
      Widget probe() => Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      );
      await tester.pumpWidget(probe());
      expect(StoreConfig.isPlayStore(ctx), kPlayStore);
      expect(kPlayStore, isFalse, reason: 'tests run without --dart-define=STORE=play');
      await tester.pumpWidget(
        Provider<StoreConfig>.value(value: const StoreConfig(playStore: true), child: probe()),
      );
      expect(StoreConfig.isPlayStore(ctx), isTrue);
      await tester.pumpWidget(
        Provider<StoreConfig>.value(value: const StoreConfig(playStore: false), child: probe()),
      );
      expect(StoreConfig.isPlayStore(ctx), isFalse);
    });

    for (final play in [true, false]) {
      testWidgets('4th community, play=$play: ${play ? 'not sent, no UPI' : 'fee warning'}', (
        tester,
      ) async {
        _phone(tester);
        final w = _World(play: play);
        await w.masters.load();
        w.account.nextRequest = CommunityRequest.fromJson(_feeRequest('created'));
        await tester.pumpWidget(w.app(const SettingsScreen()));
        await tester.pumpAndSettle();

        expect(
          find.text(play ? S.playFreeCommunitiesNote(3) : S.freeCommunitiesNote(3, 1000)),
          findsOneWidget,
        );
        await _tap(tester, find.widgetWithText(OutlinedButton, S.requestCommunity));
        await _tap(tester, find.widgetWithText(ListTile, 'Brahmin'));

        if (play) {
          expect(_inDialog(find.text(S.playNoExtraCommunityPayment)), findsOneWidget);
          expect(find.textContaining('₹1000'), findsNothing);
          await _tap(tester, _inDialog(_button(S.ok)));
          expect(w.account.requested, isEmpty, reason: 'not sent');
          expect(find.byType(CommunityPaymentScreen), findsNothing);
        } else {
          expect(
            _inDialog(find.text('This is your 4th community: one-time fee ₹1000')),
            findsOneWidget,
          );
          await _tap(tester, _inDialog(_button(S.continueToPay)));
          expect(w.account.requested, [4]);
          expect(find.byType(UpiPayCard), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('pending fee rows, play=$play: ${play ? 'state only' : 'pay buttons'}', (
        tester,
      ) async {
        _phone(tester);
        final w = _World(
          play: play,
          account: _mine([
            _feeRequest('created'),
            {
              ..._feeRequest('failed', reason: 'UTR not found'),
              'id': 32,
              'community_name': 'Vysya',
            },
          ]),
        );
        await tester.pumpWidget(w.app(const SettingsScreen()));
        await tester.pumpAndSettle();

        final notPaid = play
            ? 'Fee ₹1000 · ${S.onlinePaymentUnavailable}'
            : 'Fee ₹1000 · ${S.notPaidYet}';
        // Both rows sit near the top of the list (built without scrolling).
        expect(find.text(notPaid), findsOneWidget);
        expect(find.text('Payment not verified: UTR not found'), findsOneWidget);
        expect(_button(S.payAmount(1000)), play ? findsNothing : findsOneWidget);
        expect(_button(S.submitAgain), play ? findsNothing : findsOneWidget);
      });
    }

    testWidgets('play: a fee the server asks for anyway opens no UPI step', (tester) async {
      _phone(tester);
      final w = _World(
        play: true,
        account: _mine(
          const [],
          communities: const [
            {'id': 1, 'name': 'Reddy'},
          ],
        ),
      );
      await w.masters.load();
      w.account.nextRequest = CommunityRequest.fromJson(_feeRequest('created'));
      await tester.pumpWidget(w.app(const SettingsScreen()));
      await tester.pumpAndSettle();

      await _tap(tester, find.widgetWithText(OutlinedButton, S.requestCommunity));
      await _tap(tester, find.widgetWithText(ListTile, 'Brahmin'));
      expect(w.account.requested, [4]);
      expect(_inDialog(find.text(S.playNoExtraCommunityPayment)), findsOneWidget);
      expect(find.byType(CommunityPaymentScreen), findsNothing);
    });

    testWidgets('play: the pay screen itself never shows UPI, QR or UTR', (tester) async {
      _phone(tester);
      final w = _World(play: true);
      await tester.pumpWidget(
        w.app(CommunityPaymentScreen(request: CommunityRequest.fromJson(_feeRequest('created')))),
      );
      await tester.pumpAndSettle();
      expect(find.text(S.onlinePaymentUnavailable), findsOneWidget);
      expect(find.byType(UpiPayCard), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.byType(UtrForm), findsNothing);
    });

    testWidgets('play: admins still request freely', (tester) async {
      _phone(tester);
      final w = _World(play: true, admin: true);
      await w.masters.load();
      w.account.nextRequest = CommunityRequest.fromJson(const {
        'id': 41,
        'status': 'pending',
        'community_id': 4,
        'community_name': 'Brahmin',
        'fee_inr': 0,
      });
      await tester.pumpWidget(w.app(const SettingsScreen()));
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(OutlinedButton, S.requestCommunity));
      await _tap(tester, find.widgetWithText(ListTile, 'Brahmin'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(w.account.requested, [4]);
    });

    for (final play in [true, false]) {
      testWidgets('signup hint, play=$play', (tester) async {
        _phone(tester);
        final w = _World(play: play);
        await tester.pumpWidget(w.app(const SignupScreen()));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextFormField, S.phone), '9000000001');
        await _tap(tester, _button(S.sendOtp));
        await tester.enterText(find.widgetWithText(TextFormField, S.otpCode), '123456');
        await _tap(tester, _button(S.verifyOtp));

        expect(
          find.text(
            play ? 'Up to 3 now — the admin can add more later' : S.signupCommunitiesLimit(3, 1000),
          ),
          findsOneWidget,
        );
        for (final c in ['Reddy', 'Kamma', 'Kapu', 'Brahmin']) {
          await _tap(tester, find.widgetWithText(FilterChip, c));
        }
        expect(
          find.text(play ? S.playTooManyCommunities(3) : S.tooManyCommunities(3, 1000)),
          findsOneWidget,
        );
        if (play) expect(find.textContaining('₹'), findsNothing);
      });
    }
  });

  // ---------------------------------------------------------------- F: delete my account

  group('Delete my account (SPEC §9.20 F)', () {
    final deletionPage = Uri.parse('${AppConfig.apiBaseUrl}/delete-account?app=agent');

    test('the page is the API origin\'s /delete-account for the agent app', () {
      expect(AppConfig.deleteAccountUrl, '${AppConfig.apiBaseUrl}/delete-account?app=agent');
    });

    testWidgets('More: sheet explains, Cancel does nothing, Open launches the page', (
      tester,
    ) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const MoreScreen()));
      await tester.pump();

      final entry = find.text(S.deleteMyAccount);
      expect(find.text(S.deleteMyAccountSubtitle), findsOneWidget);
      await _tap(tester, entry);
      expect(find.text(S.deleteMyAccountBody), findsOneWidget);
      await _tap(tester, find.widgetWithText(TextButton, S.cancel));
      expect(w.launcher.launched, isEmpty);

      await _tap(tester, entry);
      await _tap(tester, find.text(S.openDeletionPage));
      expect(w.launcher.launched, [deletionPage]);

      w.launcher.result = false;
      await _tap(tester, entry);
      await _tap(tester, find.text(S.openDeletionPage));
      expect(find.text(S.cannotOpenBrowser), findsOneWidget);
    });

    testWidgets('Settings has it in Account', (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const SettingsScreen()));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text(S.deleteMyAccount));
      await _tap(tester, find.text(S.deleteMyAccount));
      await _tap(tester, find.text(S.openDeletionPage));
      expect(w.launcher.launched, [deletionPage]);
    });

    for (final status in ['pending', 'suspended']) {
      testWidgets('$status agents get it on the waiting screen', (tester) async {
        _phone(tester);
        final w = _World(status: status);
        await tester.pumpWidget(w.app(const PendingScreen()));
        await tester.pump();
        final button = find.widgetWithText(TextButton, S.deleteMyAccount);
        await _scrollTo(tester, button);
        await _tap(tester, button);
        expect(find.text(S.deleteMyAccountBody), findsOneWidget);
        await _tap(tester, find.text(S.openDeletionPage));
        expect(w.launcher.launched, [deletionPage]);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ---------------------------------------------------------------- F: admin

  group('admin: Account deletion requests (SPEC §9.20 F)', () {
    test('parsing: requests, decisions, counts', () {
      final r = DeletionRequest.fromJson(_deletion());
      expect(r.id, 7);
      expect(r.app, 'customer');
      expect(r.isAgentApp, isFalse);
      expect(r.phone, '9876543210');
      expect(r.fullName, 'Sravani Reddy');
      expect(r.reason, 'Marriage fixed, please remove my details');
      expect(r.isPending, isTrue);
      expect(r.accountExists, isTrue);
      expect(r.createdAt, isNotNull);
      expect(r.handledAt, isNull);

      final done = DeletionRequest.fromJson(
        _deletion(app: 'agent', status: 'done', exists: false, note: 'Agent account scrubbed'),
      );
      expect(done.isAgentApp, isTrue);
      expect(done.isDone, isTrue);
      expect(done.accountExists, isFalse);
      expect(done.note, 'Agent account scrubbed');
      expect(done.handledAt, isNotNull);

      final bare = DeletionRequest.fromJson(const {'id': 1, 'phone': '9000000001'});
      expect(bare.fullName, isNull);
      expect(bare.reason, isNull);
      expect(bare.accountExists, isFalse);

      final decision = DeletionDecision.fromJson(const {
        'id': 7,
        'status': 'done',
        'note': 'Deleted',
        'handled_at': '2026-11-13T12:00:00Z',
      });
      expect(decision.status, 'done');
      expect(decision.note, 'Deleted');

      final feed = NotificationFeed.fromJson({
        'badge': 2,
        'items': [],
        'counts': {'pending_agents': 1, 'deletion_requests': 1},
      });
      expect(feed.deletionRequests, 1);
      expect(feed.adminPending, 2);
      expect(AdminStats.fromJson({'deletion_requests': 2}).deletionRequests, 2);
      expect(AdminStats.fromJson(const {}).deletionRequests, 0);
    });

    test('routing: deletion_requested → the screen, admins only', () {
      final item = NotificationItem.fromJson(const {
        'type': 'deletion_requested',
        'id': 7,
        'title': 'Account deletion request',
        'body': 'b',
      });
      expect(notificationTarget(item, isAdmin: true), const AdminDeletionRequestsTarget());
      expect(notificationTarget(item, isAdmin: false), isNull);
      expect(notificationGroup('deletion_requested', isAdmin: true), NotificationGroup.action);
      expect(notificationGroup('deletion_requested', isAdmin: false), NotificationGroup.update);
      expect(
        screenForTarget(const AdminDeletionRequestsTarget()),
        isA<AdminDeletionRequestsScreen>(),
      );
    });

    testWidgets('rows, call, delete with confirmation, agent_has_data, reject, filters', (
      tester,
    ) async {
      _phone(tester, const Size(400, 1400));
      final w = _World(admin: true);
      w.admin.byStatus = {
        'pending': [
          DeletionRequest.fromJson(_deletion()),
          DeletionRequest.fromJson({
            ..._deletion(id: 8, app: 'agent', exists: false),
            'full_name': null,
            'reason': null,
          }),
        ],
        'done': [
          DeletionRequest.fromJson(_deletion(id: 5, status: 'done', note: 'Customer deleted')),
        ],
        'rejected': [],
        'all': [],
      };
      await tester.pumpWidget(w.app(const AdminDeletionRequestsScreen()));
      await tester.pumpAndSettle();

      expect(w.admin.statuses, ['pending']);
      expect(find.text(S.deletionVerifyHint), findsNWidgets(2));
      expect(find.text(S.appCustomer), findsOneWidget);
      expect(find.text(S.appAgent), findsOneWidget);
      expect(find.text('+91 9876543210'), findsNWidgets(2));
      expect(find.text('Sravani Reddy'), findsOneWidget);
      expect(find.text('Marriage fixed, please remove my details'), findsOneWidget);
      expect(find.text(S.noReasonGiven), findsOneWidget);
      expect(find.text(S.accountFound), findsOneWidget);
      expect(find.text(S.noAccountWithNumber), findsOneWidget);
      expect(find.textContaining(S.requestedOn), findsNWidgets(2));

      // Tap the number to call.
      await _tap(tester, find.text('+91 9876543210').first);
      expect(w.launcher.launched, [Uri.parse('tel:+919876543210')]);

      // Delete asks first (cannot be undone); cancel sends nothing.
      await _tap(tester, _button(S.deleteAccount).first);
      expect(_inDialog(find.text(S.deleteAccountConfirmBody('9876543210'))), findsOneWidget);
      expect(_inDialog(find.textContaining('cannot be undone')), findsOneWidget);
      await _tap(tester, _inDialog(find.widgetWithText(TextButton, S.cancel)));
      expect(w.admin.completed, isEmpty);

      // The agent still owns profiles: the server's message in a dialog.
      w.admin.completeError = ApiException(
        'agent_has_data',
        'This agent still has 12 profiles and 3 clients — move them to another agent first',
        status: 409,
      );
      await _tap(tester, _button(S.deleteAccount).at(1));
      await _tap(tester, _inDialog(_button(S.deleteAccount)));
      expect(w.admin.completed, [8]);
      expect(_inDialog(find.text(S.agentHasDataTitle)), findsOneWidget);
      expect(
        _inDialog(
          find.text(
            'This agent still has 12 profiles and 3 clients — move them to another agent first',
          ),
        ),
        findsOneWidget,
      );
      await _tap(tester, _inDialog(_button(S.ok)));

      // Completed: the server's note is shown and the row leaves the list.
      w.admin.completeError = null;
      await _tap(tester, _button(S.deleteAccount).first);
      await _tap(tester, _inDialog(_button(S.deleteAccount)));
      expect(w.admin.completed, [8, 7]);
      expect(find.text('Customer account, 1 profile and 4 photos deleted'), findsOneWidget);
      expect(find.text('Sravani Reddy'), findsNothing);

      // Reject needs a 3–200 character note.
      await _tap(tester, find.widgetWithText(OutlinedButton, S.reject));
      final note = _inDialog(find.byType(TextFormField));
      await tester.enterText(note, 'x');
      await _tap(tester, _inDialog(_button(S.reject)));
      expect(_inDialog(find.text(S.rejectReasonInvalid)), findsOneWidget);
      await tester.enterText(note, ' Could not reach the person ');
      await _tap(tester, _inDialog(_button(S.reject)));
      expect(w.admin.rejected, [(8, 'Could not reach the person')]);
      expect(find.text(S.noDeletionRequests), findsOneWidget);

      // Filters.
      await _tap(tester, find.widgetWithText(ChoiceChip, S.filterDone));
      expect(w.admin.statuses.last, 'done');
      expect(find.text('${S.noteLabel}: Customer deleted'), findsOneWidget);
      expect(find.textContaining(S.handledOn), findsOneWidget);
      expect(find.text(S.deletionVerifyHint), findsNothing);
      expect(_button(S.deleteAccount), findsNothing);
      await _tap(tester, find.widgetWithText(ChoiceChip, S.filterRejected));
      expect(w.admin.statuses.last, 'rejected');
      await _tap(tester, find.widgetWithText(ChoiceChip, S.filterAll));
      expect(w.admin.statuses.last, 'all');
      expect(find.text(S.noDeletionRequestsInList), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('badge on More and the Admin home; the feed item opens the screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      _phone(tester);
      final w = _World(admin: true);
      w.admin.byStatus = {
        'pending': [DeletionRequest.fromJson(_deletion())],
      };
      w.auth.feed = NotificationFeed.fromJson({
        'badge': 1,
        'items': [
          {
            'type': 'deletion_requested',
            'id': 7,
            'title': 'Account deletion request',
            'body': '+91 9876543210 asked to delete their Wedbook Matrimony account',
            'at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
        'counts': {'deletion_requests': 1},
      });

      await tester.pumpWidget(w.app(const MoreScreen()));
      await tester.pump();
      expect(find.text(S.deletionRequestsCount(1)), findsOneWidget);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, S.admin), matching: find.text('1')),
        findsOneWidget,
      );

      w.admin.statsResult = AdminStats.fromJson({'deletion_requests': 1});
      await tester.pumpWidget(w.app(const AdminHomeScreen()));
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, S.deletionRequests);
      await _scrollTo(tester, tile);
      expect(find.descendant(of: tile, matching: find.text('1')), findsOneWidget);

      await tester.pumpWidget(w.app(const NotificationsScreen(key: ValueKey('n'))));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Account deletion request'));
      expect(find.byType(AdminDeletionRequestsScreen), findsOneWidget);
      expect(find.text('Sravani Reddy'), findsOneWidget);
    });
  });
}
