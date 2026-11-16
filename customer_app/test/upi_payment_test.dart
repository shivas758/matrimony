import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/models/master_data.dart';
import 'package:gandharva/models/notification.dart';
import 'package:gandharva/models/payment.dart';
import 'package:gandharva/models/profile.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/services/customer_auth_service.dart';
import 'package:gandharva/services/payment_service.dart';
import 'package:gandharva/services/profile_service.dart';
import 'package:gandharva/services/push_service.dart';
import 'package:gandharva/services/razorpay_gateway.dart';
import 'package:gandharva/services/upi_launcher.dart';
import 'package:gandharva/state/auth_state.dart';
import 'package:gandharva/state/masters_state.dart';
import 'package:gandharva/ui/screens/get_started/get_started_screen.dart';
import 'package:gandharva/ui/screens/my_profile/my_profile_screen.dart';
import 'package:gandharva/ui/screens/notifications/notifications_screen.dart';
import 'package:gandharva/ui/screens/payment/checkout_screen.dart';
import 'package:gandharva/ui/screens/payment/upi_checkout.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:gandharva/ui/widgets/common.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'guest_mode_test.dart' show activeMeJson;
import 'wedbook_test.dart' show mastersJson, ownProfileJson, wedbookMeJson;

// SPEC §9.20 (v2.10 server, app 3.2.0): the registration fee by direct UPI,
// verified by an admin.

const _uri = 'upi://pay?pa=wedbook%40ybl&pn=Wedbook&am=150.00&cu=INR&tn=Wedbook%20WB501';
const _orderPath = '/customer/my-profiles/80/payment';
const _submitPath = '/customer/payments/501/submit';
const _confirmPath = '/customer/payments/501/confirm';

Map<String, dynamic> upiBlockJson() => {
      'vpa': 'wedbook@ybl',
      'name': 'Wedbook',
      'amount_inr': 150,
      'note': 'Wedbook WB501',
      'reference': 'WB501',
      'uri': _uri,
    };

/// A UPI payment as `POST /customer/my-profiles/:id/payment` and `/submit`
/// return it.
Map<String, dynamic> upiPaymentJson(String status, {String? utr, String? reason, bool withUpi = true}) => {
      'id': 501,
      'profile_id': 80,
      'status': status,
      'amount_paise': 15000,
      'amount_inr': 150,
      'currency': 'INR',
      'provider': 'upi',
      'order_id': null,
      'key_id': null,
      'created_at': '2026-11-13T10:00:00.000Z',
      'paid_at': status == 'paid' ? '2026-11-13T12:00:00.000Z' : null,
      'utr': utr,
      'submitted_at': utr == null ? null : '2026-11-13T10:05:00.000Z',
      'reject_reason': reason,
      if (withUpi) 'upi': upiBlockJson(),
    };

/// The `payment` of my own profile rows.
Map<String, dynamic> rowPaymentJson(String status, {String? utr = '123456789012', String? reason}) => {
      'id': 501,
      'status': status,
      'utr': utr,
      'submitted_at': '2026-11-13T10:05:00.000Z',
      'reject_reason': reason,
    };

/// `/customer/auth/me` on a `upi` server: profile 80 unpaid.
Map<String, dynamic> upiMeJson({Map<String, dynamic>? payment, String provider = 'upi'}) => {
      ...activeMeJson(),
      'status': 'pending',
      'access': 'guest',
      'payment_provider': provider,
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
          'payment': payment,
        },
      ],
      'unlock': {'agent_linked': true, 'profile_registered': true, 'paid': false, 'approved': false},
    };

/// Answers POSTs from per-path queues (the last answer sticks); records
/// every call. An answer is a map or an [ApiException] to throw.
class _FakeApi extends ApiClient {
  final List<(String, Object?)> posts = [];
  final Map<String, List<Object>> _answers = {};

  void answer(String path, Object reply) => _answers.putIfAbsent(path, () => []).add(reply);

  List<Object?> bodiesFor(String path) => [
        for (final (p, b) in posts)
          if (p == path) b,
      ];

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    posts.add((path, body));
    final queue = _answers[path];
    if (queue == null || queue.isEmpty) throw StateError('unexpected POST $path');
    final reply = queue.length == 1 ? queue.first : queue.removeAt(0);
    if (reply is ApiException) throw reply;
    return reply as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async =>
      throw ApiException('network_error', 'offline');

