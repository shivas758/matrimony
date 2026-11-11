import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/models/payment.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/services/customer_auth_service.dart';
import 'package:gandharva/services/payment_service.dart';
import 'package:gandharva/services/phone_auth_gateway.dart';
import 'package:gandharva/services/razorpay_gateway.dart';
import 'package:gandharva/state/auth_state.dart';
import 'package:gandharva/ui/screens/auth/otp_flow.dart';
import 'package:gandharva/ui/screens/auth/otp_screen.dart';
import 'package:gandharva/ui/screens/auth/phone_screen.dart';
import 'package:gandharva/ui/screens/payment/checkout_screen.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:gandharva/ui/widgets/common.dart';
import 'package:provider/provider.dart';

import 'guest_mode_test.dart' show activeMeJson, guestMeJson;

// SPEC §9.19 (v2.9 server, app 3.1.0): Firebase phone auth + Razorpay Checkout.

/// Answers POSTs from per-path queues (the last answer sticks); records
/// every call. An answer may be a map, a Future of one, or an
/// [ApiException] to throw. Keeps the token in memory (no secure storage).
class _FakeApi extends ApiClient {
  final List<(String, Object?)> posts = [];
  final Map<String, List<Object>> _answers = {};
  String? token;

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
    if (reply is Future<Map<String, dynamic>>) return reply;
    return reply as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async =>
      throw ApiException('network_error', 'offline');

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String t) async => token = t;

  @override
  Future<void> clearToken() async => token = null;

  @override
  String? get tokenSync => token;
}

/// Firebase phone auth without Firebase.
class _FakePhoneAuth implements PhoneAuthGateway {
  PhoneVerificationStep step = const SmsCodeSent(verificationId: 'vid-1', resendToken: 7);
  PhoneAuthFailure? startError;
  PhoneAuthFailure? confirmError;
  String idToken = 'fb-id-token';
  final starts = <(FirebaseClientOptions, String, int?)>[];
  final confirms = <(String, String)>[];
  int signOuts = 0;
  final auto = StreamController<PhoneAutoVerified>.broadcast();

  @override
  Future<PhoneVerificationStep> start(FirebaseClientOptions options, String phone10, {int? resendToken}) async {
    starts.add((options, phone10, resendToken));
    final error = startError;
    if (error != null) throw error;
    return step;
  }

  @override
  Stream<PhoneAutoVerified> get autoVerified => auto.stream;

