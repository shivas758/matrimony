import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/config.dart';
import 'package:matrimony_agents/models/agent.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/models/moderation.dart';
import 'package:matrimony_agents/models/notifications.dart';
import 'package:matrimony_agents/models/profile.dart';
import 'package:matrimony_agents/services/admin_service.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/link_launcher.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/state/auth_state.dart';
import 'package:matrimony_agents/state/home_nav.dart';
import 'package:matrimony_agents/state/masters_state.dart';
import 'package:matrimony_agents/state/notification_routes.dart';
import 'package:matrimony_agents/state/profiles_state.dart';
import 'package:matrimony_agents/ui/screens/admin/admin_home_screen.dart';
import 'package:matrimony_agents/ui/screens/admin/admin_reports_screen.dart';
import 'package:matrimony_agents/ui/screens/auth/signup_screen.dart';
import 'package:matrimony_agents/ui/screens/blocked_profiles_screen.dart';
import 'package:matrimony_agents/ui/screens/more_screen.dart';
import 'package:matrimony_agents/ui/screens/notifications_screen.dart';
import 'package:matrimony_agents/ui/screens/profiles/profile_detail_screen.dart';
import 'package:matrimony_agents/ui/screens/settings_screen.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:matrimony_agents/ui/widgets/reason_dialog.dart';
import 'package:matrimony_agents/ui/widgets/report_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SPEC §9.22 — report and block profiles, Terms consent at signup, and the
/// admin's Reports screen.

// ---------------------------------------------------------------- wire shapes

Map<String, dynamic> _profileJson(int id, String name, {bool mine = false}) => {
  'id': id,
  'full_name': name,
  'gender': 'bride',
  'age': 26,
  'status': 'active',
  'community': {'id': 1, 'name': 'Reddy'},
  'photos': [],
  'is_mine': mine,
  'can_edit': mine,
  'can_delete': mine,
  'contact_access': mine ? 'granted' : 'none',
};

Map<String, dynamic> _reportJson({
  int id = 9,
  String status = 'open',
  String? action,
  String? note,
  bool withProfile = true,
}) => {
  'id': id,
  'reason': 'scam_or_fraud',
  'details': 'Asked my client for money for a "visa fee"',
  'status': status,
  'action': action,
  'note': note,
  'created_at': '2026-11-13T08:00:00.000Z',
  'handled_at': status == 'open' ? null : '2026-11-13T12:00:00.000Z',
  'reports_on_profile': 3,
  'reporter': {'type': 'customer', 'id': 77, 'full_name': 'Priya Lakshmi', 'phone': '9000000077'},
  'profile': withProfile
      ? {
          'id': 102,
          'full_name': 'Sai Kiran Chowdary',
          'profile_code': 'GN-AP3C-A014',
          'status': 'active',
        }
      : null,
  'customer': {
    'id': 55,
    'full_name': 'Sai Kiran Chowdary',
    'phone': '9000000055',
    'status': 'active',
  },
  'agent': {'id': 8, 'full_name': 'Suresh Kumar', 'agent_code': 'AP3C', 'status': 'active'},
};

const _communities = [
  {'id': 1, 'name': 'Reddy'},
  {'id': 2, 'name': 'Kamma'},
];

// ---------------------------------------------------------------- fakes

class _FakeProfiles extends ProfileService {
  _FakeProfiles() : super(ApiClient());

  final reports = <(int, String, String?)>[];
  final blocked = <int>[];
  int listCalls = 0;
  ApiException? reportError;

  @override
  Future<MasterData> masters() async => MasterData.fromJson({
    'communities': _communities,
    'professions': [],
    'educations': [],
    'marital_statuses': [],
    'zodiac_signs': [],
    'nakshatrams': [],
  });

  @override
  Future<ProfilePage> list(Map<String, dynamic> query) async {
    listCalls++;
    return ProfilePage.fromJson({
      'profiles': [
        for (final id in [101, 102, 103])
          if (!blocked.contains(id)) _profileJson(id, 'Profile name $id'),
      ],
      'total': 3 - blocked.length,
      'page': 1,
    });
  }

  @override
  Future<Profile> detail(int id) async => Profile.fromJson(
    _profileJson(id, id == 101 ? 'Sravani Reddy' : 'Harika Rao', mine: id == 101),
  );

