import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/agent.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/models/notifications.dart';
import 'package:matrimony_agents/models/payment.dart';
import 'package:matrimony_agents/services/admin_service.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/services/link_launcher.dart';
import 'package:matrimony_agents/state/auth_state.dart';
import 'package:matrimony_agents/state/home_nav.dart';
import 'package:matrimony_agents/state/masters_state.dart';
import 'package:matrimony_agents/state/notification_routes.dart';
import 'package:matrimony_agents/ui/screens/admin/admin_community_requests_screen.dart';
import 'package:matrimony_agents/ui/screens/admin/admin_home_screen.dart';
import 'package:matrimony_agents/ui/screens/admin/admin_payments_screen.dart';
import 'package:matrimony_agents/ui/screens/auth/signup_screen.dart';
import 'package:matrimony_agents/ui/screens/community_payment_screen.dart';
import 'package:matrimony_agents/ui/screens/more_screen.dart';
import 'package:matrimony_agents/ui/screens/notifications_screen.dart';
import 'package:matrimony_agents/ui/screens/settings_screen.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:matrimony_agents/ui/widgets/reason_dialog.dart';
import 'package:matrimony_agents/ui/widgets/upi_payment.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Release 3.2.0 (SPEC §9.20): signup takes at most 3 communities, a 4th+
/// community costs a one-time ₹1000 paid by UPI and verified by an admin,
/// and admins get "Payments to verify".

// ---------------------------------------------------------------- wire shapes

const _upiUri = 'upi://pay?pa=wedbook%40ybl&pn=Wedbook&am=1000.00&cu=INR&tn=Wedbook%20WB12';

const _upi = {
  'vpa': 'wedbook@ybl',
  'name': 'Wedbook',
  'amount_inr': 1000,
  'note': 'Wedbook WB12',
  'reference': 'WB12',
  'uri': _upiUri,
};

Map<String, dynamic> _payment(String status, {String? utr, String? reason}) => {
  'id': 12,
  'status': status,
  'utr': utr,
  'submitted_at': utr == null ? null : '2026-11-13T09:30:00.000Z',
  'reject_reason': reason,
  'upi': _upi,
};

Map<String, dynamic> _feeRequest(Map<String, dynamic>? payment, {int id = 31}) => {
  'id': id,
  'status': 'pending',
  'created_at': '2026-11-13T09:00:00.000Z',
  'decided_at': null,
  'community_id': 4,
  'community_name': 'Brahmin',
  'fee_inr': 1000,
  'payment': payment,
};

const _communities = [
  {'id': 1, 'name': 'Reddy'},
  {'id': 2, 'name': 'Kamma'},
  {'id': 3, 'name': 'Kapu'},
];

MyCommunities _mine(
  List<Map<String, dynamic>> requests, {
  List<Map<String, dynamic>> communities = _communities,
}) => MyCommunities.fromJson({
  'communities': communities,
  'requests': requests,
  'free_limit': 3,
  'extra_fee_inr': 1000,
});

// ---------------------------------------------------------------- fakes

class _FakeProfiles extends ProfileService {
  _FakeProfiles() : super(ApiClient());