  @override
  Future<String> confirmCode(String verificationId, String smsCode) async {
    confirms.add((verificationId, smsCode));
    final error = confirmError;
    if (error != null) throw error;
    return idToken;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

/// Razorpay Checkout without Razorpay: answers [outcomes] in order.
class _FakeRazorpay implements RazorpayGateway {
  _FakeRazorpay(List<RazorpayOutcome> outcomes) : outcomes = [...outcomes];

  final List<RazorpayOutcome> outcomes;
  final opened = <Map<String, dynamic>>[];

  @override
  Future<RazorpayOutcome> open(Map<String, dynamic> options) async {
    opened.add(options);
    return outcomes.removeAt(0);
  }
}

/// AuthState with a fixed customer and no network (checkout tests).
class _FixedAuth extends AuthState {
  _FixedAuth(this._c, ApiClient api) : super(api: api, auth: CustomerAuthService(api));

  Customer _c;

  @override
  Customer? get customer => _c;

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

const _phoneNo = '9876543210';
const _sendPath = '/customer/auth/otp/send';
const _verifyPath = '/customer/auth/otp/verify';

Map<String, dynamic> _firebaseOptionsJson() => {
      'api_key': 'AIza-test-key',
      'app_id': '1:1234567890:android:abc123',
      'messaging_sender_id': '1234567890',
      'project_id': 'wedbook-test',
    };

Map<String, dynamic> _firebaseSend({Map<String, dynamic>? options}) => {
      'sent': false,
      'provider': 'firebase',
      'mock': false,
      'expires_in': 300,
      'retry_after': 30,
      'firebase': options ?? _firebaseOptionsJson(),
    };

Map<String, dynamic> _mockSend() => {
      'sent': true,
      'provider': 'mock',
      'mock': true,
      'expires_in': 300,
      'retry_after': 30,
      'mock_code': '123456',
    };

Map<String, dynamic> _newNumber() => {'new': true, 'verification_token': 'vt-1'};

Map<String, dynamic> _login() => {'token': 'jwt-1', 'customer': guestMeJson()};

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

/// Replaces the tree so the OTP countdown timer is disposed.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

class _OtpHost {
  _OtpHost() {
    auth = AuthState(api: api, auth: CustomerAuthService(api));
  }

  final api = _FakeApi();
  final phoneAuth = _FakePhoneAuth();
  late final AuthState auth;

  Widget wrap() => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<PhoneAuthGateway>.value(value: phoneAuth),
          ChangeNotifierProvider<AuthState>.value(value: auth),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const PhoneScreen()),
      );

  /// Phone screen → number → Send OTP.
  Future<void> sendFrom(WidgetTester tester) async {
    await _phone(tester);
    await tester.pumpWidget(wrap());
    await tester.enterText(find.byType(TextFormField), _phoneNo);
    await tester.tap(find.text(S.sendOtp));
    await _settle(tester);
  }
}

void main() {
  group('OTP send response (SPEC §9.19 A)', () {
    test('provider firebase carries the client options', () {
      final s = OtpSent.fromJson(_firebaseSend());
      expect(s.provider, 'firebase');
      expect(s.isFirebase, isTrue);
      expect(s.mock, isFalse);
      expect(s.mockCode, isNull);
      expect(s.retryAfter, 30);
      expect(s.firebase, isNotNull);
      expect(s.firebase!.apiKey, 'AIza-test-key');
      expect(s.firebase!.appId, '1:1234567890:android:abc123');
      expect(s.firebase!.messagingSenderId, '1234567890');
      expect(s.firebase!.projectId, 'wedbook-test');
    });

    test('provider firebase with a missing option has no usable options', () {
      final s = OtpSent.fromJson(_firebaseSend(options: {..._firebaseOptionsJson(), 'app_id': ''}));
      expect(s.isFirebase, isTrue);
      expect(s.firebase, isNull);
      expect(OtpSent.fromJson({..._firebaseSend()}..remove('firebase')).firebase, isNull);
      expect(FirebaseClientOptions.tryParse('nope'), isNull);
      expect(FirebaseClientOptions.tryParse({..._firebaseOptionsJson()}..remove('project_id')), isNull);
    });

    test('mock / msg91 / an older server without provider mean the code flow', () {
      final mock = OtpSent.fromJson(_mockSend());
      expect(mock.isFirebase, isFalse);
      expect(mock.mockCode, '123456');
      final msg91 = OtpSent.fromJson({'sent': true, 'provider': 'msg91', 'mock': false});
      expect(msg91.isFirebase, isFalse);
      expect(msg91.provider, 'msg91');
      final old = OtpSent.fromJson({'sent': true, 'mock': false, 'expires_in': 300, 'retry_after': 30});
      expect(old.provider, isNull);
      expect(old.isFirebase, isFalse);
      expect(old.firebase, isNull);
    });

    test('send always says the app can do Firebase; verify carries the ID token', () async {
      final api = _FakeApi()
        ..answer(_sendPath, _mockSend())
        ..answer(_verifyPath, _newNumber());
      final service = CustomerAuthService(api);
      await service.sendOtp(_phoneNo);
      expect(api.bodiesFor(_sendPath).single, {'phone': _phoneNo, 'firebase': true});
      final r = await service.verifyFirebaseToken(phone: _phoneNo, idToken: 'tok');
      expect(api.bodiesFor(_verifyPath).single, {'phone': _phoneNo, 'firebase_id_token': 'tok'});
      expect(r, isA<NeedsSignup>());
      expect((r as NeedsSignup).verificationToken, 'vt-1');
    });

    test('a firebase answer without options is "could not send" — Firebase is never started', () async {
      final api = _FakeApi()..answer(_sendPath, _firebaseSend(options: {'api_key': 'x'}));
      final fb = _FakePhoneAuth();
      final auth = AuthState(api: api, auth: CustomerAuthService(api));
      await expectLater(
        requestOtp(auth, fb, _phoneNo),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', S.otpCouldNotSend)),
      );
      expect(fb.starts, isEmpty);
    });
  });

  group('Firebase errors in plain words', () {
    test('codes are normalised', () {
      expect(PhoneAuthFailure.normaliseCode('ERROR_INVALID_VERIFICATION_CODE'), 'invalid-verification-code');
      expect(PhoneAuthFailure.normaliseCode('too-many-requests'), 'too-many-requests');
      expect(PhoneAuthFailure.normaliseCode('QUOTA_EXCEEDED'), 'quota-exceeded');
    });

    test('each Firebase code maps to a message', () {
      String m(String code, [String? raw]) => phoneAuthMessage(PhoneAuthFailure(code, raw));
      expect(m('invalid-verification-code'), S.errInvalidOtp);
      expect(m('session-expired'), S.errOtpExpired);
      expect(m('code-expired'), S.errOtpExpired);
      expect(m('too-many-requests'), S.phoneAuthTooManyRequests);
      expect(m('quota-exceeded'), S.phoneAuthQuotaExceeded);
      expect(m('invalid-phone-number'), S.phoneAuthInvalidNumber);
      expect(m('network-request-failed'), S.errNetwork);
      for (final c in ['app-not-authorized', 'missing-client-identifier', 'invalid-app-credential', 'operation-not-allowed']) {
        expect(m(c), S.phoneAuthNotSetUp, reason: c);
      }
      expect(m('internal-error', 'An internal error has occurred. [ BILLING_NOT_ENABLED ]'), S.phoneAuthNotSetUp);
      expect(m('internal-error', 'boom'), S.phoneAuthFailed);
      expect(m('web-context-cancelled'), S.phoneAuthFailed);
      expect(m('timeout'), S.phoneAuthFailed);
    });
  });

  group('Firebase phone login screens', () {
    testWidgets('code sent → OTP screen without the test hint → typed code → ID token → signup', (tester) async {
      final host = _OtpHost();
      host.api
        ..answer(_sendPath, _firebaseSend())
        ..answer(_verifyPath, _newNumber());
      await host.sendFrom(tester);

      expect(host.api.bodiesFor(_sendPath).single, {'phone': _phoneNo, 'firebase': true});
      expect(host.phoneAuth.starts, hasLength(1));
      final (options, phone, resendToken) = host.phoneAuth.starts.single;
      expect(phone, _phoneNo);
      expect(resendToken, isNull);
      expect(options.projectId, 'wedbook-test');
      expect(find.text(S.otpTitle), findsOneWidget);
      expect(find.textContaining('Test mode'), findsNothing);
      expect(find.text(S.testModeTap), findsNothing);

      await tester.enterText(find.byType(TextFormField), '654321'); // 6 digits verify by themselves
      await _settle(tester);

      expect(host.phoneAuth.confirms, [('vid-1', '654321')]);
      expect(host.api.bodiesFor(_verifyPath).single, {'phone': _phoneNo, 'firebase_id_token': 'fb-id-token'});
      expect(host.phoneAuth.signOuts, 1, reason: 'the app keeps no Firebase session');
      expect(find.text(S.signupTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('auto-verified at send → straight to signup, no OTP screen', (tester) async {
      final host = _OtpHost();
      host.phoneAuth.step = const PhoneAutoVerified(idToken: 'auto-token', phone: _phoneNo);
      host.api
        ..answer(_sendPath, _firebaseSend())
        ..answer(_verifyPath, _newNumber());
      await host.sendFrom(tester);

      expect(host.api.bodiesFor(_verifyPath).single, {'phone': _phoneNo, 'firebase_id_token': 'auto-token'});
      expect(host.phoneAuth.confirms, isEmpty);
      expect(host.phoneAuth.signOuts, 1);
      expect(find.text(S.signupTitle), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('SMS read on the OTP screen → "Verifying automatically…" → logged in', (tester) async {
      final host = _OtpHost();
      final answer = Completer<Map<String, dynamic>>();
      host.api
        ..answer(_sendPath, _firebaseSend())
        ..answer(_verifyPath, answer.future);
      await host.sendFrom(tester);
      expect(find.text(S.otpTitle), findsOneWidget);

      host.phoneAuth.auto.add(const PhoneAutoVerified(idToken: 'read-token', phone: _phoneNo));
      await tester.pump();
      await tester.pump();
      expect(find.text(S.otpVerifyingAuto), findsOneWidget);
      expect(host.api.bodiesFor(_verifyPath).single, {'phone': _phoneNo, 'firebase_id_token': 'read-token'});

      answer.complete(_login());
      await _settle(tester);
      expect(host.auth.phase, AuthPhase.loggedIn);
      expect(host.api.token, 'jwt-1');
      expect(host.phoneAuth.confirms, isEmpty);
      expect(host.phoneAuth.signOuts, 1);
      expect(find.byType(OtpScreen), findsNothing, reason: 'popped back to the root, which swaps to Home');
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('an auto-verification for another number is ignored', (tester) async {
      final host = _OtpHost();
      host.api.answer(_sendPath, _firebaseSend());
      await host.sendFrom(tester);
      host.phoneAuth.auto.add(const PhoneAutoVerified(idToken: 'other', phone: '9000000001'));
      await _settle(tester);
      expect(host.api.bodiesFor(_verifyPath), isEmpty);
      expect(find.text(S.otpVerifyingAuto), findsNothing);
      await _dispose(tester);
    });

    testWidgets('a wrong code → Firebase error in plain words, nothing sent to the server', (tester) async {
      final host = _OtpHost();
      host.api.answer(_sendPath, _firebaseSend());
      host.phoneAuth.confirmError = const PhoneAuthFailure('invalid-verification-code', 'The SMS code is invalid');
      await host.sendFrom(tester);

      await tester.enterText(find.byType(TextFormField), '111111');
      await _settle(tester);
      expect(find.text(S.errInvalidOtp), findsOneWidget);
      expect(find.textContaining('SMS code is invalid'), findsNothing);
      expect(host.api.bodiesFor(_verifyPath), isEmpty);
      expect(host.phoneAuth.signOuts, 0);

      host.phoneAuth.confirmError = const PhoneAuthFailure('session-expired');
      await tester.tap(find.text(S.verify));
      await _settle(tester);
      expect(find.text(S.errOtpExpired), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('Firebase errors at send show on the phone screen', (tester) async {
      final host = _OtpHost();
      host.api.answer(_sendPath, _firebaseSend());
      host.phoneAuth.startError = const PhoneAuthFailure('quota-exceeded');
      await host.sendFrom(tester);
      expect(find.text(S.phoneAuthQuotaExceeded), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);

      host.phoneAuth.startError =
          const PhoneAuthFailure('internal-error', 'An internal error has occurred. [ BILLING_NOT_ENABLED ]');
      await tester.tap(find.text(S.sendOtp));
      await _settle(tester);
      expect(find.text(S.phoneAuthNotSetUp), findsOneWidget);

      host.phoneAuth.startError = const PhoneAuthFailure('too-many-requests');
      await tester.tap(find.text(S.sendOtp));
      await _settle(tester);
      expect(find.text(S.phoneAuthTooManyRequests), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('provider firebase without options → "could not send"', (tester) async {
      final host = _OtpHost();
      host.api.answer(_sendPath, _firebaseSend(options: {'api_key': 'only-this'}));
      await host.sendFrom(tester);
      expect(find.text(S.otpCouldNotSend), findsOneWidget);
      expect(host.phoneAuth.starts, isEmpty);
      await _dispose(tester);
    });

    testWidgets('the server refuses the ID token → its message; signed out; Verify confirms again', (tester) async {
      final host = _OtpHost();
      host.api
        ..answer(_sendPath, _firebaseSend())
        ..answer(
          _verifyPath,
          ApiException('invalid_firebase_token', 'This verification could not be checked. Please try again.',
              status: 400),
        );
      await host.sendFrom(tester);
      await tester.enterText(find.byType(TextFormField), '222222');
      await _settle(tester);
      expect(find.text('This verification could not be checked. Please try again.'), findsOneWidget);
      expect(host.phoneAuth.signOuts, 1);

      await tester.tap(find.text(S.verify));
      await _settle(tester);
      expect(host.phoneAuth.confirms, hasLength(2), reason: 'a refused token is not reused');
      expect(host.phoneAuth.signOuts, 2);
      await _dispose(tester);
    });

    testWidgets('server unreachable after Firebase accepted the code → Verify reuses the token', (tester) async {
      final host = _OtpHost();
      host.api
        ..answer(_sendPath, _firebaseSend())
        ..answer(_verifyPath, ApiException('network_error', 'Cannot reach the server.'))
        ..answer(_verifyPath, _newNumber());
      await host.sendFrom(tester);
      await tester.enterText(find.byType(TextFormField), '333333');
      await _settle(tester);
      expect(find.text(S.errNetwork), findsOneWidget);

      await tester.tap(find.text(S.verify));
      await _settle(tester);
      expect(host.phoneAuth.confirms, hasLength(1));
      expect(host.api.bodiesFor(_verifyPath), hasLength(2));
      expect(find.text(S.signupTitle), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('Resend after the countdown → server send again + Firebase with the resend token', (tester) async {
      final host = _OtpHost();
      host.api
        ..answer(_sendPath, _firebaseSend())
        ..answer(_verifyPath, _newNumber());
      await host.sendFrom(tester);
      expect(find.textContaining('Resend code in'), findsOneWidget);
      expect(find.text(S.resendOtp), findsNothing);

      await tester.pump(const Duration(seconds: 31));
      host.phoneAuth.step = const SmsCodeSent(verificationId: 'vid-2', resendToken: 8);
      await tester.tap(find.text(S.resendOtp));
      await _settle(tester);
      expect(host.api.bodiesFor(_sendPath), hasLength(2));
      expect(host.phoneAuth.starts, hasLength(2));
      expect(host.phoneAuth.starts.last.$3, 7, reason: 'forceResendingToken from the first send');
      expect(find.text(S.otpResent), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '444444');
      await _settle(tester);
      expect(host.phoneAuth.confirms.single, ('vid-2', '444444'));
      await _dispose(tester);
    });
  });

  group('Code flow unchanged (mock / msg91 / older server)', () {
    testWidgets('mock: test hint, typed code goes to the server, Firebase never used', (tester) async {
      final host = _OtpHost();
      host.api
        ..answer(_sendPath, _mockSend())
        ..answer(_verifyPath, _newNumber());
      await host.sendFrom(tester);
      expect(find.text(S.testModeHint('123456')), findsOneWidget);

      await tester.tap(find.text(S.testModeHint('123456')));
      await tester.pump();
      await tester.tap(find.text(S.verify));
      await _settle(tester);
      expect(host.api.bodiesFor(_verifyPath).single, {'phone': _phoneNo, 'code': '123456'});
      expect(find.text(S.signupTitle), findsOneWidget);
      expect(host.phoneAuth.starts, isEmpty);
      expect(host.phoneAuth.confirms, isEmpty);
      expect(host.phoneAuth.signOuts, 0);
      await _dispose(tester);
    });

    testWidgets('older server (no provider): no hint, code flow, a known number logs in', (tester) async {
      final host = _OtpHost();
      host.api
        ..answer(_sendPath, {'sent': true, 'mock': false, 'expires_in': 300, 'retry_after': 30})
        ..answer(_verifyPath, _login());
      await host.sendFrom(tester);
      expect(find.text(S.otpTitle), findsOneWidget);
      expect(find.textContaining('Test mode'), findsNothing);

      await tester.enterText(find.byType(TextFormField), '987654');
      await _settle(tester);
      expect(host.api.bodiesFor(_verifyPath).single, {'phone': _phoneNo, 'code': '987654'});
      expect(host.auth.phase, AuthPhase.loggedIn);
      expect(host.phoneAuth.starts, isEmpty);
      await _dispose(tester);
    });
  });

  group('Razorpay checkout (SPEC §9.19 B)', () {
    const orderPath = '/customer/my-profiles/80/payment';
    const confirmPath = '/customer/payments/501/confirm';

    Map<String, dynamic> payment(String status, {String provider = 'razorpay'}) => {
          'id': 501,
          'profile_id': 80,
          'status': status,
          'amount_paise': 15000,
          'amount_inr': 150,
          'currency': 'INR',
          'provider': provider,
          'order_id': provider == 'razorpay' ? 'order_ABC123' : 'mock_1',
          'key_id': provider == 'razorpay' ? 'rzp_test_KEY' : null,
          'created_at': '2026-11-11T10:00:00.000Z',
          'paid_at': status == 'paid' ? '2026-11-11T10:01:00.000Z' : null,
        };

    Map<String, dynamic> customerJson(String provider) => {
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
            },
          ],
          'unlock': {'agent_linked': true, 'profile_registered': true, 'paid': false, 'approved': false},
        };

    Map<String, dynamic> confirmed({String provider = 'razorpay'}) => {
          'payment': payment('paid', provider: provider),
          'profile': {
            'id': 80,
            'full_name': 'Sita',
            'gender': 'bride',
            'status': 'hidden',
            'paid': true,
            'paid_at': '2026-11-11T10:01:00.000Z',
            'visibility': 'awaiting_approval',
          },
          'customer': {...customerJson(provider), 'unlock': {'agent_linked': true, 'profile_registered': true, 'paid': true, 'approved': false}},
        };

    /// Opens the checkout from a launcher page; [popped] gets what it returned.
    final popped = <bool>[];

    Future<(_FakeApi, _FakeRazorpay)> render(
      WidgetTester tester,
      List<RazorpayOutcome> outcomes, {
      String provider = 'razorpay',
    }) async {
      await _phone(tester);
      popped.clear();
      final api = _FakeApi();
      final razorpay = _FakeRazorpay(outcomes);
      final customer = Customer.fromJson(customerJson(provider));
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<PaymentService>.value(value: PaymentService(api)),
          Provider<RazorpayGateway>.value(value: razorpay),
          ChangeNotifierProvider<AuthState>(create: (_) => _FixedAuth(customer, api)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async =>
                      popped.add(await CheckoutScreen.open(context, profileId: 80, profileName: 'Sita')),
                  child: const Text('open checkout'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open checkout'));
      await _settle(tester);
      return (api, razorpay);
    }

    Finder payButton(String label) =>
        find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

    testWidgets('the page: amount, Razorpay notice, Pay — no test mode, no Simulate failure', (tester) async {
      await render(tester, const []);
      expect(find.text('₹150'), findsOneWidget);
      expect(find.text(S.razorpaySecure), findsOneWidget);
      expect(payButton(S.payFee(150)), findsOneWidget);
      expect(find.text(S.testModeNoCharge), findsNothing);
      expect(find.text(S.simulateFailure), findsNothing);
      expect(find.text(S.paymentComingSoon), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('success → confirm with the payment id + signature → success view', (tester) async {
      final (api, razorpay) = await render(tester, const [
        RazorpaySuccess(paymentId: 'pay_XYZ', signature: 'sig_123', orderId: 'order_ABC123'),
      ]);
      api
        ..answer(orderPath, {'payment': payment('created')})
        ..answer(confirmPath, confirmed());
      await tester.tap(find.text(S.payFee(150)));
      await _settle(tester);

      final options = razorpay.opened.single;
      expect(options['key'], 'rzp_test_KEY');
      expect(options['order_id'], 'order_ABC123');
      expect(options['amount'], 15000);
      expect(options['currency'], 'INR');
      expect(options['name'], 'Wedbook Matrimony');
      expect(options['description'], 'Profile registration fee');
      expect(options['prefill'], {'contact': '+917990591543'});
      expect(options['theme'], {'color': '#540729'});
      expect(api.bodiesFor(confirmPath).single, {'provider_payment_id': 'pay_XYZ', 'signature': 'sig_123'});
      expect(find.text(S.paymentSuccessTitle), findsOneWidget);
      expect(find.text(S.paymentAwaitingApproval), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancel → a neutral note, no confirm call', (tester) async {
      final (api, razorpay) = await render(tester, const [RazorpayCancelled()]);
      api.answer(orderPath, {'payment': payment('created')});
      await tester.tap(find.text(S.payFee(150)));
      await _settle(tester);
      expect(razorpay.opened, hasLength(1));
      expect(find.text(S.paymentCancelled), findsOneWidget);
      expect(find.text(S.razorpayFailedTitle), findsNothing);
      expect(api.bodiesFor(confirmPath), isEmpty);
      expect(payButton(S.payFee(150)), findsOneWidget);
    });

    testWidgets('failure → "did not complete" + Try again, which starts a new order', (tester) async {
      final (api, razorpay) = await render(tester, const [
        RazorpayFailed('0: Payment failed'),
        RazorpaySuccess(paymentId: 'pay_2', signature: 'sig_2', orderId: 'order_ABC123'),
      ]);
      api
        ..answer(orderPath, {'payment': payment('created')})
        ..answer(confirmPath, confirmed());
      await tester.tap(find.text(S.payFee(150)));
      await _settle(tester);
      expect(find.text(S.razorpayFailedTitle), findsOneWidget);
      expect(find.text(S.razorpayFailedBody), findsOneWidget);
      expect(api.bodiesFor(confirmPath), isEmpty);
      expect(payButton(S.tryAgain), findsOneWidget);

      await tester.tap(find.text(S.tryAgain));
      await _settle(tester);
      expect(api.bodiesFor(orderPath), hasLength(2), reason: 'trying again starts a new order');
      expect(razorpay.opened, hasLength(2));
      expect(api.bodiesFor(confirmPath).single, {'provider_payment_id': 'pay_2', 'signature': 'sig_2'});
      expect(find.text(S.paymentSuccessTitle), findsOneWidget);
    });

    testWidgets('signature rejected by the server → its message', (tester) async {
      final (api, _) = await render(tester, const [
        RazorpaySuccess(paymentId: 'pay_bad', signature: 'sig_bad'),
      ]);
      api
        ..answer(orderPath, {'payment': payment('created')})
        ..answer(
          confirmPath,
          ApiException('payment_verification_failed', 'Payment could not be verified', status: 400),
        );
      await tester.tap(find.text(S.payFee(150)));
      await _settle(tester);
      expect(find.text(S.errPaymentVerification), findsOneWidget);
      expect(find.text(S.paymentSuccessTitle), findsNothing);
    });

    testWidgets('confirm unreachable → Try again re-confirms the same payment, no new order', (tester) async {
      final (api, razorpay) = await render(tester, const [
        RazorpaySuccess(paymentId: 'pay_N', signature: 'sig_N', orderId: 'order_ABC123'),
      ]);
      api
        ..answer(orderPath, {'payment': payment('created')})
        ..answer(confirmPath, ApiException('network_error', 'Cannot reach the server.'))
        ..answer(confirmPath, confirmed());
      await tester.tap(find.text(S.payFee(150)));
      await _settle(tester);
      expect(find.text(S.errNetwork), findsOneWidget);

      await tester.tap(find.text(S.tryAgain));
      await _settle(tester);
      expect(api.bodiesFor(orderPath), hasLength(1));
      expect(razorpay.opened, hasLength(1));
      expect(api.bodiesFor(confirmPath), hasLength(2));
      expect(api.bodiesFor(confirmPath).last, {'provider_payment_id': 'pay_N', 'signature': 'sig_N'});
      expect(find.text(S.paymentSuccessTitle), findsOneWidget);
    });

    testWidgets('already paid (webhook / safety net) → done', (tester) async {
      final (api, razorpay) = await render(tester, const []);
      api.answer(orderPath, ApiException('already_paid', 'This profile is already paid for.', status: 409));
      await tester.tap(find.text(S.payFee(150)));
      await _settle(tester);
      expect(razorpay.opened, isEmpty);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(popped, [true]);
    });

    testWidgets('mock checkout unchanged: Pay and Simulate failure, Razorpay never opened', (tester) async {
      final (api, razorpay) = await render(tester, const [], provider: 'mock');
      api
        ..answer(orderPath, {'payment': payment('created', provider: 'mock')})
        ..answer(confirmPath, {'payment': payment('failed', provider: 'mock'), 'profile': null, 'customer': null})
        ..answer(confirmPath, confirmed(provider: 'mock'));
      expect(find.text(S.testModeNoCharge), findsOneWidget);
      expect(find.text(S.razorpaySecure), findsNothing);

      await tester.tap(find.text(S.simulateFailure));
      await _settle(tester);
      expect(api.bodiesFor(confirmPath).single, {'outcome': 'failure'});
      expect(find.text(S.paymentFailedTitle), findsOneWidget);

      await tester.tap(find.text(S.tryAgain));
      await _settle(tester);
      expect(api.bodiesFor(confirmPath).last, <String, dynamic>{});
      expect(find.text(S.paymentSuccessTitle), findsOneWidget);
      expect(razorpay.opened, isEmpty);
    });

    test('options without a phone have no prefill; colours become #RRGGBB', () {
      final order = Payment.fromJson(payment('created')..remove('amount_paise'));
      final o = PaymentService.razorpayOptions(order);
      expect(o['amount'], 15000, reason: 'from amount_inr when paise is missing');
      expect(o.containsKey('prefill'), isFalse);
      expect(o.containsKey('theme'), isFalse);
      expect(PaymentService.hexColor(AppColors.wine), '#540729');
      expect(PaymentService.hexColor(const Color(0xFF00000A)), '#00000A');
    });
  });
}
