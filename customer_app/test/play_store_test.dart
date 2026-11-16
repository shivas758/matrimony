import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/config.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/models/master_data.dart';
import 'package:gandharva/models/profile.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/services/customer_auth_service.dart';
import 'package:gandharva/services/link_launcher.dart';
import 'package:gandharva/services/payment_service.dart';
import 'package:gandharva/services/profile_service.dart';
import 'package:gandharva/services/razorpay_gateway.dart';
import 'package:gandharva/services/upi_launcher.dart';
import 'package:gandharva/state/auth_state.dart';
import 'package:gandharva/state/masters_state.dart';
import 'package:gandharva/ui/screens/auth/blocked_screen.dart';
import 'package:gandharva/ui/screens/get_started/get_started_screen.dart';
import 'package:gandharva/ui/screens/more_screen.dart';
import 'package:gandharva/ui/screens/my_profile/my_profile_screen.dart';
import 'package:gandharva/ui/screens/payment/checkout_screen.dart';
import 'package:gandharva/ui/screens/payment/upi_checkout.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:provider/provider.dart';

import 'guest_mode_test.dart' show activeMeJson, guestMeJson;
import 'upi_payment_test.dart' show rowPaymentJson, upiMeJson, upiPaymentJson;
import 'wedbook_test.dart' show mastersJson, ownProfileJson;

// SPEC §9.20 F (Delete my account) and G (the Google Play build).

const _orderPath = '/customer/my-profiles/80/payment';

/// Answers POSTs from per-path queues; records every call.
class _FakeApi extends ApiClient {
  final List<String> posts = [];
  final Map<String, Map<String, dynamic>> _answers = {};

  void answer(String path, Map<String, dynamic> reply) => _answers[path] = reply;

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    posts.add(path);
    final reply = _answers[path];
    if (reply == null) throw StateError('unexpected POST $path');
    return reply;
  }

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async =>
      throw ApiException('network_error', 'offline');

  @override
  Future<String?> readToken() async => 'jwt';

  @override
  String? get tokenSync => 'jwt';
}

class _FakeUpiLauncher implements UpiLauncher {
  final opened = <String>[];

  @override
  Future<bool> open(String uri) async {
    opened.add(uri);
    return true;
  }
}

class _FakeRazorpay implements RazorpayGateway {
  int opened = 0;

  @override
  Future<RazorpayOutcome> open(Map<String, dynamic> options) async {
    opened++;
    return const RazorpayCancelled();
  }
}

class _FakeLinks implements LinkLauncher {
  _FakeLinks({this.opens = true});

  final bool opens;
  final opened = <Uri>[];

  @override
  Future<bool> openExternal(Uri uri) async {
    opened.add(uri);
    return opens;
  }
}

class _FixedAuth extends AuthState {
  _FixedAuth(this._c, ApiClient api) : super(api: api, auth: CustomerAuthService(api));

  final Customer _c;

  @override
  Customer? get customer => _c;

  @override
  AgentCard? get agent => _c.agent;

  @override
  bool get isSuspended => _c.isSuspended;

  @override
  Future<bool> refresh() async => true;

  @override
  Future<void> refreshCustomer() async {}
}

class _FakeProfiles extends ProfileService {
  _FakeProfiles(super.api, this.own);

  final Map<String, dynamic> own;

  @override
  Future<MasterData> masters() async => MasterData.fromJson(mastersJson());

  @override
  Future<Profile> myProfile(int id) async => Profile.fromJson(own);
}

class _Host {
  _Host(Map<String, dynamic> me, {required this.playStore, Map<String, dynamic>? own, bool linkOpens = true}) {
    auth = _FixedAuth(Customer.fromJson(me), api);
    profiles = _FakeProfiles(api, own ?? ownProfileJson());
    links = _FakeLinks(opens: linkOpens);
  }

  final bool playStore;
  final api = _FakeApi();
  final upi = _FakeUpiLauncher();
  final razorpay = _FakeRazorpay();
  late final _FixedAuth auth;
  late final _FakeProfiles profiles;
  late final _FakeLinks links;

  Widget wrap(Widget home) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<PaymentService>.value(value: PaymentService(api, playStore: playStore)),
          Provider<ProfileService>.value(value: profiles),
          Provider<RazorpayGateway>.value(value: razorpay),
          Provider<UpiLauncher>.value(value: upi),
          Provider<LinkLauncher>.value(value: links),
          ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profiles)),
          ChangeNotifierProvider<AuthState>.value(value: auth),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder f) =>
    tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);