  @override
  Future<MasterData> masters() async => MasterData.fromJson({
    'communities': [
      ..._communities,
      {'id': 4, 'name': 'Brahmin'},
      {'id': 5, 'name': 'Vysya'},
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
  List<int>? signedUpCommunities;
  ApiException? signupError;

  @override
  Agent? get agent => me;

  @override
  bool get isAdmin => me?.isAdmin ?? false;

  @override
  NotificationFeed get notifications => feed;

  @override
  int get badge => feed.badge;

  @override
  Future<void> signup({
    required String fullName,
    required String phone,
    required String password,
    required List<int> communityIds,
    required String phoneVerificationToken,
    String? agencyName,
    int? stateId,
    bool acceptedTerms = false,
  }) async {
    if (signupError != null) throw signupError!;
    signedUpCommunities = communityIds;
  }
}

class _FakeAccount extends MyAccountService {
  _FakeAccount(this.state) : super(ApiClient());

  MyCommunities state;
  CommunityRequest? nextRequest;
  ApiException? requestError;
  ApiException? submitError;
  final requested = <int>[];
  final submitted = <(int, String)>[];

  @override
  Future<MyCommunities> communities() async => state;

  @override
  Future<CommunityRequest> requestCommunity(int communityId) async {
    requested.add(communityId);
    if (requestError != null) throw requestError!;
    return nextRequest!;
  }

  @override
  Future<UpiPayment?> submitPayment(int paymentId, String utr) async {
    submitted.add((paymentId, utr));
    if (submitError != null) throw submitError!;
    return UpiPayment.fromJson(_payment('submitted', utr: utr));
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

  Map<String, List<AdminPayment>> byStatus = {};
  List<CommunityRequest> requests = [];
  AdminStats statsResult = AdminStats.fromJson(const {});
  final statuses = <String>[];
  final approved = <int>[];
  final rejected = <(int, String)>[];
  final decided = <(int, bool)>[];
  ApiException? decideError;

  @override
  Future<AdminStats> stats() async => statsResult;

  @override
  Future<List<AdminPayment>> payments({String status = PaymentStatus.submitted}) async {
    statuses.add(status);
    return [...?byStatus[status]];
  }

  @override
  Future<void> approvePayment(int id) async {
    approved.add(id);
    byStatus[PaymentStatus.submitted]?.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> rejectPayment(int id, String reason) async {
    rejected.add((id, reason));
    byStatus[PaymentStatus.submitted]?.removeWhere((p) => p.id == id);
  }

  @override
  Future<List<CommunityRequest>> communityRequests({String? status}) async => requests;

  @override
  Future<void> decideCommunityRequest(int id, {required bool approve}) async {
    decided.add((id, approve));
    if (decideError != null) throw decideError!;
  }
}

Agent _agent({bool admin = false}) => Agent.fromJson({
  'id': 4,
  'full_name': 'Lakshmi Devi',
  'agency_name': 'Sri Lakshmi Marriage Bureau',
  'phone': '9000000004',
  'role': admin ? 'admin' : 'agent',
  'status': 'active',
  'communities': _communities,
  'state': {'id': 1, 'name': 'Karnataka', 'code': 'KA'},
  'agent_code': 'KA1A',
});

class _World {
  _World({bool admin = false, MyCommunities? account}) {
    auth = _FakeAuth(_agent(admin: admin), profiles, authService);
    this.account = _FakeAccount(account ?? _mine(const []));
    masters = MastersState(profiles);
  }

  final profiles = _FakeProfiles();
  final authService = _FakeAuthService();
  final launcher = _FakeLauncher();
  final admin = _FakeAdmin();
  late final _FakeAuth auth;
  late final _FakeAccount account;
  late final MastersState masters;

  Widget app(Widget home) => MultiProvider(
    providers: [
      Provider<ApiClient>(create: (_) => ApiClient()),
      Provider<ProfileService>.value(value: profiles),
      Provider<AuthService>.value(value: authService),
      Provider<MyAccountService>.value(value: account),
      Provider<AdminService>.value(value: admin),
      Provider<LinkLauncher>.value(value: launcher),
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

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Scrolls the screen's list (lazily built) until [finder] is built and visible.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

/// Lets a snackbar time out so it no longer covers the bottom of the screen.
Future<void> _waitSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Finder _inDialog(Finder matching) =>
    find.descendant(of: find.byType(AlertDialog), matching: matching);

AdminPayment _adminPayment(Map<String, dynamic> j) => AdminPayment.fromJson(j);

final _registrationJson = <String, dynamic>{
  'id': 21,
  'purpose': 'profile_registration',
  'status': 'submitted',
  'amount_inr': 150,
  'utr': '123456789012',
  'reference': 'WB21',
  'submitted_at': '2026-11-13T09:30:00.000Z',
  'verified_at': null,
  'reject_reason': null,
  'customer': {'id': 5, 'full_name': 'Priya Lakshmi', 'phone': '9000000005'},
  'profile': {'id': 9, 'full_name': 'Priya Lakshmi', 'profile_code': 'GN-KA1A-A009'},
  'agent': null,
  'community': null,
};

final _communityJson = <String, dynamic>{
  'id': 22,
  'purpose': 'extra_community',
  'status': 'submitted',
  'amount_inr': 1000,
  'utr': '210987654321',
  'reference': 'WB22',
  'submitted_at': '2026-11-13T10:00:00.000Z',
  'verified_at': null,
  'reject_reason': null,
  'customer': null,
  'profile': null,
  'agent': {'id': 8, 'full_name': 'Suresh Kumar', 'phone': '9000000008', 'agent_code': 'AP3C'},
  'community': {'id': 4, 'name': 'Brahmin'},
};

void main() {
  // ---------------------------------------------------------------- models

  group('parsing (SPEC §9.20)', () {
    test('GET /my/communities with the fee rule, a fee request and a free one', () {
      final mine = MyCommunities.fromJson({
        'communities': [
          {'id': 1, 'name': 'Reddy'},
          {'id': 2, 'name': 'Kamma'},
        ],
        'requests': [
          _feeRequest(_payment('created')),
          {
            'id': 30,
            'status': 'approved',
            'created_at': '2026-11-01T09:00:00.000Z',
            'community_id': 2,
            'community_name': 'Kamma',
            'fee_inr': 0,
            'payment': null,
          },
        ],
        'free_limit': 3,
        'extra_fee_inr': 1000,
      });

      expect(mine.freeLimit, 3);
      expect(mine.extraFeeInr, 1000);
      expect(mine.communities.map((c) => c.name), ['Reddy', 'Kamma']);
      expect(mine.pending, hasLength(1));
      expect(mine.used, 3, reason: '2 communities + 1 pending request');
      expect(mine.nextIsPaid, isTrue);
      expect(mine.nextNumber, 4);

      final fee = mine.requests.first;
      expect(fee.hasFee, isTrue);
      expect(fee.feeInr, 1000);
      expect(fee.needsPayment, isTrue);
      expect(fee.feePaymentStatus, 'created');
      final p = fee.payment!;
      expect(p.id, 12);
      expect(p.canSubmit, isTrue);
      expect(p.upi!.vpa, 'wedbook@ybl');
      expect(p.upi!.name, 'Wedbook');
      expect(p.upi!.amountInr, 1000);
      expect(p.upi!.reference, 'WB12');
      expect(p.upi!.note, 'Wedbook WB12');
      expect(p.upi!.uri, _upiUri);

      final free = mine.requests.last;
      expect(free.hasFee, isFalse);
      expect(free.payment, isNull);
      expect(free.needsPayment, isFalse);
      expect(free.feePaymentStatus, isNull);
    });

    test('an older server: no fee keys → free, defaults 3 / ₹1000', () {
      final mine = MyCommunities.fromJson({
        'communities': [
          {'id': 1, 'name': 'Reddy'},
        ],
        'requests': [
          {'id': 3, 'status': 'pending', 'community_id': 2, 'community_name': 'Kamma'},
        ],
      });
      expect(mine.freeLimit, 3);
      expect(mine.extraFeeInr, 1000);
      expect(mine.requests.single.hasFee, isFalse);
      expect(mine.requests.single.payment, isNull);
      expect(mine.nextIsPaid, isFalse);
    });

    test('payment states: submitted, failed with a reason, paid', () {
      final submitted = UpiPayment.fromJson(_payment('submitted', utr: '123456789012'));
      expect(submitted.isSubmitted, isTrue);
      expect(submitted.canSubmit, isFalse);
      expect(submitted.utr, '123456789012');
      expect(submitted.submittedAt, isNotNull);

      final failed = UpiPayment.fromJson(
        _payment('failed', utr: '111111111111', reason: 'No such UTR'),
      );
      expect(failed.isFailed, isTrue);
      expect(failed.canSubmit, isTrue, reason: 'a corrected UTR goes on the same row');
      expect(failed.rejectReason, 'No such UTR');

      expect(UpiPayment.fromJson(_payment('paid', utr: '1')).isPaid, isTrue);
      expect(UpiPayment.fromJsonOrNull(null), isNull);
      expect(UpiInfo.fromJsonOrNull(const {'vpa': 'x'}), isNull, reason: 'no uri');
    });

    test('admin community-request rows: fee_inr, payment_id, payment_status, utr', () {
      final r = CommunityRequest.fromJson(const {
        'id': 7,
        'status': 'pending',
        'community_id': 4,
        'community_name': 'Brahmin',
        'agent_id': 8,
        'agent_name': 'Suresh',
        'agent_phone': '9000000008',
        'fee_inr': 1000,
        'payment_id': 12,
        'payment_status': 'submitted',
        'utr': '123456789012',
      });
      expect(r.hasFee, isTrue);
      expect(r.paymentId, 12);
      expect(r.feePaymentStatus, 'submitted');
      expect(r.feeUtr, '123456789012');
      expect(r.needsPayment, isFalse);
      expect(
        S.feeState(r.feeInr, r.feePaymentStatus, r.feeUtr),
        'Fee ₹1000 · payment submitted (UTR 123456789012)',
      );
      expect(S.feeState(1000, 'created', null), 'Fee ₹1000 · awaiting payment');
      expect(S.feeState(1000, null, null), 'Fee ₹1000 · awaiting payment');
    });

    test('admin payments list: a customer fee and an agent community fee', () {
      final reg = _adminPayment(_registrationJson);
      expect(reg.isSubmitted, isTrue);
      expect(reg.isExtraCommunity, isFalse);
      expect(reg.amountInr, 150);
      expect(reg.utr, '123456789012');
      expect(reg.reference, 'WB21');
      expect(reg.customer!.fullName, 'Priya Lakshmi');
      expect(reg.customer!.phone, '9000000005');
      expect(reg.profile!.profileCode, 'GN-KA1A-A009');
      expect(reg.agent, isNull);
      expect(reg.community, isNull);
      expect(reg.submittedAt, isNotNull);

      final com = _adminPayment(_communityJson);
      expect(com.isExtraCommunity, isTrue);
      expect(com.agent!.agentCode, 'AP3C');
      expect(com.agent!.phone, '9000000008');
      expect(com.community!.name, 'Brahmin');
      expect(com.customer, isNull);

      final paid = _adminPayment({
        ..._communityJson,
        'status': 'paid',
        'verified_at': '2026-11-13T11:00:00Z',
      });
      expect(paid.isPaid, isTrue);
      expect(paid.verifiedAt, isNotNull);
      expect(_adminPayment({'id': 1, 'amount_inr': '150.00'}).amountInr, 150);
    });

    test('feed and stats count payments to verify', () {
      final feed = NotificationFeed.fromJson({
        'badge': 3,
        'items': [],
        'counts': {'pending_agents': 1, 'pending_password_resets': 0, 'payments_to_verify': 2},
      });
      expect(feed.paymentsToVerify, 2);
      expect(feed.adminPending, 3);
      expect(NotificationFeed.fromJson(const {}).paymentsToVerify, 0);
      expect(AdminStats.fromJson({'payments_to_verify': 4}).paymentsToVerify, 4);
      expect(AdminStats.fromJson(const {}).paymentsToVerify, 0);
    });

    test('UTR and reject-reason rules, ordinals', () {
      expect(UtrForm.isValidUtr('123456789012'), isTrue);
      expect(UtrForm.isValidUtr(' 123456789012 '), isTrue);
      expect(UtrForm.isValidUtr('12345678901'), isFalse);
      expect(UtrForm.isValidUtr('1234567890123'), isFalse);
      expect(UtrForm.isValidUtr('12345678901a'), isFalse);
      expect(ReasonDialog.isValidReason('no'), isFalse);
      expect(ReasonDialog.isValidReason('   ab  '), isFalse);
      expect(ReasonDialog.isValidReason('UTR not found'), isTrue);
      expect(ReasonDialog.isValidReason('x' * 200), isTrue);
      expect(ReasonDialog.isValidReason('x' * 201), isFalse);
      expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101].map(S.ordinal), [
        '1st',
        '2nd',
        '3rd',
        '4th',
        '11th',
        '12th',
        '13th',
        '21st',
        '22nd',
        '23rd',
        '101st',
      ]);
      expect(S.extraCommunityFee(4, 1000), 'This is your 4th community: one-time fee ₹1000');
    });
  });

  // ---------------------------------------------------------------- notifications

  group('notifications (SPEC §9.20 C / D)', () {
    NotificationItem item(String type) =>
        NotificationItem.fromJson({'type': type, 'id': 12, 'title': 't', 'body': 'b'});

    test('payment_to_verify → Payments (admins only), payment_rejected → My communities', () {
      expect(
        notificationTarget(item('payment_to_verify'), isAdmin: true),
        const AdminPaymentsTarget(),
      );
      expect(notificationTarget(item('payment_to_verify'), isAdmin: false), isNull);
      expect(notificationTarget(item('payment_rejected'), isAdmin: false), const SettingsTarget());
      expect(notificationTarget(item('payment_rejected'), isAdmin: true), const SettingsTarget());
      expect(notificationGroup('payment_to_verify', isAdmin: true), NotificationGroup.action);
      expect(notificationGroup('payment_to_verify', isAdmin: false), NotificationGroup.update);
      expect(notificationGroup('payment_rejected', isAdmin: false), NotificationGroup.update);
      expect(screenForTarget(const AdminPaymentsTarget()), isA<AdminPaymentsScreen>());
    });

    testWidgets('tapping a payment_to_verify item opens Payments to verify', (tester) async {
      SharedPreferences.setMockInitialValues({});
      _phone(tester);
      final w = _World(admin: true);
      w.admin.byStatus = {
        PaymentStatus.submitted: [_adminPayment(_communityJson)],
      };
      w.auth.feed = NotificationFeed.fromJson({
        'badge': 1,
        'items': [
          {
            'type': 'payment_to_verify',
            'id': 22,
            'title': 'Payment to verify',
            'body': 'Suresh Kumar paid ₹1000 — UTR 210987654321',
            'at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
        'counts': {'payments_to_verify': 1},
      });
      await tester.pumpWidget(w.app(const NotificationsScreen()));
      await tester.pumpAndSettle();

      expect(find.text(S.needsYourAction.toUpperCase()), findsOneWidget);
      await _tap(tester, find.text('Payment to verify'));
      expect(find.widgetWithText(AppBar, S.paymentsToVerify), findsOneWidget);
      expect(find.text('210987654321'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping payment_rejected opens My communities with the reason', (tester) async {
      SharedPreferences.setMockInitialValues({});
      _phone(tester);
      final w = _World(
        account: _mine([
          _feeRequest(_payment('failed', utr: '111111111111', reason: 'UTR not found')),
        ]),
      );
      w.auth.feed = NotificationFeed.fromJson({
        'badge': 0,
        'items': [
          {
            'type': 'payment_rejected',
            'id': 12,
            'title': 'Payment not verified',
            'body': 'UTR not found',
          },
        ],
      });
      await tester.pumpWidget(w.app(const NotificationsScreen()));
      await tester.pumpAndSettle();

      await _tap(tester, find.text('Payment not verified'));
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.ensureVisible(find.text(S.paymentNotVerified('UTR not found')));
      expect(find.text(S.paymentNotVerified('UTR not found')), findsOneWidget);
    });

    testWidgets('admin badge: More and the Admin home count payments to verify', (tester) async {
      _phone(tester);
      final w = _World(admin: true);
      w.auth.feed = NotificationFeed.fromJson({
        'badge': 2,
        'items': [],
        'counts': {'payments_to_verify': 2},
      });
      await tester.pumpWidget(w.app(const MoreScreen()));
      await tester.pump();
      expect(find.text(S.paymentsToVerifyCount(2)), findsOneWidget);
      final adminTile = find.widgetWithText(ListTile, S.admin);
      expect(find.descendant(of: adminTile, matching: find.text('2')), findsOneWidget);

      w.admin.statsResult = AdminStats.fromJson({'payments_to_verify': 3});
      await tester.pumpWidget(w.app(const AdminHomeScreen()));
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, S.paymentsToVerify);
      await _scrollTo(tester, tile);
      expect(find.descendant(of: tile, matching: find.text('3')), findsOneWidget);
      await _tap(tester, tile);
      expect(find.byType(AdminPaymentsScreen), findsOneWidget);
      expect(w.admin.statuses, [PaymentStatus.submitted]);
      expect(find.text(S.noPaymentsToVerify), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------- signup

  group('signup: at most 3 communities (SPEC §9.20 C)', () {
    Future<void> reachDetails(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(TextFormField, S.phone), '9000000001');
      await _tap(tester, _button(S.sendOtp));
      await tester.enterText(find.widgetWithText(TextFormField, S.otpCode), '123456');
      await _tap(tester, _button(S.verifyOtp));
      await tester.enterText(find.widgetWithText(TextFormField, S.fullName), 'New Agent');
      await tester.enterText(find.widgetWithText(TextFormField, S.password), 'secret1');
      await tester.enterText(find.widgetWithText(TextFormField, S.confirmPassword), 'secret1');
    }

    bool selected(WidgetTester tester, String name) =>
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, name)).selected;

    testWidgets('a 4th community is refused with the hint; 3 go to the server', (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const SignupScreen()));
      await tester.pumpAndSettle();
      await reachDetails(tester);

      expect(find.text('Up to 3 now — you can add more later (₹1000 each)'), findsOneWidget);
      for (final c in ['Reddy', 'Kamma', 'Kapu']) {
        await _tap(tester, find.widgetWithText(FilterChip, c));
      }
      await _tap(tester, find.widgetWithText(FilterChip, 'Brahmin'));
      expect(selected(tester, 'Brahmin'), isFalse);
      expect(find.text(S.tooManyCommunities(3, 1000)), findsOneWidget);

      // Unselecting one frees a place again.
      await _tap(tester, find.widgetWithText(FilterChip, 'Kapu'));
      expect(find.text(S.tooManyCommunities(3, 1000)), findsNothing);
      await _tap(tester, find.widgetWithText(FilterChip, 'Brahmin'));
      expect(selected(tester, 'Brahmin'), isTrue);

      await _tap(tester, find.byType(Checkbox)); // the terms (SPEC §9.22 C)
      await _tap(tester, _button(S.signup));
      expect(w.auth.signedUpCommunities, unorderedEquals([1, 2, 4]));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the server\'s too_many_communities message is shown', (tester) async {
      _phone(tester);
      final w = _World();
      w.auth.signupError = ApiException(
        'too_many_communities',
        'Choose up to 3 communities — you can add more later (₹1000 each)',
        status: 400,
      );
      await tester.pumpWidget(w.app(const SignupScreen()));
      await tester.pumpAndSettle();
      await reachDetails(tester);
      await _tap(tester, find.widgetWithText(FilterChip, 'Reddy'));
      await _tap(tester, find.byType(Checkbox)); // the terms (SPEC §9.22 C)
      await _tap(tester, _button(S.signup));
      expect(
        find.text('Choose up to 3 communities — you can add more later (₹1000 each)'),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------- my communities

  group('My communities: paid extra community (SPEC §9.20 C / E)', () {
    testWidgets('4th community: fee warning → UPI pay card → UTR → under verification', (
      tester,
    ) async {
      _phone(tester);
      final w = _World();
      await w.masters.load();
      w.account.nextRequest = CommunityRequest.fromJson(_feeRequest(_payment('created')));
      await tester.pumpWidget(w.app(const SettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.text(S.freeCommunitiesNote(3, 1000)), findsOneWidget);
      await _tap(tester, find.widgetWithText(OutlinedButton, S.requestCommunity));
      await _tap(tester, find.widgetWithText(ListTile, 'Brahmin'));

      // Warned before anything is sent.
      expect(
        _inDialog(find.text('This is your 4th community: one-time fee ₹1000')),
        findsOneWidget,
      );
      expect(w.account.requested, isEmpty);
      await _tap(tester, _inDialog(_button(S.continueToPay)));
      expect(w.account.requested, [4]);

      // The pay step.
      expect(find.byType(CommunityPaymentScreen), findsOneWidget);
      expect(find.text('This is your 4th community: one-time fee ₹1000'), findsOneWidget);
      expect(find.text('₹1000'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('wedbook@ybl'), findsOneWidget);
      expect(find.widgetWithText(TextButton, S.copy), findsOneWidget);

      await _tap(tester, _button('Pay ₹1000 with UPI app'));
      expect(w.launcher.launched, [Uri.parse(_upiUri)]);

      // No UPI app on the phone: say so.
      w.launcher.result = false;
      await _tap(tester, _button('Pay ₹1000 with UPI app'));
      expect(find.text(S.upiNoApp), findsOneWidget);
      await _waitSnack(tester);

      // The UTR must be 12 digits.
      final utrField = find.widgetWithText(TextFormField, S.utrLabel);
      await _scrollTo(tester, utrField);
      await tester.enterText(utrField, '12345');
      await _tap(tester, _button(S.submitForVerification));
      expect(find.text(S.utrInvalid), findsOneWidget);
      expect(w.account.submitted, isEmpty);

      await tester.enterText(utrField, '1234 5678 9012 99');
      expect(
        tester.widget<TextFormField>(utrField).controller!.text,
        '123456789012',
        reason: 'digits only, at most 12',
      );
      await _tap(tester, _button(S.submitForVerification));
      expect(w.account.submitted, [(12, '123456789012')]);
      expect(find.text(S.paymentUnderVerification), findsOneWidget);
      expect(find.text(S.utrValue('123456789012')), findsOneWidget);
      expect(find.byType(UtrForm), findsNothing);

      // Back on My communities the request shows its payment state.
      w.account.state = _mine([_feeRequest(_payment('submitted', utr: '123456789012'))]);
      await _tap(tester, _button(S.done));
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.ensureVisible(find.text(S.paymentUnderVerification));
      expect(find.text(S.paymentUnderVerification), findsOneWidget);
      expect(find.text(S.utrValue('123456789012')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, S.payAmount(1000)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unpaid fee request offers "Pay ₹1000"', (tester) async {
      _phone(tester);
      final w = _World(account: _mine([_feeRequest(_payment('created'))]));
      await tester.pumpWidget(w.app(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Fee ₹1000 · ${S.notPaidYet}'));
      final pay = find.widgetWithText(FilledButton, S.payAmount(1000));
      await _tap(tester, pay);
      expect(find.byType(CommunityPaymentScreen), findsOneWidget);
      expect(find.byType(UpiPayCard), findsOneWidget);
      expect(find.text(S.communityFeeFor('Brahmin')), findsOneWidget);
    });

    testWidgets('rejected payment: the reason, Submit again, server errors shown', (tester) async {
      _phone(tester);
      final w = _World(
        account: _mine([
          _feeRequest(_payment('failed', utr: '111111111111', reason: 'UTR not found')),
        ]),
      );
      await tester.pumpWidget(w.app(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Payment not verified: UTR not found'));
      expect(find.text('Payment not verified: UTR not found'), findsOneWidget);
      await _tap(tester, find.widgetWithText(FilledButton, S.submitAgain));

      expect(find.byType(CommunityPaymentScreen), findsOneWidget);
      expect(find.text('Payment not verified: UTR not found'), findsOneWidget);
      expect(find.byType(UpiPayCard), findsOneWidget);
      await _scrollTo(tester, find.widgetWithText(TextFormField, S.utrLabel));

      w.account.submitError = ApiException(
        'utr_already_used',
        'This UTR has already been used for another payment',
        status: 409,
      );
      await tester.enterText(find.widgetWithText(TextFormField, S.utrLabel), '222222222222');
      await _tap(tester, _button(S.submitForVerification));
      expect(w.account.submitted, [(12, '222222222222')]);
      expect(find.text('This UTR has already been used for another payment'), findsOneWidget);
      expect(find.text(S.paymentUnderVerification), findsNothing);

      w.account.submitError = null;
      await _tap(tester, _button(S.submitForVerification));
      expect(find.text(S.paymentUnderVerification), findsOneWidget);
    });

    testWidgets('free requests send at once; payment_provider_error shows its message', (
      tester,
    ) async {
      _phone(tester);
      final w = _World(
        account: _mine(
          const [],
          communities: const [
            {'id': 1, 'name': 'Reddy'},
          ],
        ),
      );
      await w.masters.load();
      w.account.nextRequest = CommunityRequest.fromJson(const {
        'id': 40,
        'status': 'pending',
        'community_id': 2,
        'community_name': 'Kamma',
        'fee_inr': 0,
        'payment': null,
      });
      await tester.pumpWidget(w.app(const SettingsScreen()));
      await tester.pumpAndSettle();

      await _tap(tester, find.widgetWithText(OutlinedButton, S.requestCommunity));
      await _tap(tester, find.widgetWithText(ListTile, 'Kamma'));
      expect(find.byType(AlertDialog), findsNothing, reason: 'free: no fee warning');
      expect(w.account.requested, [2]);
      expect(find.byType(CommunityPaymentScreen), findsNothing);
      expect(find.text(S.requestSent), findsOneWidget);

      // A paid request while the server has no UPI ID.
      w.account.state = _mine(const []);
      w.account.requestError = ApiException(
        'payment_provider_error',
        'UPI payments are not set up yet',
        status: 503,
      );
      await tester.pumpWidget(w.app(const SettingsScreen(key: ValueKey('again'))));
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(OutlinedButton, S.requestCommunity));
      await _tap(tester, find.widgetWithText(ListTile, 'Vysya'));
      await _tap(tester, _inDialog(_button(S.continueToPay)));
      expect(w.account.requested, [2, 5]);
      expect(find.text('UPI payments are not set up yet'), findsOneWidget);
      expect(find.byType(CommunityPaymentScreen), findsNothing);
    });

    testWidgets('admins are never warned about the fee', (tester) async {
      _phone(tester);
      final w = _World(admin: true);
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
      expect(find.text(S.freeCommunitiesNote(3, 1000)), findsNothing);
      await _tap(tester, find.widgetWithText(OutlinedButton, S.requestCommunity));
      await _tap(tester, find.widgetWithText(ListTile, 'Brahmin'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(w.account.requested, [4]);
    });
  });

  // ---------------------------------------------------------------- admin

  group('admin: Payments to verify (SPEC §9.20 D)', () {
    testWidgets('rows, hint, approve with confirmation, reject with a reason, filters', (
      tester,
    ) async {
      _phone(tester, const Size(400, 1400));
      final w = _World(admin: true);
      w.admin.byStatus = {
        PaymentStatus.submitted: [_adminPayment(_registrationJson), _adminPayment(_communityJson)],
        PaymentStatus.paid: [
          _adminPayment({
            ..._registrationJson,
            'id': 23,
            'status': 'paid',
            'utr': '333333333333',
            'verified_at': '2026-11-13T11:00:00Z',
          }),
        ],
        PaymentStatus.failed: [
          _adminPayment({
            ..._communityJson,
            'id': 24,
            'status': 'failed',
            'reject_reason': 'UTR not found',
          }),
        ],
        'all': [],
      };
      await tester.pumpWidget(w.app(const AdminPaymentsScreen()));
      await tester.pumpAndSettle();

      expect(w.admin.statuses, ['submitted']);
      expect(find.text(S.paymentsCheckHint), findsNWidgets(2));
      // Customer fee: amount, UTR, reference, customer + phone, profile + ID.
      expect(find.text('₹150'), findsOneWidget);
      expect(find.text('123456789012'), findsOneWidget);
      expect(find.text('${S.upiReference}: WB21'), findsOneWidget);
      expect(find.text('${S.paidBy}: Priya Lakshmi · +91 9000000005'), findsOneWidget);
      expect(find.text('${S.profilePrefix}Priya Lakshmi · ID GN-KA1A-A009'), findsOneWidget);
      expect(find.text(S.purposeRegistration), findsOneWidget);
      // Agent community fee: agent + code + phone, the community.
      expect(find.text('₹1000'), findsOneWidget);
      expect(find.text('210987654321'), findsOneWidget);
      expect(find.text('${S.paidBy}: Suresh Kumar (AP3C) · +91 9000000008'), findsOneWidget);
      expect(find.text('${S.forCommunity}: Brahmin'), findsOneWidget);
      expect(find.text(S.purposeExtraCommunity), findsOneWidget);
      expect(find.textContaining(S.submittedOn), findsNWidgets(2));

      // Approve asks first; cancelling sends nothing.
      await _tap(tester, _button(S.approve).first);
      expect(_inDialog(find.text(S.approvePaymentBody(150, '123456789012'))), findsOneWidget);
      await _tap(tester, _inDialog(find.widgetWithText(TextButton, S.cancel)));
      expect(w.admin.approved, isEmpty);
      await _tap(tester, _button(S.approve).first);
      await _tap(tester, _inDialog(_button(S.approve)));
      expect(w.admin.approved, [21]);
      expect(find.text(S.paymentApproved), findsOneWidget);
      expect(find.text('123456789012'), findsNothing, reason: 'reloaded without it');

      // Reject needs 3–200 characters.
      await _tap(tester, find.widgetWithText(OutlinedButton, S.reject));
      final reason = _inDialog(find.byType(TextFormField));
      await tester.enterText(reason, 'no');
      await _tap(tester, _inDialog(_button(S.reject)));
      expect(_inDialog(find.text(S.rejectReasonInvalid)), findsOneWidget);
      expect(w.admin.rejected, isEmpty);
      await tester.enterText(reason, '  No payment with this UTR  ');
      await _tap(tester, _inDialog(_button(S.reject)));
      expect(w.admin.rejected, [(22, 'No payment with this UTR')]);
      expect(find.text(S.noPaymentsToVerify), findsOneWidget);

      // Filters.
      await _tap(tester, find.widgetWithText(ChoiceChip, S.filterPaid));
      expect(w.admin.statuses.last, 'paid');
      expect(find.text('333333333333'), findsOneWidget);
      expect(find.textContaining(S.verifiedOn), findsOneWidget);
      expect(_button(S.approve), findsNothing, reason: 'only submitted payments are decided');

      await _tap(tester, find.widgetWithText(ChoiceChip, S.filterRejected));
      expect(w.admin.statuses.last, 'failed');
      expect(find.text('${S.rejectReason}: UTR not found'), findsOneWidget);

      await _tap(tester, find.widgetWithText(ChoiceChip, S.filterAll));
      expect(w.admin.statuses.last, 'all');
      expect(find.text(S.noPayments), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('community requests show the fee and payment state; 409 is shown', (tester) async {
      _phone(tester, const Size(400, 1400));
      final w = _World(admin: true);
      w.admin.requests = [
        CommunityRequest.fromJson(const {
          'id': 1,
          'status': 'pending',
          'community_id': 4,
          'community_name': 'Brahmin',
          'agent_name': 'Suresh Kumar',
          'agent_phone': '9000000008',
          'fee_inr': 1000,
          'payment_id': 12,
          'payment_status': 'submitted',
          'utr': '123456789012',
        }),
        CommunityRequest.fromJson(const {
          'id': 2,
          'status': 'pending',
          'community_id': 5,
          'community_name': 'Vysya',
          'agent_name': 'Ramesh',
          'fee_inr': 1000,
          'payment_id': 13,
          'payment_status': 'created',
          'utr': null,
        }),
        CommunityRequest.fromJson(const {
          'id': 3,
          'status': 'pending',
          'community_id': 2,
          'community_name': 'Kamma',
          'agent_name': 'Lakshmi',
          'fee_inr': 0,
          'payment_id': null,
          'payment_status': null,
          'utr': null,
        }),
      ];
      w.admin.decideError = ApiException(
        'payment_not_submitted',
        'The agent has not paid the community fee yet',
        status: 409,
      );
      await tester.pumpWidget(w.app(const AdminCommunityRequestsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Fee ₹1000 · payment submitted (UTR 123456789012)'), findsOneWidget);
      expect(find.text('Fee ₹1000 · awaiting payment'), findsOneWidget);
      expect(find.byType(CommunityFeeLine), findsNWidgets(2), reason: 'the free request has none');

      await _tap(tester, _button(S.approve).at(1));
      expect(w.admin.decided, [(2, true)]);
      expect(find.text('The agent has not paid the community fee yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