  @override
  Future<void> report(int id, {required String reason, String? details}) async {
    reports.add((id, reason, details));
    if (reportError != null) throw reportError!;
  }

  @override
  Future<void> block(int id) async => blocked.add(id);
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
  bool? acceptedTerms;

  @override
  Agent? get agent => me;

  @override
  bool get isAdmin => me?.isAdmin ?? false;

  @override
  NotificationFeed get notifications => feed;

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
    this.acceptedTerms = acceptedTerms;
  }
}

class _FakeAccount extends MyAccountService {
  _FakeAccount() : super(ApiClient());

  List<BlockedProfile> rows = [];
  final unblocked = <int>[];

  @override
  Future<MyCommunities> communities() async =>
      MyCommunities.fromJson({'communities': _communities, 'requests': []});

  @override
  Future<List<BlockedProfile>> blocks() async => [...rows];

  @override
  Future<void> unblock(int profileId) async {
    unblocked.add(profileId);
    rows.removeWhere((b) => b.profileId == profileId);
  }
}

class _FakeAdmin extends AdminService {
  _FakeAdmin() : super(ApiClient());

  Map<String, List<AdminReport>> byStatus = {};
  AdminStats statsResult = AdminStats.fromJson(const {});
  final statuses = <String>[];
  final actions = <(String, int, String?)>[];

  @override
  Future<AdminStats> stats() async => statsResult;

  @override
  Future<List<AdminReport>> reports({String status = 'open'}) async {
    statuses.add(status);
    return [...?byStatus[status]];
  }

  void _close(int id) => byStatus['open']?.removeWhere((r) => r.id == id);

  @override
  Future<void> dismissReport(int id, {String? note}) async {
    actions.add(('dismiss', id, note));
    _close(id);
  }

  @override
  Future<void> hideReportedProfile(int id, {String? note}) async {
    actions.add(('hide-profile', id, note));
    _close(id);
  }

  @override
  Future<void> suspendReportedAccount(int id, {String? note}) async {
    actions.add(('suspend-account', id, note));
    _close(id);
  }
}

class _FakeLauncher implements LinkLauncher {
  final launched = <Uri>[];

  @override
  Future<bool> launch(Uri uri) async {
    launched.add(uri);
    return true;
  }
}

/// Captures what AuthService posts.
class _CaptureApi extends ApiClient {
  Map<String, dynamic>? lastBody;

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    lastBody = body as Map<String, dynamic>?;
    return {
      'token': 't',
      'agent': {'id': 1, 'full_name': 'A', 'phone': '9000000001', 'status': 'pending'},
    };
  }

  @override
  Future<void> saveToken(String token) async {}
}

Agent _agent({bool admin = false}) => Agent.fromJson({
  'id': 4,
  'full_name': 'Ramesh Goud',
  'phone': '9849012345',
  'role': admin ? 'admin' : 'agent',
  'status': 'active',
  'communities': _communities,
  'agent_code': 'TS1A',
});

class _World {
  _World({bool admin = false}) {
    auth = _FakeAuth(_agent(admin: admin), profiles, authService);
    masters = MastersState(profiles);
    profilesState = ProfilesState(profiles);
  }

