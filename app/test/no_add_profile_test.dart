import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/agent.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/models/notifications.dart';
import 'package:matrimony_agents/models/profile.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/state/auth_state.dart';
import 'package:matrimony_agents/state/home_nav.dart';
import 'package:matrimony_agents/state/masters_state.dart';
import 'package:matrimony_agents/state/profiles_state.dart';
import 'package:matrimony_agents/ui/screens/profiles/my_uploads_screen.dart';
import 'package:matrimony_agents/ui/screens/profiles/profile_list_screen.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SPEC §9.24 A (release 3.5.0): agents no longer add profiles — no Add
/// button on Profiles or My uploads, and the empty states point to the
/// families instead of a + button.

Map<String, dynamic> _profileJson(int id, String name) => {
      'id': id,
      'full_name': name,
      'gender': 'bride',
      'status': 'active',
      'age': 27,
      'community': {'id': 1, 'name': 'Reddy'},
      'photos': [],
      'is_mine': true,
      'profile_code': 'GN-KA1A-A00$id',
    };

class _FakeProfiles extends ProfileService {
  _FakeProfiles() : super(ApiClient());

  List<Map<String, dynamic>> rows = [];
  final queries = <Map<String, dynamic>>[];

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
    queries.add(query);
    final status = query['status'];
    final matching = [for (final r in rows) if (status == null || r['status'] == status) r];
    return ProfilePage.fromJson({'profiles': matching, 'total': matching.length, 'page': 1});
  }

  @override
  Future<NotificationFeed> notifications() async => NotificationFeed.empty;
}

class _FakeAuth extends AuthState {
  _FakeAuth(this.me, ProfileService profiles)
      : super(api: ApiClient(), auth: AuthService(ApiClient()), profiles: profiles);

  final Agent me;

  @override
  Agent? get agent => me;

  @override
  Future<void> refreshNotifications() async {}
}

/// An approved agent, so the "not approved yet" banner stays out of the way.
final _agent = Agent.fromJson(const {
  'id': 4,
  'full_name': 'Lakshmi Devi',
  'phone': '9000000004',
  'role': 'agent',
  'status': 'active',
  'communities': [
    {'id': 1, 'name': 'Reddy'},
  ],
  'agent_code': 'KA1A',
  'approved': true,
  'live_clients': 12,
  'approval_clients': 10,
});

class _World {
  _World() : profilesState = ProfilesState(profiles) {
    auth = _FakeAuth(_agent, profiles);
  }

  static final profiles = _FakeProfiles();
  final ProfilesState profilesState;
  late final _FakeAuth auth;

  Widget app(Widget home) => MultiProvider(
        providers: [
          Provider<ApiClient>(create: (_) => ApiClient()),
          Provider<ProfileService>.value(value: profiles),
          ChangeNotifierProvider<HomeNav>(create: (_) => HomeNav()),
          ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profiles)),
          ChangeNotifierProvider<ProfilesState>.value(value: profilesState),
          ChangeNotifierProvider<AuthState>.value(value: auth),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Nothing on screen that would add a profile.
void _expectNoAddButton() {
  expect(find.byType(FloatingActionButton), findsNothing);
  expect(find.text('Add profile'), findsNothing);
  expect(find.byIcon(Icons.add_rounded), findsNothing);
  expect(find.textContaining('+ button'), findsNothing);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _World.profiles
      ..rows = []
      ..queries.clear();
  });

  group('Profiles tab', () {
    testWidgets('no Add profile button; the empty state points to families', (tester) async {
      _phone(tester);
      final w = _World();
      await w.profilesState.refresh();
      await tester.pumpWidget(w.app(const ProfileListScreen()));
      await tester.pumpAndSettle();

      _expectNoAddButton();
      expect(find.text(S.noProfiles), findsOneWidget);
      expect(find.text(S.noProfilesHint), findsOneWidget);
      expect(S.noProfilesHint, contains(S.customerAppName));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with profiles: the grid, still no Add button', (tester) async {
      _phone(tester);
      _World.profiles.rows = [_profileJson(1, 'Sravani Reddy'), _profileJson(2, 'Anusha Reddy')];
      final w = _World();
      await w.profilesState.refresh();
      await tester.pumpWidget(w.app(const ProfileListScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Sravani Reddy'), findsOneWidget);
      expect(find.text('Anusha Reddy'), findsOneWidget);
      _expectNoAddButton();
      expect(tester.takeException(), isNull);
    });
  });

  group('My uploads', () {
    testWidgets('no Add profile button; the empty state says clients add their profiles',
        (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app(const MyUploadsScreen()));
      await tester.pumpAndSettle();

      expect(_World.profiles.queries.single['mine'], 'true');
      _expectNoAddButton();
      expect(find.text(S.noUploads), findsOneWidget);
      expect(find.text(S.noUploadsHint), findsOneWidget);
      expect(find.text('You have not added any profiles yet'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets("my clients' profiles are listed; an empty status filter says so", (tester) async {
      _phone(tester);
      _World.profiles.rows = [_profileJson(1, 'Sravani Reddy')];
      final w = _World();
      await tester.pumpWidget(w.app(const MyUploadsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Sravani Reddy'), findsOneWidget);
      expect(find.text('ID GN-KA1A-A001'), findsOneWidget);
      _expectNoAddButton();

      final married = find.widgetWithText(ChoiceChip, ProfileStatus.married.label);
      await tester.ensureVisible(married);
      await tester.pumpAndSettle();
      await tester.tap(married);
      await tester.pumpAndSettle();
      expect(_World.profiles.queries.last['status'], 'married');
      expect(find.text('Sravani Reddy'), findsNothing);
      expect(find.text(S.noMatches), findsOneWidget);
      expect(find.text(S.noUploads), findsNothing);
      _expectNoAddButton();
    });
  });
}