  @override
  Future<String?> readToken() async => 'jwt';

  @override
  String? get tokenSync => 'jwt';
}

/// A UPI app that opens (or not); remembers the links.
class _FakeUpiLauncher implements UpiLauncher {
  _FakeUpiLauncher({this.opens = true});

  bool opens;
  final opened = <String>[];

  @override
  Future<bool> open(String uri) async {
    opened.add(uri);
    return opens;
  }
}

/// Razorpay Checkout that must never open on a UPI server.
class _NoRazorpay implements RazorpayGateway {
  int opened = 0;

  @override
  Future<RazorpayOutcome> open(Map<String, dynamic> options) async {
    opened++;
    return const RazorpayCancelled();
  }
}

/// AuthState with a fixed customer and no network.
class _FixedAuth extends AuthState {
  _FixedAuth(this._c, ApiClient api) : super(api: api, auth: CustomerAuthService(api));

  Customer _c;
  int refreshes = 0;

  @override
  Customer? get customer => _c;

  @override
  AgentCard? get agent => _c.agent;

  @override
  Future<bool> refresh() async {
    refreshes++;
    return true;
  }

  @override
  Future<void> refreshCustomer() async {}

  @override
  void setCustomer(Customer customer) {
    _c = customer;
    notifyListeners();
  }
}

/// My profile's routes without the network.
class _FakeProfiles extends ProfileService {
  _FakeProfiles(super.api, this.own);

  Map<String, dynamic> own;

  @override
  Future<MasterData> masters() async => MasterData.fromJson(mastersJson());

  @override
  Future<Profile> myProfile(int id) async => Profile.fromJson(own);
}

class _Host {
  _Host(Map<String, dynamic> me, {bool upiOpens = true, Map<String, dynamic>? own}) {
    auth = _FixedAuth(Customer.fromJson(me), api);
    launcher = _FakeUpiLauncher(opens: upiOpens);
    profiles = _FakeProfiles(api, own ?? ownProfileJson());
  }

  final api = _FakeApi();
  final razorpay = _NoRazorpay();
  late final _FixedAuth auth;
  late final _FakeUpiLauncher launcher;
  late final _FakeProfiles profiles;

  /// What the checkout returned when it closed.
  final popped = <bool>[];

  Widget wrap(Widget home) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<PaymentService>.value(value: PaymentService(api)),
          Provider<ProfileService>.value(value: profiles),
          Provider<RazorpayGateway>.value(value: razorpay),
          Provider<UpiLauncher>.value(value: launcher),
          ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profiles)),
          ChangeNotifierProvider<AuthState>.value(value: auth),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );

  /// A page with a button that opens the checkout for profile 80.
  Widget launcherPage() => wrap(Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async =>
                  popped.add(await CheckoutScreen.open(context, profileId: 80, profileName: 'Sita')),
              child: const Text('open checkout'),
            ),
          ),
        ),
      ));

  Future<void> openCheckout(WidgetTester tester) async {
    await tester.pumpWidget(launcherPage());
    await tester.tap(find.text('open checkout'));
    await _settle(tester);
  }
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Lets futures, route transitions and snack bars run (1 s of fake time).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

Map<String, dynamic> _submitted({String utr = '123456789012'}) => {
      'payment': upiPaymentJson('submitted', utr: utr, withUpi: false),
      'profile': {
        'id': 80,
        'full_name': 'Sita',
        'gender': 'bride',
        'status': 'hidden',
        'paid': false,
        'paid_at': null,
        'visibility': 'payment_pending',
        'payment': rowPaymentJson('submitted', utr: utr),
      },
      'customer': upiMeJson(payment: rowPaymentJson('submitted', utr: utr)),
    };