  final profiles = _FakeProfiles();
  final authService = _FakeAuthService();
  final account = _FakeAccount();
  final admin = _FakeAdmin();
  final launcher = _FakeLauncher();
  late final _FakeAuth auth;
  late final MastersState masters;
  late final ProfilesState profilesState;

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
      ChangeNotifierProvider<ProfilesState>.value(value: profilesState),
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

/// A list screen with a button that opens [id]'s detail, so the detail can pop.
Widget _launcher(int id) => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileId: id))),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  // ---------------------------------------------------------------- models

  group('parsing (SPEC §9.22)', () {
    test('report reasons: six wire values with labels', () {
      expect(ReportReason.values.map((r) => r.apiValue), [
        'fake_profile',
        'inappropriate_photo',
        'offensive_content',
        'scam_or_fraud',
        'harassment',
        'other',
      ]);
      expect(ReportReason.values.map((r) => r.label), [
        'Fake profile',
        'Inappropriate photo',
        'Offensive content',
        'Scam or fraud',
        'Harassment',
        'Other',
      ]);
      expect(ReportReason.labelOf('harassment'), 'Harassment');
      expect(ReportReason.labelOf('something_new'), 'something_new');
    });

    test('blocks', () {
      final b = BlockedProfile.fromJson(const {
        'profile_id': 102,
        'profile_label': 'Harika Rao',
        'created_at': '2026-11-13T08:00:00Z',
      });
      expect(b.profileId, 102);
      expect(b.label, 'Harika Rao');
      expect(b.createdAt, isNotNull);
      expect(BlockedProfile.fromJson(const {'profile_id': 7}).label, 'Profile 7');
    });

    test('admin reports: full row, deleted profile, counts', () {
      final r = AdminReport.fromJson(_reportJson());
      expect(r.id, 9);
      expect(r.isOpen, isTrue);
      expect(r.reasonLabel, 'Scam or fraud');
      expect(r.details, 'Asked my client for money for a "visa fee"');
      expect(r.reportsOnProfile, 3);
      expect(r.reporter!.isCustomer, isTrue);
      expect(r.reporter!.phone, '9000000077');
      expect(r.profile!.profileCode, 'GN-AP3C-A014');
      expect(r.profile!.status, 'active');
      expect(r.customer!.fullName, 'Sai Kiran Chowdary');
      expect(r.agent!.agentCode, 'AP3C');
      expect(r.createdAt, isNotNull);

      final gone = AdminReport.fromJson({
        ..._reportJson(status: 'actioned', action: 'profile_hidden', note: 'Photo removed'),
        'profile': null,
        'customer': null,
      });
      expect(gone.isOpen, isFalse);
      expect(gone.action, 'profile_hidden');
      expect(gone.note, 'Photo removed');
      expect(gone.profile, isNull);
      expect(gone.customer, isNull);
      expect(gone.handledAt, isNotNull);

      final bare = AdminReport.fromJson(const {'id': 1});
      expect(bare.reason, 'other');
      expect(bare.reportsOnProfile, 1);
      expect(bare.reporter, isNull);

      final feed = NotificationFeed.fromJson({
        'badge': 2,
        'items': [],
        'counts': {'reports_open': 2},
      });
      expect(feed.reportsOpen, 2);
      expect(feed.adminPending, 2);
      expect(AdminStats.fromJson({'reports_open': 5}).reportsOpen, 5);
      expect(AdminStats.fromJson(const {}).reportsOpen, 0);
      expect(ReasonDialog.isValidReason('', optional: true), isTrue);
      expect(ReasonDialog.isValidReason('ab', optional: true), isFalse);
      expect(ReasonDialog.isValidReason(''), isFalse);
    });

    test('routing: report_received → Reports, admins only, needs action', () {
      final item = NotificationItem.fromJson(const {
        'type': 'report_received',
        'id': 9,
        'title': 'Profile reported',
        'body': 'b',
      });
      expect(notificationTarget(item, isAdmin: true), const AdminReportsTarget());
      expect(notificationTarget(item, isAdmin: false), isNull);
      expect(notificationGroup('report_received', isAdmin: true), NotificationGroup.action);
      expect(notificationGroup('report_received', isAdmin: false), NotificationGroup.update);
      expect(screenForTarget(const AdminReportsTarget()), isA<AdminReportsScreen>());
    });
  });

  // ---------------------------------------------------------------- report / block

  group('profile detail: report and block (SPEC §9.22 A / B)', () {
    Future<void> openMenu(WidgetTester tester) async {
      await _tap(tester, find.byTooltip('More'));
    }

    testWidgets('not on my own uploads', (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const ProfileDetailScreen(profileId: 101)));
      await tester.pumpAndSettle();
      await openMenu(tester);
      expect(find.text(S.deleteProfile), findsOneWidget, reason: 'the menu is open');
      expect(find.text(S.reportProfile), findsNothing);
      expect(find.text(S.block), findsNothing);
    });

    testWidgets('report: a reason is required, details optional, server errors shown', (
      tester,
    ) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const ProfileDetailScreen(profileId: 102)));
      await tester.pumpAndSettle();
      await openMenu(tester);
      expect(find.text(S.block), findsOneWidget);
      await _tap(tester, find.text(S.reportProfile));

      expect(find.byType(ReportSheet), findsOneWidget);
      for (final r in ReportReason.values) {
        expect(find.text(r.label), findsOneWidget);
      }
      final send = find.widgetWithText(FilledButton, S.sendReport);
      expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'no reason yet');
      await _tap(tester, find.text('Scam or fraud'));
      await tester.enterText(
        find.widgetWithText(TextField, S.reportDetailsLabel),
        ' Asked for money ',
      );
      await _tap(tester, send);
      expect(w.profiles.reports, [(102, 'scam_or_fraud', 'Asked for money')]);
      expect(find.text(S.reportSent), findsOneWidget);

      // Again, without details, and the server says no.
      w.profiles.reportError = ApiException(
        'own_profile',
        'You cannot report your own profile',
        status: 400,
      );
      await openMenu(tester);
      await _tap(tester, find.text(S.reportProfile));
      await _tap(tester, find.text('Fake profile'));
      await _tap(tester, send);
      expect(w.profiles.reports.last, (102, 'fake_profile', ''));
      expect(find.text('You cannot report your own profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('block: confirm, then the profile leaves the list and the screen closes', (
      tester,
    ) async {
      _phone(tester);
      final w = _World();
      await w.profilesState.refresh();
      expect(w.profilesState.profiles.map((p) => p.id), [101, 102, 103]);
      await tester.pumpWidget(w.app(_launcher(102)));
      await _tap(tester, find.text('open'));
      expect(find.byType(ProfileDetailScreen), findsOneWidget);

      await openMenu(tester);
      await _tap(tester, find.text(S.block));
      expect(_inDialog(find.text(S.blockProfileBody)), findsOneWidget);
      await _tap(tester, _inDialog(find.widgetWithText(TextButton, S.cancel)));
      expect(w.profiles.blocked, isEmpty);

      await openMenu(tester);
      await _tap(tester, find.text(S.block));
      await _tap(tester, _inDialog(_button(S.block)));
      expect(w.profiles.blocked, [102]);
      expect(find.byType(ProfileDetailScreen), findsNothing, reason: 'popped');
      expect(find.text(S.profileBlocked), findsOneWidget);
      expect(w.profilesState.profiles.map((p) => p.id), [101, 103]);
    });
  });

  group('Settings → Blocked profiles (SPEC §9.22 B)', () {
    testWidgets('listed with Unblock; the list empties and the profiles reload', (tester) async {
      _phone(tester);
      final w = _World();
      w.account.rows = [
        BlockedProfile.fromJson(const {
          'profile_id': 102,
          'profile_label': 'Harika Rao',
          'created_at': '2026-11-13T08:00:00Z',
        }),
        BlockedProfile.fromJson(const {'profile_id': 105, 'profile_label': 'Kavya Gowda'}),
      ];
      await tester.pumpWidget(w.app(const SettingsScreen()));
      await tester.pumpAndSettle();
      final entry = find.text(S.blockedProfiles);
      await _scrollTo(tester, entry);
      await _tap(tester, entry);

      expect(find.byType(BlockedProfilesScreen), findsOneWidget);
      expect(find.text('Harika Rao'), findsOneWidget);
      expect(find.text(S.blockedOn('13 Nov 2026')), findsOneWidget);
      expect(find.text('Kavya Gowda'), findsOneWidget);

      final before = w.profiles.listCalls;
      await _tap(tester, find.widgetWithText(OutlinedButton, S.unblock).first);
      expect(w.account.unblocked, [102]);
      expect(find.text('Harika Rao'), findsNothing);
      expect(find.text(S.unblocked('Harika Rao')), findsOneWidget);
      expect(w.profiles.listCalls, before + 1, reason: 'the list reloads');

      await _tap(tester, find.widgetWithText(OutlinedButton, S.unblock));
      expect(w.account.unblocked, [102, 105]);
      expect(find.text(S.noBlockedProfiles), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------- terms

  group('signup: Terms consent (SPEC §9.22 C)', () {
    testWidgets('links open the pages; signup waits for the tick; accepted_terms is sent', (
      tester,
    ) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const SignupScreen()));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, S.phone), '9000000001');
      await _tap(tester, _button(S.sendOtp));
      await tester.enterText(find.widgetWithText(TextFormField, S.otpCode), '123456');
      await _tap(tester, _button(S.verifyOtp));
      await tester.enterText(find.widgetWithText(TextFormField, S.fullName), 'New Agent');
      await tester.enterText(find.widgetWithText(TextFormField, S.password), 'secret1');
      await tester.enterText(find.widgetWithText(TextFormField, S.confirmPassword), 'secret1');
      await _tap(tester, find.widgetWithText(FilterChip, 'Reddy'));

      final signup = _button(S.signup);
      await tester.ensureVisible(signup);
      expect(tester.widget<FilledButton>(signup).onPressed, isNull, reason: 'not ticked');

      await _tap(tester, find.text(S.termsLink));
      await _tap(tester, find.text(S.privacyLink));
      expect(w.launcher.launched, [Uri.parse(AppConfig.termsUrl), Uri.parse(AppConfig.privacyUrl)]);
      expect(AppConfig.termsUrl, '${AppConfig.apiBaseUrl}/terms');
      expect(AppConfig.privacyUrl, '${AppConfig.apiBaseUrl}/privacy/agent');
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox)).value,
        isFalse,
        reason: 'a link does not tick the box',
      );

      await _tap(tester, find.byType(Checkbox));
      expect(tester.widget<FilledButton>(signup).onPressed, isNotNull);
      await _tap(tester, find.byType(Checkbox));
      expect(tester.widget<FilledButton>(signup).onPressed, isNull, reason: 'untick disables');
      await _tap(tester, find.byType(Checkbox));
      await _tap(tester, signup);
      expect(w.auth.acceptedTerms, isTrue);
      expect(tester.takeException(), isNull);
    });

    test('POST /auth/signup carries accepted_terms only when accepted', () async {
      final api = _CaptureApi();
      final service = AuthService(api);
      Future<void> signup(bool accepted) => service.signup(
        fullName: 'A',
        phone: '9000000001',
        password: 'secret1',
        communityIds: const [1],
        phoneVerificationToken: 'tok',
        acceptedTerms: accepted,
      );
      await signup(true);
      expect(api.lastBody!['accepted_terms'], isTrue);
      await signup(false);
      expect(api.lastBody!.containsKey('accepted_terms'), isFalse);
    });
  });

  // ---------------------------------------------------------------- admin

  group('admin: Reports (SPEC §9.22 A)', () {
    testWidgets('rows, call, open profile, dismiss / hide / suspend with notes, filters', (
      tester,
    ) async {
      _phone(tester, const Size(420, 1500));
      final w = _World(admin: true);
      w.admin.byStatus = {
        'open': [
          AdminReport.fromJson(_reportJson()),
          AdminReport.fromJson({..._reportJson(id: 10), 'reason': 'inappropriate_photo'}),
          AdminReport.fromJson({..._reportJson(id: 11), 'reason': 'fake_profile'}),
        ],
        'actioned': [
          AdminReport.fromJson(
            _reportJson(
              id: 5,
              status: 'actioned',
              action: 'account_suspended',
              note: 'Confirmed scam',
            ),
          ),
        ],
        'dismissed': [],
        'all': [],
      };
      await tester.pumpWidget(w.app(const AdminReportsScreen()));
      await tester.pumpAndSettle();

      expect(w.admin.statuses, ['open']);
      expect(find.text('Scam or fraud'), findsOneWidget);
      expect(find.text('Inappropriate photo'), findsOneWidget);
      expect(find.text('Fake profile'), findsOneWidget);
      expect(find.text('"Asked my client for money for a "visa fee""'), findsNWidgets(3));
      expect(find.text('Sai Kiran Chowdary'), findsNWidgets(3));
      expect(find.text('ID GN-AP3C-A014'), findsNWidgets(3));
      expect(
        find.textContaining('${S.reportedBy}: Priya Lakshmi (${S.reporterFamily})'),
        findsNWidgets(3),
      );
      expect(find.textContaining('${S.uploadedByLabel}: Suresh Kumar (AP3C)'), findsNWidgets(3));
      expect(find.textContaining('${S.familyLabel}: Sai Kiran Chowdary'), findsNWidgets(3));
      expect(find.textContaining(S.reportsOnProfile(3)), findsNWidgets(3));

      // Tap the reporter's number to call.
      await _tap(tester, find.text('+91 9000000077').first);
      expect(w.launcher.launched, [Uri.parse('tel:+919000000077')]);

      // Dismiss with no note.
      await _tap(tester, find.widgetWithText(OutlinedButton, S.dismiss).first);
      expect(_inDialog(find.text(S.dismissReportBody)), findsOneWidget);
      await _tap(tester, _inDialog(_button(S.dismiss)));
      expect(w.admin.actions, [('dismiss', 9, null)]);
      expect(find.text(S.reportDismissed), findsOneWidget);

      // Hide the profile, with a note.
      await _tap(tester, find.widgetWithText(OutlinedButton, S.hideProfile).first);
      expect(_inDialog(find.text(S.hideProfileBody)), findsOneWidget);
      await tester.enterText(_inDialog(find.byType(TextFormField)), 'Nude photo removed');
      await _tap(tester, _inDialog(_button(S.hideProfile)));
      expect(w.admin.actions.last, ('hide-profile', 10, 'Nude photo removed'));

      // Suspend: says whose account; cancel sends nothing.
      await _tap(tester, _button(S.suspendAccount).first);
      expect(
        _inDialog(
          find.text(
            "Suspends the family's account (or the uploading agent if there is no family "
            'account) and hides the profile.',
          ),
        ),
        findsOneWidget,
      );
      await _tap(tester, _inDialog(find.widgetWithText(TextButton, S.cancel)));
      expect(w.admin.actions, hasLength(2));
      await _tap(tester, _button(S.suspendAccount).first);
      await _tap(tester, _inDialog(_button(S.suspendAccount)));
      expect(w.admin.actions.last, ('suspend-account', 11, null));
      expect(find.text(S.noOpenReports), findsOneWidget);

      // Filters; a handled report shows its action and note, no buttons.
      await _tap(tester, find.widgetWithText(ChoiceChip, S.filterActioned));
      expect(w.admin.statuses.last, 'actioned');
      expect(find.text(S.actionAccountSuspended), findsOneWidget);
      expect(find.text('${S.noteLabel}: Confirmed scam'), findsOneWidget);
      expect(find.textContaining(S.handledOn), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, S.dismiss), findsNothing);

      // Tapping the profile opens it.
      await _tap(tester, find.text('Sai Kiran Chowdary'));
      expect(find.byType(ProfileDetailScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _tap(tester, find.widgetWithText(ChoiceChip, S.filterDismissed));
      expect(w.admin.statuses.last, 'dismissed');
      expect(find.text(S.noReportsInList), findsOneWidget);
      await _tap(tester, find.widgetWithText(ChoiceChip, S.filterAll));
      expect(w.admin.statuses.last, 'all');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a deleted profile: no profile actions', (tester) async {
      _phone(tester, const Size(420, 900));
      final w = _World(admin: true);
      w.admin.byStatus = {
        'open': [AdminReport.fromJson(_reportJson(withProfile: false))],
      };
      await tester.pumpWidget(w.app(const AdminReportsScreen()));
      await tester.pumpAndSettle();
      expect(find.text(S.profileDeletedLabel), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, S.hideProfile)).onPressed,
        isNull,
      );
      expect(tester.widget<FilledButton>(_button(S.suspendAccount)).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, S.dismiss)).onPressed,
        isNotNull,
      );
    });

    testWidgets('badge on More and the Admin home; report_received opens Reports', (tester) async {
      SharedPreferences.setMockInitialValues({});
      _phone(tester);
      final w = _World(admin: true);
      w.admin.byStatus = {
        'open': [AdminReport.fromJson(_reportJson())],
      };
      w.auth.feed = NotificationFeed.fromJson({
        'badge': 2,
        'items': [
          {
            'type': 'report_received',
            'id': 9,
            'title': 'Profile reported',
            'body': 'Sai Kiran Chowdary — Scam or fraud',
            'at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
        'counts': {'reports_open': 2},
      });

      await tester.pumpWidget(w.app(const MoreScreen()));
      await tester.pump();
      expect(find.text(S.reportsCount(2)), findsOneWidget);
      expect(
        find.descendant(of: find.widgetWithText(ListTile, S.admin), matching: find.text('2')),
        findsOneWidget,
      );

      w.admin.statsResult = AdminStats.fromJson({'reports_open': 4});
      await tester.pumpWidget(w.app(const AdminHomeScreen()));
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, S.reports);
      await _scrollTo(tester, tile);
      expect(find.descendant(of: tile, matching: find.text('4')), findsOneWidget);

      await tester.pumpWidget(w.app(const NotificationsScreen(key: ValueKey('n'))));
      await tester.pumpAndSettle();
      expect(find.text(S.needsYourAction.toUpperCase()), findsOneWidget);
      await _tap(tester, find.text('Profile reported'));
      expect(find.byType(AdminReportsScreen), findsOneWidget);
      expect(find.text('Scam or fraud'), findsOneWidget);
    });
  });
}