/// My profile 80, unpaid.
Map<String, dynamic> _unpaidOwn(Map<String, dynamic>? payment) => {
      ...ownProfileJson(),
      'id': 80,
      'full_name': 'Sita',
      'paid': false,
      'paid_at': null,
      'visibility': 'payment_pending',
      'payment': payment,
    };

void main() {
  // ================================================================ G. Play build

  group('Play build flag (SPEC §9.20 G)', () {
    test('a normal build is not the Play build; the service defaults to the flag', () {
      expect(kPlayStore, isFalse, reason: 'no --dart-define=STORE=play in tests');
      expect(PaymentService(_FakeApi()).playStore, kPlayStore);
    });

    test('Play build: only mock is paid in the app; elsewhere razorpay and upi too', () {
      for (final p in ['upi', 'razorpay', 'cashfree']) {
        expect(PaymentService.supportsInApp(p, playStore: true), isFalse, reason: p);
      }
      expect(PaymentService.supportsInApp('mock', playStore: true), isTrue);
      for (final p in ['upi', 'razorpay', 'mock']) {
        expect(PaymentService.supportsInApp(p, playStore: false), isTrue, reason: p);
      }
      expect(PaymentService.supportsInApp('cashfree', playStore: false), isFalse);

      final play = PaymentService(_FakeApi(), playStore: true);
      final apk = PaymentService(_FakeApi(), playStore: false);
      expect(play.canPayInApp('upi'), isFalse);
      expect(apk.canPayInApp('upi'), isTrue);
      expect(play.offersPayment('upi'), isFalse);
      expect(play.offersPayment('razorpay'), isFalse);
      expect(play.offersPayment('mock'), isTrue);
      expect(apk.offersPayment('upi'), isTrue);
      expect(apk.offersPayment('cashfree'), isTrue, reason: 'the APK keeps "coming soon" as before');
    });

    for (final provider in ['upi', 'razorpay']) {
      testWidgets('Play build checkout for $provider: the neutral notice only — no order, no pay', (tester) async {
        await _phone(tester);
        final host = _Host(upiMeJson(provider: provider), playStore: true);
        await tester.pumpWidget(host.wrap(const CheckoutScreen(profileId: 80, profileName: 'Sita')));
        await _settle(tester);
        expect(find.text(S.paymentUnavailable), findsOneWidget);
        expect(find.text(S.paymentComingSoon), findsNothing, reason: 'no "contact your agent"');
        expect(find.text(S.payFee(150)), findsNothing);
        expect(find.byType(UpiCheckout), findsNothing);
        expect(find.text(S.razorpaySecure), findsNothing);
        expect(host.api.posts, isEmpty);
        expect(host.upi.opened, isEmpty);
        expect(host.razorpay.opened, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the same checkout outside the Play build is the UPI page', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson(), playStore: false);
      host.api.answer(_orderPath, {'payment': upiPaymentJson('created')});
      await tester.pumpWidget(host.wrap(const CheckoutScreen(profileId: 80, profileName: 'Sita')));
      await _settle(tester);
      expect(find.text(S.paymentUnavailable), findsNothing);
      expect(find.text(S.payWithUpiApp(150)), findsOneWidget);
      expect(host.api.posts, [_orderPath]);
    });

    testWidgets('Play build keeps the mock checkout for dev', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson(provider: 'mock'), playStore: true);
      await tester.pumpWidget(host.wrap(const CheckoutScreen(profileId: 80, profileName: 'Sita')));
      await _settle(tester);
      expect(find.text(S.testModeNoCharge), findsOneWidget);
      expect(find.text(S.payFee(150)), findsOneWidget);
      expect(find.text(S.paymentUnavailable), findsNothing);
    });

    testWidgets('Play build My profile: no Pay / Fix / status button, no UPI state, a neutral note', (tester) async {
      await _phone(tester);
      final submitted = rowPaymentJson('submitted');
      final host = _Host(upiMeJson(payment: submitted), playStore: true, own: _unpaidOwn(submitted));
      await tester.pumpWidget(host.wrap(const MyProfileScreen(profileId: 80)));
      await tester.pump();
      await tester.pump();
      expect(find.text(S.visibilityTitle('payment_pending')), findsOneWidget);
      expect(find.text(S.paymentUnavailable), findsOneWidget);
      for (final label in [S.payFee(150), S.viewPaymentStatus, S.fixPayment]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.text(S.upiUnderReviewTitle), findsNothing);
      expect(find.byType(UpiUnderReviewCard), findsNothing);
      await _scrollTo(tester, find.text(S.chipFeeNotPaid));
      expect(find.text(S.chipFeeNotPaid), findsOneWidget);
      expect(find.text(S.chipPay(150)), findsNothing);
      expect(find.text(S.chipVerifyingPayment), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the same profile outside the Play build shows the UPI state and its button', (tester) async {
      await _phone(tester);
      final submitted = rowPaymentJson('submitted');
      final host = _Host(upiMeJson(payment: submitted), playStore: false, own: _unpaidOwn(submitted));
      await tester.pumpWidget(host.wrap(const MyProfileScreen(profileId: 80)));
      await tester.pump();
      await tester.pump();
      expect(find.text(S.upiUnderReviewTitle), findsOneWidget);
      expect(find.text(S.viewPaymentStatus), findsOneWidget);
      expect(find.text(S.paymentUnavailable), findsNothing);
    });

    testWidgets('Play build Get started: "Registration fee", the neutral note, no button', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson(payment: rowPaymentJson('failed', reason: 'x')), playStore: true);
      await tester.pumpWidget(host.wrap(const GetStartedScreen()));
      await tester.pump();
      await _scrollTo(tester, find.text(S.paymentUnavailable));
      expect(find.text(S.step3TitleNoPayment), findsOneWidget);
      expect(find.text(S.paymentUnavailable), findsOneWidget);
      for (final label in [S.payFee(150), S.viewPaymentStatus, S.fixPayment]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(find.textContaining('Payment not verified'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // ================================================================ F. Delete my account

  group('Delete my account (SPEC §9.20 F)', () {
    final deletionPage = Uri.parse('${AppConfig.apiBaseUrl}/delete-account?app=customer');

    test('the page is the API domain\'s /delete-account for this app', () {
      expect(AppConfig.deleteAccountUrl, '${AppConfig.apiBaseUrl}/delete-account?app=customer');
    });

    final states = <String, Map<String, dynamic>>{
      'guest': guestMeJson(),
      'pending': {...activeMeJson(), 'status': 'pending', 'access': 'guest'},
      'active': activeMeJson(),
    };
    for (final MapEntry(key: state, value: me) in states.entries) {
      testWidgets('More shows it for a $state customer', (tester) async {
        await _phone(tester);
        final host = _Host(me, playStore: false);
        await tester.pumpWidget(host.wrap(const MoreScreen()));
        await _scrollTo(tester, find.text(S.deleteAccount));
        expect(find.text(S.deleteAccount), findsOneWidget);
        expect(find.text(S.deleteAccountSubtitle), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a suspended customer gets it on the blocked screen', (tester) async {
      await _phone(tester);
      final host = _Host({...activeMeJson(), 'status': 'suspended'}, playStore: false);
      await tester.pumpWidget(host.wrap(const BlockedScreen()));
      await _scrollTo(tester, find.text(S.deleteAccount));
      expect(find.text(S.deleteAccount), findsOneWidget);
      expect(find.text(S.deleteAccountSubtitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirm → the deletion page opens in the browser', (tester) async {
      await _phone(tester);
      final host = _Host(activeMeJson(), playStore: false);
      await tester.pumpWidget(host.wrap(const MoreScreen()));
      await _scrollTo(tester, find.text(S.deleteAccount));
      await tester.tap(find.text(S.deleteAccount));
      await _settle(tester);
      expect(find.text(S.deleteAccountBody), findsOneWidget);
      expect(host.links.opened, isEmpty, reason: 'nothing opens before confirming');

      await tester.tap(find.text(S.openDeletionPage));
      await _settle(tester);
      expect(host.links.opened, [deletionPage]);
      expect(find.text(S.deleteAccountBody), findsNothing);
    });

    testWidgets('Cancel opens nothing', (tester) async {
      await _phone(tester);
      final host = _Host(activeMeJson(), playStore: false);
      await tester.pumpWidget(host.wrap(const MoreScreen()));
      await _scrollTo(tester, find.text(S.deleteAccount));
      await tester.tap(find.text(S.deleteAccount));
      await _settle(tester);
      await tester.tap(find.text(S.cancel));
      await _settle(tester);
      expect(host.links.opened, isEmpty);
      expect(find.text(S.deleteAccountBody), findsNothing);
    });

    testWidgets('from the suspended screen too; no browser → a message', (tester) async {
      await _phone(tester);
      final host = _Host({...activeMeJson(), 'status': 'suspended'}, playStore: true, linkOpens: false);
      await tester.pumpWidget(host.wrap(const BlockedScreen()));
      await _scrollTo(tester, find.text(S.deleteAccount));
      await tester.tap(find.text(S.deleteAccount));
      await _settle(tester);
      await tester.tap(find.text(S.openDeletionPage));
      await _settle(tester);
      expect(host.links.opened, [deletionPage]);
      expect(find.text(S.linkOpenFailed), findsOneWidget);
    });
  });
}