void main() {
  // ================================================================ models

  group('Payment / UPI JSON (SPEC §9.20 A / B)', () {
    test('a UPI payment carries the UPI block, UTR fields and status', () {
      final p = Payment.fromJson(upiPaymentJson('created'));
      expect(p.provider, 'upi');
      expect(p.isUpi, isTrue);
      expect(p.isMock, isFalse);
      expect(p.isSubmitted, isFalse);
      expect(p.utr, isNull);
      expect(p.rejectReason, isNull);
      final upi = p.upi!;
      expect(upi.vpa, 'wedbook@ybl');
      expect(upi.name, 'Wedbook');
      expect(upi.amountInr, 150);
      expect(upi.note, 'Wedbook WB501');
      expect(upi.reference, 'WB501');
      expect(upi.uri, _uri);
    });

    test('submitted and failed (not verified) payments', () {
      final s = Payment.fromJson(upiPaymentJson('submitted', utr: '123456789012'));
      expect(s.isSubmitted, isTrue);
      expect(s.utr, '123456789012');
      expect(s.submittedAt, DateTime.parse('2026-11-13T10:05:00.000Z').toLocal());

      final f = Payment.fromJson(upiPaymentJson('failed', utr: '111122223333', reason: '  Amount did not match '));
      expect(f.isFailed, isTrue);
      expect(f.rejectReason, 'Amount did not match');
    });

    test('razorpay / mock payments have no UPI block', () {
      final r = Payment.fromJson({'id': 1, 'status': 'created', 'amount_inr': 150, 'provider': 'razorpay'});
      expect(r.upi, isNull);
      expect(r.utr, isNull);
      expect(r.isUpi, isFalse);
    });

    test('a UPI block without an ID or a link is no block; a string amount is read', () {
      expect(UpiDetails.tryParse(null), isNull);
      expect(UpiDetails.tryParse('upi://pay'), isNull);
      expect(UpiDetails.tryParse({...upiBlockJson()}..remove('vpa')), isNull);
      expect(UpiDetails.tryParse({...upiBlockJson(), 'uri': '  '}), isNull);
      final u = UpiDetails.tryParse({...upiBlockJson(), 'amount_inr': '150.00', 'name': null})!;
      expect(u.amountInr, 150);
      expect(u.name, isNull);
    });

    test('my profile rows carry payment {id, status, utr, submitted_at, reject_reason}', () {
      final c = Customer.fromJson(upiMeJson(payment: rowPaymentJson('submitted')));
      expect(c.paymentProvider, 'upi');
      final row = c.myProfile(80)!;
      expect(row.payment!.id, 501);
      expect(row.payment!.isSubmitted, isTrue);
      expect(row.payment!.isRejected, isFalse);
      expect(row.payment!.utr, '123456789012');
      expect(c.myProfile(1), isNull);

      final rejected = ProfileSummary.fromJson({
        'id': 80,
        'full_name': 'Sita',
        'gender': 'bride',
        'payment': rowPaymentJson('failed', reason: 'No such UTR'),
      });
      expect(rejected.payment!.isRejected, isTrue);
      expect(rejected.payment!.rejectReason, 'No such UTR');

      final own = Profile.fromJson({
        ...ownProfileJson(),
        'paid': false,
        'paid_at': null,
        'payment': rowPaymentJson('submitted'),
      });
      expect(own.payment!.isSubmitted, isTrue);
    });

    test('older servers / paid profiles: no payment', () {
      expect(Customer.fromJson(activeMeJson()).myProfile(80)!.payment, isNull);
      expect(Profile.fromJson(ownProfileJson()).payment, isNull);
      expect(ProfilePayment.tryParse({'status': 'submitted'}), isNull, reason: 'no id');
    });

    test('upiStateOf: only an unpaid profile being verified / not verified; the profile wins over the row', () {
      final unpaid = {...ownProfileJson(), 'id': 80, 'paid': false, 'paid_at': null};
      final me = Customer.fromJson(upiMeJson(payment: rowPaymentJson('submitted')));
      // From the account's row when the profile itself says nothing.
      expect(upiStateOf(Profile.fromJson(unpaid), me)!.isSubmitted, isTrue);
      // The profile's own payment wins.
      final failed = Profile.fromJson({...unpaid, 'payment': rowPaymentJson('failed', reason: 'x')});
      expect(upiStateOf(failed, me)!.isRejected, isTrue);
      // An open (created) payment is just "not paid".
      expect(upiStateOf(Profile.fromJson({...unpaid, 'payment': rowPaymentJson('created', utr: null)}), null), isNull);
      // Paid → nothing to say.
      expect(upiStateOf(Profile.fromJson({...ownProfileJson(), 'payment': rowPaymentJson('submitted')}), me), isNull);
    });
  });

  // ================================================================ service

  group('PaymentService (UPI)', () {
    test('UTR: exactly 12 digits; spaces / dashes are ignored', () {
      expect(PaymentService.isValidUtr('123456789012'), isTrue);
      expect(PaymentService.isValidUtr('1234 5678 9012'), isTrue);
      expect(PaymentService.isValidUtr('1234-5678-9012'), isTrue);
      expect(PaymentService.isValidUtr('12345678901'), isFalse);
      expect(PaymentService.isValidUtr('1234567890123'), isFalse);
      expect(PaymentService.isValidUtr('12345678901a'), isFalse);
      expect(PaymentService.isValidUtr(''), isFalse);
      expect(PaymentService.normalizeUtr(' 1234 5678-9012 '), '123456789012');
    });

    test('upi is checked out in the app', () {
      expect(PaymentService.supportsInApp('upi'), isTrue);
      expect(PaymentService.supportsInApp('cashfree'), isFalse);
    });

    test('openUpi: the open payment; another provider → changed; no UPI block → not set up', () async {
      final api = _FakeApi()..answer(_orderPath, {'payment': upiPaymentJson('created')});
      final service = PaymentService(api);
      expect((await service.openUpi(80)).upi!.uri, _uri);

      final rz = _FakeApi()
        ..answer(_orderPath, {
          'payment': {'id': 9, 'status': 'created', 'amount_inr': 150, 'provider': 'razorpay'},
        });
      await expectLater(
        PaymentService(rz).openUpi(80),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'payment_provider_changed')),
      );

      final bare = _FakeApi()..answer(_orderPath, {'payment': upiPaymentJson('created', withUpi: false)});
      await expectLater(
        PaymentService(bare).openUpi(80),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'payment_provider_error')),
      );
    });

    test('submitUtr posts the 12 digits and reads {payment, profile, customer}', () async {
      final api = _FakeApi()..answer(_submitPath, _submitted());
      final result = await PaymentService(api).submitUtr(501, '1234 5678 9012');
      expect(api.bodiesFor(_submitPath).single, {'utr': '123456789012'});
      expect(result.payment.isSubmitted, isTrue);
      expect(result.profile!.payment!.isSubmitted, isTrue);
      expect(result.customer!.myProfile(80)!.payment!.utr, '123456789012');
    });

    test('friendly messages for the new error codes', () {
      expect(friendlyMessage(ApiException('utr_already_used', 'x')), S.errUtrUsed);
      expect(friendlyMessage(ApiException('payment_under_review', 'x')), S.errPaymentUnderReview);
      expect(
        friendlyMessage(ApiException('payment_provider_error', 'UPI payments are not set up yet')),
        'UPI payments are not set up yet',
      );
    });
  });

  // ================================================================ checkout

  group('Checkout with UPI (SPEC §9.20 E)', () {
    testWidgets('the page: amount, Pay with UPI app, QR of the link, UPI ID + name, the UTR step', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson());
      host.api.answer(_orderPath, {'payment': upiPaymentJson('created')});
      await host.openCheckout(tester);

      expect(host.api.bodiesFor(_orderPath), hasLength(1), reason: 'the open payment is fetched on arrival');
      expect(find.text('₹150'), findsOneWidget);
      expect(_button(S.payWithUpiApp(150)), findsOneWidget);
      // The QR code is the same payment link.
      expect(tester.widget<UpiQrCode>(find.byType(UpiQrCode)).data, _uri);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text(S.upiScanCaption), findsOneWidget);
      expect(find.text('wedbook@ybl'), findsOneWidget);
      expect(find.text(S.upiPayTo('Wedbook')), findsOneWidget);
      expect(find.text(S.copy), findsOneWidget);
      expect(find.text(S.utrLabel), findsOneWidget);
      expect(find.text(S.utrHelper), findsOneWidget);
      expect(_button(S.submitForVerification), findsOneWidget);
      // Nothing from the other providers.
      expect(find.text(S.testModeNoCharge), findsNothing);
      expect(find.text(S.simulateFailure), findsNothing);
      expect(find.text(S.razorpaySecure), findsNothing);
      expect(find.text(S.paymentComingSoon), findsNothing);
      expect(host.api.bodiesFor(_confirmPath), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Pay with UPI app opens the payment link with a UPI app', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson());
      host.api.answer(_orderPath, {'payment': upiPaymentJson('created')});
      await host.openCheckout(tester);

      await tester.tap(find.text(S.payWithUpiApp(150)));
      await _settle(tester);
      expect(host.launcher.opened, [_uri]);
      expect(find.text(S.upiNoAppTitle), findsNothing);
      expect(host.razorpay.opened, 0);
      expect(host.api.bodiesFor(_confirmPath), isEmpty);
    });

    testWidgets('no UPI app on the phone → points to the QR / UPI ID', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson(), upiOpens: false);
      host.api.answer(_orderPath, {'payment': upiPaymentJson('created')});
      await host.openCheckout(tester);

      await tester.tap(find.text(S.payWithUpiApp(150)));
      await _settle(tester);
      expect(host.launcher.opened, [_uri]);
      expect(find.text(S.upiNoAppTitle), findsOneWidget);
      expect(find.text(S.upiNoAppBody), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('Copy puts the UPI ID on the clipboard', (tester) async {
      await _phone(tester);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add('${(call.arguments as Map)['text']}');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final host = _Host(upiMeJson());
      host.api.answer(_orderPath, {'payment': upiPaymentJson('created')});
      await host.openCheckout(tester);

      await _tapVisible(tester, find.text(S.copy));
      await tester.pump();
      expect(copied, ['wedbook@ybl']);
      expect(find.text(S.upiIdCopied), findsOneWidget);
    });

    testWidgets('the UTR must be exactly 12 digits — nothing is sent until it is', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson());
      host.api.answer(_orderPath, {'payment': upiPaymentJson('created')});
      await host.openCheckout(tester);

      final field = find.byType(TextField);
      await tester.enterText(field, '12345');
      await _tapVisible(tester, find.text(S.submitForVerification));
      await _settle(tester);
      expect(find.text(S.utrInvalid), findsOneWidget);
      expect(host.api.bodiesFor(_submitPath), isEmpty);

      // Letters never get in; more than 12 digits are cut.
      await tester.enterText(field, 'ab12cd34');
      await _settle(tester); // the error fades out
      expect(tester.widget<TextField>(field).controller!.text, '1234');
      expect(find.text(S.utrInvalid), findsNothing, reason: 'typing clears the error');
      await tester.enterText(field, '12345678901234');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '123456789012');
    });

    testWidgets('submit → "under verification" with the UTR; no pay button; never /confirm', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson());
      host.api
        ..answer(_orderPath, {'payment': upiPaymentJson('created')})
        ..answer(_submitPath, _submitted());
      await host.openCheckout(tester);

      await tester.enterText(find.byType(TextField), '123456789012');
      await _tapVisible(tester, find.text(S.submitForVerification));
      await _settle(tester);
      expect(host.api.bodiesFor(_submitPath).single, {'utr': '123456789012'});
      expect(find.text(S.upiUnderReviewTitle), findsOneWidget);
      expect(find.text(S.upiUnderReviewBody), findsOneWidget);
      expect(find.text(S.utrLine('123456789012')), findsOneWidget);
      expect(find.text(S.payWithUpiApp(150)), findsNothing);
      expect(find.text(S.submitForVerification), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
      expect(host.api.bodiesFor(_confirmPath), isEmpty);
      // The account follows (my profile row now says submitted).
      expect(host.auth.customer!.myProfile(80)!.payment!.isSubmitted, isTrue);

      // Back: not paid (an admin still has to verify it).
      await tester.pageBack();
      await _settle(tester);
      expect(host.popped, [false]);
    });

    testWidgets('payment_under_review on arrival → "under verification", the account is re-read', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson());
      host.api.answer(
        _orderPath,
        ApiException('payment_under_review', 'Your payment is being verified', status: 409),
      );
      await host.openCheckout(tester);
      expect(find.text(S.upiUnderReviewTitle), findsOneWidget);
      expect(find.text(S.payWithUpiApp(150)), findsNothing);
      expect(find.text(S.errPaymentUnderReview), findsNothing, reason: 'a state, not an error');
      expect(host.auth.refreshes, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a profile row already submitted opens on "under verification"; Check status asks again',
        (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson(payment: rowPaymentJson('submitted', utr: '555566667777')));
      host.api
        ..answer(_orderPath, ApiException('payment_under_review', 'being verified', status: 409))
        ..answer(_orderPath, {'payment': upiPaymentJson('failed', utr: '555566667777', reason: 'Not received')});
      await tester.pumpWidget(host.launcherPage());
      await tester.tap(find.text('open checkout'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Straight away, from the row — no spinner first.
      expect(find.text(S.upiUnderReviewTitle), findsOneWidget);
      expect(find.text(S.utrLine('555566667777')), findsOneWidget);
      await _settle(tester);
      expect(find.text(S.upiUnderReviewTitle), findsOneWidget);
      expect(host.launcher.opened, isEmpty);

      // The admin decided meanwhile: Check status shows the reason and the pay steps again.
      await tester.tap(find.text(S.checkStatus));
      await _settle(tester);
      expect(host.api.bodiesFor(_orderPath), hasLength(2));
      expect(find.text(S.upiNotVerified('Not received')), findsOneWidget);
      expect(find.text(S.payWithUpiApp(150)), findsOneWidget);
    });

    testWidgets('not verified → the reason, the UTR to correct, resubmit on the same payment', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson(payment: rowPaymentJson('failed', utr: '111122223333', reason: 'Amount did not match')));
      host.api
        ..answer(
          _orderPath,
          {'payment': upiPaymentJson('failed', utr: '111122223333', reason: 'Amount did not match')},
        )
        ..answer(_submitPath, _submitted(utr: '999988887777'));
      await host.openCheckout(tester);

      expect(find.text('Payment not verified: Amount did not match'), findsOneWidget);
      expect(find.text(S.upiNotVerifiedBody), findsOneWidget);
      // They may pay again (same link) …
      expect(_button(S.payWithUpiApp(150)), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      // … or correct the UTR they typed.
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).controller!.text, '111122223333');

      await tester.enterText(field, '999988887777');
      await _tapVisible(tester, find.text(S.submitForVerification));
      await _settle(tester);
      expect(host.api.bodiesFor(_submitPath).single, {'utr': '999988887777'});
      expect(host.api.bodiesFor(_orderPath), hasLength(1), reason: 'the same payment, no new one');
      expect(find.text(S.upiUnderReviewTitle), findsOneWidget);
      expect(find.text(S.utrLine('999988887777')), findsOneWidget);
    });

    testWidgets('a UTR already used shows on the field; other failures in a banner', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson());
      host.api
        ..answer(_orderPath, {'payment': upiPaymentJson('created')})
        ..answer(_submitPath, ApiException('utr_already_used', 'This UTR was already used', status: 409))
        ..answer(_submitPath, ApiException('network_error', 'offline'));
      await host.openCheckout(tester);

      await tester.enterText(find.byType(TextField), '123456789012');
      await _tapVisible(tester, find.text(S.submitForVerification));
      await _settle(tester);
      expect(find.text(S.errUtrUsed), findsOneWidget);
      expect(find.text(S.upiUnderReviewTitle), findsNothing);

      await _tapVisible(tester, find.text(S.submitForVerification));
      await _settle(tester);
      expect(find.text(S.errNetwork), findsOneWidget);
      expect(find.text(S.errUtrUsed), findsNothing);
      expect(host.api.bodiesFor(_submitPath), hasLength(2));
    });

    testWidgets('a payment verified on submit → the success view', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson());
      host.api
        ..answer(_orderPath, {'payment': upiPaymentJson('created')})
        ..answer(_submitPath, {
          'payment': upiPaymentJson('paid', utr: '123456789012', withUpi: false),
          'profile': {'id': 80, 'full_name': 'Sita', 'gender': 'bride', 'paid': true, 'visibility': 'awaiting_approval'},
          'customer': null,
        });
      await host.openCheckout(tester);
      await tester.enterText(find.byType(TextField), '123456789012');
      await _tapVisible(tester, find.text(S.submitForVerification));
      await _settle(tester);
      expect(find.text(S.paymentSuccessTitle), findsOneWidget);
      expect(find.text(S.paymentAwaitingApproval), findsOneWidget);
      await tester.tap(find.text(S.done));
      await _settle(tester);
      expect(host.popped, [true]);
    });

    testWidgets('already paid → closes as paid', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson());
      host.api.answer(_orderPath, ApiException('already_paid', 'This profile is already paid for.', status: 409));
      await host.openCheckout(tester);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(host.popped, [true]);
      expect(host.launcher.opened, isEmpty);
    });

    testWidgets('UPI not set up on the server → its message and Try again', (tester) async {
      await _phone(tester);
      final host = _Host(upiMeJson());
      host.api
        ..answer(_orderPath, ApiException('payment_provider_error', 'UPI payments are not set up yet', status: 503))
        ..answer(_orderPath, {'payment': upiPaymentJson('created')});
      await host.openCheckout(tester);
      expect(find.text('UPI payments are not set up yet'), findsOneWidget);
      expect(find.text(S.payWithUpiApp(150)), findsNothing);

      await tester.tap(find.text(S.tryAgain));
      await _settle(tester);
      expect(find.text(S.payWithUpiApp(150)), findsOneWidget);
    });

    testWidgets('razorpay and mock are unchanged: no UPI page, no order on arrival, no UPI app', (tester) async {
      await _phone(tester);
      for (final provider in ['razorpay', 'mock']) {
        final host = _Host(upiMeJson(provider: provider));
        await host.openCheckout(tester);
        expect(host.api.posts, isEmpty, reason: provider);
        expect(find.byType(QrImageView), findsNothing, reason: provider);
        expect(find.text(S.payWithUpiApp(150)), findsNothing, reason: provider);
        expect(find.text(S.utrLabel), findsNothing, reason: provider);
        expect(_button(S.payFee(150)), findsOneWidget, reason: provider);
        expect(find.text(S.razorpaySecure), provider == 'razorpay' ? findsOneWidget : findsNothing);
        expect(find.text(S.testModeNoCharge), provider == 'mock' ? findsOneWidget : findsNothing);
        expect(host.launcher.opened, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });

  // ================================================================ My profile

  group('My profile with a UPI fee (SPEC §9.20 B / E)', () {
    Map<String, dynamic> unpaidOwn(Map<String, dynamic>? payment) => {
          ...ownProfileJson(),
          'id': 80,
          'full_name': 'Sita',
          'paid': false,
          'paid_at': null,
          'visibility': 'payment_pending',
          'payment': payment,
        };

    Map<String, dynamic> me(Map<String, dynamic>? payment) => {
          ...wedbookMeJson(),
          'status': 'pending',
          'payment_provider': 'upi',
          'profiles': [
            {
              'id': 80,
              'full_name': 'Sita',
              'gender': 'bride',
              'paid': false,
              'visibility': 'payment_pending',
              'payment': payment,
            },
          ],
        };

    Future<_Host> render(WidgetTester tester, Map<String, dynamic>? payment) async {
      await _phone(tester);
      final host = _Host(me(payment), own: unpaidOwn(payment));
      await tester.pumpWidget(host.wrap(const MyProfileScreen(profileId: 80)));
      await tester.pump();
      await tester.pump();
      return host;
    }

    testWidgets('under verification: the card with the UTR, the chip, and View payment status', (tester) async {
      await render(tester, rowPaymentJson('submitted', utr: '123456789012'));
      expect(find.text(S.upiUnderReviewTitle), findsOneWidget);
      expect(find.text(S.upiUnderReviewBody), findsOneWidget);
      expect(find.text(S.utrLine('123456789012')), findsOneWidget);
      expect(find.text(S.visibilityTitle('payment_pending')), findsNothing);
      expect(find.text(S.payFee(150)), findsNothing);
      expect(_button(S.viewPaymentStatus), findsOneWidget);
      await tester.scrollUntilVisible(find.text(S.chipVerifyingPayment), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(S.chipVerifyingPayment), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('not verified: the reason, the chip, and Fix payment → the checkout', (tester) async {
      final host = await render(tester, rowPaymentJson('failed', utr: '111122223333', reason: 'Amount did not match'));
      expect(find.text('Payment not verified: Amount did not match'), findsOneWidget);
      expect(find.text(S.upiNotVerifiedBody), findsOneWidget);
      expect(find.text(S.payFee(150)), findsNothing);
      await tester.scrollUntilVisible(find.text(S.chipPaymentNotVerified), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text(S.chipPaymentNotVerified), findsOneWidget);

      host.api.answer(
        _orderPath,
        {'payment': upiPaymentJson('failed', utr: '111122223333', reason: 'Amount did not match')},
      );
      await tester.tap(find.text(S.fixPayment));
      await _settle(tester);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(find.text(S.submitForVerification), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no UPI payment yet (or an open one): the usual "not published" and Publish my profile',
        (tester) async {
      await render(tester, rowPaymentJson('created', utr: null));
      expect(find.text(S.visibilityTitle('payment_pending')), findsOneWidget);
      // SPEC §9.23 F: the publish screen has Pay ₹150 and the gift code.
      expect(_button(S.publishMyProfile), findsOneWidget);
      expect(_button(S.payFee(150)), findsNothing);
      expect(find.text(S.upiUnderReviewTitle), findsNothing);
      expect(find.textContaining('Payment not verified'), findsNothing);
    });
  });

  group('Get started step 3 with a UPI fee', () {
    Future<void> render(WidgetTester tester, Map<String, dynamic>? payment) async {
      await _phone(tester);
      final host = _Host(upiMeJson(payment: payment));
      await tester.pumpWidget(host.wrap(const GetStartedScreen()));
      await tester.pump();
    }

    Future<void> scrollTo(WidgetTester tester, Finder f) =>
        tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);

    testWidgets('being verified → says so; the button shows the status', (tester) async {
      await render(tester, rowPaymentJson('submitted'));
      await scrollTo(tester, find.text(S.step3UnderReview));
      expect(find.text(S.step3UnderReview), findsOneWidget);
      expect(find.text(S.viewPaymentStatus), findsOneWidget);
      expect(find.text(S.payFee(150)), findsNothing, reason: 'no Pay button while it is being verified');
      expect(find.text(S.useGiftCode), findsNothing, reason: 'a fee being verified is not swapped for a code');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('not verified → the reason and Fix payment', (tester) async {
      await render(tester, rowPaymentJson('failed', reason: 'Amount did not match'));
      await scrollTo(tester, find.text(S.fixPayment));
      expect(find.text('Payment not verified: Amount did not match'), findsOneWidget);
      expect(find.text(S.fixPayment), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('nothing submitted → Pay as before', (tester) async {
      await render(tester, null);
      await scrollTo(tester, find.text(S.step3Body(150)));
      expect(find.text(S.step3Body(150)), findsOneWidget);
      expect(find.text(S.step3Title(150)), findsOneWidget);
      expect(find.text(S.payFee(150)), findsOneWidget, reason: 'the button');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // ================================================================ notifications

  group('payment_rejected notification (SPEC §9.20 B)', () {
    test('opens my profile (the reason and Fix payment are there)', () {
      const n = AppNotification(
        type: 'payment_rejected',
        group: 'update',
        id: 501,
        title: 'Payment not verified',
        body: 'Amount did not match',
        myProfileId: 80,
      );
      expect(routeFor(n), const NotificationRoute(NotificationDestination.ownProfile, 80));
      const noProfile = AppNotification(type: 'payment_rejected', group: 'update', id: 501, title: 't');
      expect(routeFor(noProfile).destination, NotificationDestination.myProfilesTab);
    });

    test('a pushed payment_rejected goes to the same place', () {
      expect(
        pushRoute({'type': 'payment_rejected', 'id': '501', 'my_profile_id': '80'}),
        const NotificationRoute(NotificationDestination.ownProfile, 80),
      );
    });

    test('parsed from the feed, with its own icon', () {
      final feed = NotificationFeed.fromJson({
        'action_count': 0,
        'items': [
          {
            'type': 'payment_rejected',
            'group': 'update',
            'id': 501,
            'my_profile_id': 80,
            'title': 'Payment not verified',
            'body': 'Amount did not match',
            'at': '2026-11-13T12:00:00.000Z',
          },
        ],
      });
      final n = feed.updates.single;
      expect(n.type, 'payment_rejected');
      expect(n.myProfileId, 80);
      expect(routeFor(n).tappable, isTrue);
      expect(notificationLook('payment_rejected').$1, Icons.money_off_rounded);
      expect(notificationLook('payment_rejected').$1, isNot(notificationLook('brand_new_type').$1));
    });
  });
}
