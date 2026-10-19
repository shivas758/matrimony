import 'package:flutter/material.dart';
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
import 'package:gandharva/state/browse_filters.dart';
import 'package:gandharva/ui/screens/auth/blocked_screen.dart';
import 'package:gandharva/ui/screens/browse/filter_sheet.dart';
import 'package:gandharva/ui/screens/get_started/get_started_screen.dart';
import 'package:gandharva/ui/screens/my_profile/my_profiles_screen.dart';
import 'package:gandharva/ui/screens/payment/checkout_screen.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:provider/provider.dart';

import 'guest_mode_test.dart' show activeMeJson, guestMeJson;

/// AuthState with a fixed customer and no network.
class _FakeAuth extends AuthState {
  _FakeAuth(this._c, ApiClient api) : super(api: api, auth: CustomerAuthService(api));

  final Customer _c;

  @override
  Customer? get customer => _c;

  @override
  Future<bool> refresh() async => true;

  @override
  Future<void> refreshCustomer() async {}
}

/// Own-profile views without the network: profile 77 has a pending deletion request.
class _FakeProfiles extends ProfileService {
  _FakeProfiles(super.api);

  static Profile _priya() => Profile.fromJson({
        'id': 77,
        'full_name': 'Priya',
        'gender': 'bride',
        'paid': true,
        'visibility': 'live',
        'delete_request': {'id': 4, 'status': 'pending', 'reason': null, 'created_at': '2026-09-28T12:00:00Z'},
      });

  @override
  Future<List<Profile>> myProfiles() async => [_priya()];

  @override
  Future<Profile> myProfile(int id) async => _priya();

  /// No network: the profile page loads the masters when it opens.
  @override
  Future<MasterData> masters() async => MasterData.fromJson(const {});
}

Widget _host(Customer customer, Widget child) {
  final api = ApiClient();
  final profiles = _FakeProfiles(api);
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      Provider<ProfileService>.value(value: profiles),
      Provider<AgentsService>.value(value: AgentsService(api)),
      Provider<PaymentService>.value(value: PaymentService(api)),
      ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profiles)),
      ChangeNotifierProvider<AuthState>(create: (_) => _FakeAuth(customer, api)),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}

Future<void> _render(WidgetTester tester, Customer customer, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(customer, child));
  await tester.pump();
}

/// Replaces the tree so periodic timers (Get started polls) are disposed.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  final guest = Customer.fromJson(guestMeJson());
  final pendingUnpaid = Customer.fromJson({
    ...activeMeJson(),
    'status': 'pending',
    'access': 'guest',
    'profiles': [
      {
        'id': 80,
        'full_name': 'Sita',
        'gender': 'bride',
        'age': 24,
        'community': {'id': 1, 'name': 'Kamma'},
        'status': 'hidden',
        'photo_url': null,
        'paid': false,
        'paid_at': null,
        'visibility': 'payment_pending',
      },
    ],
    'unlock': {'agent_linked': true, 'profile_registered': true, 'paid': false, 'approved': false},
  });
  final active = Customer.fromJson(activeMeJson());

  testWidgets('Get started — guest: step 1 open with the phone field', (tester) async {
    await _render(tester, guest, const GetStartedScreen());
    expect(find.text(S.step1Title), findsOneWidget);
    expect(find.text(S.agentPhoneLink), findsOneWidget);
    expect(find.text(S.pickFromDirectory), findsOneWidget);
    expect(find.text(S.needAgentFirst), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets('Get started — pending with an unpaid profile: agent + Change + Pay', (tester) async {
    await _render(tester, pendingUnpaid, const GetStartedScreen());
    expect(find.text('Agent A'), findsWidgets);
    expect(find.text(S.change), findsOneWidget);
    expect(find.text(S.payFee(150)), findsNWidgets(2), reason: 'step title + button');
    // Step 4 sits below the fold of the lazily built list.
    await tester.scrollUntilVisible(find.text(S.step4Waiting('Agent A')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(S.step4Waiting('Agent A')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets('Get started — full access says all set', (tester) async {
    await _render(tester, active, const GetStartedScreen());
    expect(find.text(S.allSetTitle), findsOneWidget);
    expect(find.text(S.change), findsNothing, reason: 'active customers use Change agent');
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets('My profile — the one profile opens right in the tab (SPEC §9.17)', (tester) async {
    final one = Customer.fromJson({
      ...activeMeJson(),
      'max_profiles': 1,
      'profiles': [(activeMeJson()['profiles'] as List).first],
    });
    await _render(tester, one, const MyProfilesScreen());
    await tester.pump(); // my-profile answered
    expect(find.text('Priya'), findsWidgets, reason: 'the page title is the profile name');
    expect(find.text(S.visibilityTitle('live')), findsOneWidget);
    expect(find.text(S.deletionRequestedTitle), findsOneWidget);
    expect(find.text(S.addProfile), findsNothing, reason: 'one profile per customer');
    expect(find.byType(BackButton), findsNothing, reason: 'a tab, not a pushed page');
    expect(tester.takeException(), isNull);
    await _dispose(tester);
  });

  testWidgets('My profile — guest: empty state, Create profile disabled with a hint', (tester) async {
    await _render(tester, guest, const MyProfilesScreen());
    expect(find.text(S.noProfilesYetTitle), findsOneWidget);
    expect(find.text(S.addProfileNeedsAgent), findsWidgets);
    final add = tester.widget<ButtonStyleButton>(
      find.ancestor(of: find.text(S.addProfile), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
    );
    expect(add.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Checkout (mock) shows the amount from the API and the test-mode note', (tester) async {
    await _render(tester, pendingUnpaid, const CheckoutScreen(profileId: 80, profileName: 'Sita'));
    expect(find.text('₹150'), findsOneWidget);
    expect(find.text(S.testModeNoCharge), findsOneWidget);
    expect(find.text(S.payFee(150)), findsOneWidget);
    expect(find.text(S.simulateFailure), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Checkout with another provider never offers to pay', (tester) async {
    final razor = Customer.fromJson({...guestMeJson(), 'payment_provider': 'razorpay'});
    await _render(tester, razor, const CheckoutScreen(profileId: 80, profileName: 'Sita'));
    expect(find.text(S.paymentComingSoon), findsOneWidget);
    expect(find.text(S.simulateFailure), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Blocked (suspended) screen renders with the agent', (tester) async {
    final suspended = Customer.fromJson({...activeMeJson(), 'status': 'suspended'});
    await _render(tester, suspended, const BlockedScreen());
    expect(find.text(S.suspendedTitle), findsOneWidget);
    expect(find.text('Agent A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Filter sheet for guests shows the place filter but not sort-by-name', (tester) async {
    await _render(
      tester,
      guest,
      const Scaffold(body: FilterSheet(initial: BrowseFilters.empty, communities: [], guest: true)),
    );
    await tester.scrollUntilVisible(find.text(S.place.toUpperCase()), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(S.place.toUpperCase()), findsOneWidget);
    expect(find.text(S.placeHint), findsOneWidget);
    await tester.scrollUntilVisible(find.text(S.sortNewest), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text(S.sortName), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
