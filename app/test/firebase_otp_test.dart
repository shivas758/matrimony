import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/phone_auth_gateway.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/state/auth_state.dart';
import 'package:matrimony_agents/state/masters_state.dart';
import 'package:matrimony_agents/ui/screens/auth/signup_screen.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:provider/provider.dart';

/// Signup OTP through Firebase phone auth (SPEC §9.19 A, release 3.1.0):
/// the send answer, the AuthService wire shapes, the Firebase error wording
/// and the signup screen's step 1 in firebase mode — with the mock / msg91
/// code flow left exactly as it was.

const _options = {
  'api_key': 'AIza-test',
  'app_id': '1:123:android:abc',
  'messaging_sender_id': '123',
  'project_id': 'wedbook-test',
};

Map<String, dynamic> _firebaseSend({Map<String, dynamic>? options = _options}) => {
      'sent': false,
      'provider': 'firebase',
      'mock': false,
      'expires_in': 300,
      'retry_after': 30,
      'firebase': ?options,
    };

/// Records every POST; answers the OTP routes like the server would.
class _FakeApi extends ApiClient {
  _FakeApi(this.sendResponse);

  Map<String, dynamic> sendResponse;

  /// Thrown by /auth/otp/verify when set.
  ApiException? verifyError;

  /// Holds /auth/otp/verify until completed (to see the in-between state).
  Completer<void>? verifyGate;

  final posts = <(String, Map<String, Object?>)>[];

  List<Map<String, Object?>> bodiesFor(String path) =>
      [for (final p in posts) if (p.$1 == path) p.$2];

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    posts.add((path, Map<String, Object?>.from(body as Map)));
    if (path == '/auth/otp/send') return sendResponse;
    if (path == '/auth/otp/verify') {
      if (verifyGate != null) await verifyGate!.future;
      if (verifyError != null) throw verifyError!;
      return {'verification_token': 'verified-token'};
    }
    throw ApiException('not_found', 'unexpected POST $path');
  }
}

class _FakeGateway implements PhoneAuthGateway {
  PhoneVerificationStep step = const PhoneCodeSent('vid-1', 42);
  PhoneAuthFailure? startFailure;
  PhoneAuthFailure? confirmFailure;
  String idToken = 'fb-id-token';

  final starts = <({FirebaseClientOptions options, String phone, int? resendToken})>[];
  final confirms = <(String, String)>[];
  int signOuts = 0;
  final auto = StreamController<String>.broadcast();

  @override
  Future<PhoneVerificationStep> start(
    FirebaseClientOptions options,
    String phone10, {
    int? resendToken,
  }) async {
    starts.add((options: options, phone: phone10, resendToken: resendToken));
    if (startFailure != null) throw startFailure!;
    return step;
  }

  @override
  Stream<String> get autoVerifiedIdTokens => auto.stream;

  @override
  Future<String> confirmCode(String verificationId, String smsCode) async {
    confirms.add((verificationId, smsCode));
    if (confirmFailure != null) throw confirmFailure!;
    return idToken;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

class _FakeProfiles extends ProfileService {
  _FakeProfiles() : super(ApiClient());

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
}

class _FakeAuth extends AuthState {
  _FakeAuth(ApiClient api, AuthService service, ProfileService profiles)
      : super(api: api, auth: service, profiles: profiles);

  Map<String, Object?>? signedUp;

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
    signedUp = {'phone': phone, 'token': phoneVerificationToken};
  }
}

class _World {
  _World(Map<String, dynamic> sendResponse) : api = _FakeApi(sendResponse) {
    auth = _FakeAuth(api, AuthService(api), profiles);
  }

  final _FakeApi api;
  final gateway = _FakeGateway();
  final profiles = _FakeProfiles();
  late final _FakeAuth auth;

  Widget app() => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<ProfileService>.value(value: profiles),
          Provider<AuthService>.value(value: AuthService(api)),
          Provider<PhoneAuthGateway>.value(value: gateway),
          ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profiles)),
          ChangeNotifierProvider<AuthState>.value(value: auth),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const SignupScreen()),
      );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);
Finder get _codeField => find.widgetWithText(TextFormField, S.otpCode);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _sendOtp(WidgetTester tester, [String phone = '9000000001']) async {
  await tester.enterText(find.widgetWithText(TextFormField, S.phone), phone);
  await _tap(tester, _button(S.sendOtp));
}

Future<void> _enterCodeAndVerify(WidgetTester tester, String code) async {
  await tester.enterText(_codeField, code);
  await _tap(tester, _button(S.verifyOtp));
}

/// Step 2 → submit; the verification token must reach the signup call.
Future<void> _finishSignup(WidgetTester tester, _World w) async {
  await tester.enterText(find.widgetWithText(TextFormField, S.fullName), 'New Agent');
  await tester.enterText(find.widgetWithText(TextFormField, S.password), 'secret1');
  await tester.enterText(find.widgetWithText(TextFormField, S.confirmPassword), 'secret1');
  await _tap(tester, find.widgetWithText(FilterChip, 'Reddy'));
  await _tap(tester, _button(S.signup));
  expect(w.auth.signedUp, {'phone': '9000000001', 'token': 'verified-token'});
}

void main() {
  group('OtpSendResult (SPEC §9.19 A)', () {
    test('firebase: provider + the client options, no mock code', () {
      final r = OtpSendResult.fromJson(_firebaseSend());
      expect(r.provider, 'firebase');
      expect(r.isFirebase, isTrue);
      expect(r.mock, isFalse);
      expect(r.mockCode, isNull);
      expect(r.retryAfter, 30);
      expect(r.expiresIn, 300);
      expect(r.firebase, isNotNull);
      expect(r.firebase!.apiKey, 'AIza-test');
      expect(r.firebase!.appId, '1:123:android:abc');
      expect(r.firebase!.messagingSenderId, '123');
      expect(r.firebase!.projectId, 'wedbook-test');
    });

    test('firebase with a missing or empty option has no usable options', () {
      expect(OtpSendResult.fromJson(_firebaseSend(options: null)).firebase, isNull);
      final partial = Map<String, dynamic>.of(_options)..remove('project_id');
      expect(OtpSendResult.fromJson(_firebaseSend(options: partial)).firebase, isNull);
      final blank = Map<String, dynamic>.of(_options)..['api_key'] = '  ';
      expect(OtpSendResult.fromJson(_firebaseSend(options: blank)).firebase, isNull);
      expect(FirebaseClientOptions.fromJson('nope'), isNull);
    });

    test('mock / msg91 carry their provider and stay the code flow', () {
      final mock = OtpSendResult.fromJson(const {
        'sent': true,
        'provider': 'mock',
        'mock': true,
        'expires_in': 300,
        'retry_after': 30,
        'mock_code': '123456',
      });
      expect(mock.provider, 'mock');
      expect(mock.isFirebase, isFalse);
      expect(mock.mockCode, '123456');
      expect(mock.firebase, isNull);

      final msg91 = OtpSendResult.fromJson(const {
        'sent': true,
        'provider': 'msg91',
        'mock': false,
        // Options next to another provider are ignored.
        'firebase': _options,
      });
      expect(msg91.isFirebase, isFalse);
      expect(msg91.firebase, isNull);
    });

    test('an older server sends no provider: the code flow', () {
      final old = OtpSendResult.fromJson(
          const {'sent': true, 'mock': true, 'expires_in': 300, 'retry_after': 30, 'mock_code': '123456'});
      expect(old.provider, isNull);
      expect(old.isFirebase, isFalse);
      expect(old.mockCode, '123456');
    });
  });

  group('AuthService wire shapes', () {
    test('send always says firebase: true', () async {
      final api = _FakeApi(const {'sent': true, 'mock': false, 'provider': 'msg91'});
      await AuthService(api).sendSignupOtp('9000000001');
      expect(api.posts.single.$1, '/auth/otp/send');
      expect(api.posts.single.$2, {'phone': '9000000001', 'firebase': true});
    });

    test('provider firebase without complete options → a plain "could not send"', () async {
      final api = _FakeApi(_firebaseSend(options: null));
      await expectLater(
        AuthService(api).sendSignupOtp('9000000001'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'otp_provider_error')
            .having((e) => e.message, 'message', S.otpSendFailed)),
      );
    });

    test('firebase verify sends firebase_id_token instead of a code', () async {
      final api = _FakeApi(_firebaseSend());
      final token = await AuthService(api).verifySignupFirebase('9000000001', 'fb-id-token');
      expect(token, 'verified-token');
      expect(api.posts.single.$1, '/auth/otp/verify');
      expect(api.posts.single.$2, {'phone': '9000000001', 'firebase_id_token': 'fb-id-token'});
    });

    test('the code verify is unchanged', () async {
      final api = _FakeApi(const {});
      await AuthService(api).verifySignupOtp('9000000001', '123456');
      expect(api.posts.single.$2, {'phone': '9000000001', 'code': '123456'});
    });
  });

  group('Firebase errors in plain English', () {
    test('each code has its message', () {
      expect(phoneAuthMessage('invalid-verification-code'), S.phoneAuthWrongCode);
      expect(phoneAuthMessage('session-expired'), S.phoneAuthCodeExpired);
      expect(phoneAuthMessage('code-expired'), S.phoneAuthCodeExpired);
      expect(phoneAuthMessage('too-many-requests'), S.phoneAuthTooManyAttempts);
      expect(phoneAuthMessage('quota-exceeded'), S.phoneAuthQuotaExceeded);
      expect(phoneAuthMessage('invalid-phone-number'), S.phoneAuthInvalidNumber);
      expect(phoneAuthMessage('network-request-failed'), S.phoneAuthNetwork);
      for (final c in [
        'app-not-authorized',
        'missing-client-identifier',
        'invalid-app-credential',
        'operation-not-allowed',
      ]) {
        expect(phoneAuthMessage(c), S.phoneAuthNotSetUp, reason: c);
      }
      expect(phoneAuthMessage('internal-error', 'An internal error has occurred. [ BILLING_NOT_ENABLED ]'),
          S.phoneAuthNotSetUp);
      expect(phoneAuthMessage('unknown', 'boom'), S.phoneAuthFailed);
      expect(phoneAuthMessage('web-context-cancelled'), S.phoneAuthFailed);
    });

    test('native-style codes are normalised', () {
      expect(normalisePhoneAuthCode('ERROR_INVALID_VERIFICATION_CODE'), 'invalid-verification-code');
      expect(phoneAuthMessage('ERROR_QUOTA_EXCEEDED'), S.phoneAuthQuotaExceeded);
      final f = PhoneAuthFailure.from('ERROR_SESSION_EXPIRED');
      expect(f.code, 'session-expired');
      expect(f.message, S.phoneAuthCodeExpired);
      expect(f.needsNewCode, isTrue);
      expect(PhoneAuthFailure.from('invalid-verification-code').needsNewCode, isFalse);
    });
  });

  group('signup step 1 in firebase mode', () {
    testWidgets('code sent → typed code → firebase_id_token → step 2 → signup', (tester) async {
      _phone(tester);
      final w = _World(_firebaseSend());
      await tester.pumpWidget(w.app());
      await tester.pumpAndSettle();

      await _sendOtp(tester);
      expect(w.api.bodiesFor('/auth/otp/send').single, {'phone': '9000000001', 'firebase': true});
      final start = w.gateway.starts.single;
      expect(start.phone, '9000000001');
      expect(start.resendToken, isNull);
      expect(start.options.projectId, 'wedbook-test');
      expect(start.options.appId, '1:123:android:abc');

      expect(_codeField, findsOneWidget);
      expect(find.textContaining(S.testModeHint), findsNothing, reason: 'no test-mode hint for firebase');
      expect(find.textContaining('123456'), findsNothing);
      expect(find.textContaining(S.resendIn), findsOneWidget, reason: 'the 30 s countdown runs');

      await _enterCodeAndVerify(tester, '654321');
      expect(w.gateway.confirms, [('vid-1', '654321')]);
      final verify = w.api.bodiesFor('/auth/otp/verify').single;
      expect(verify, {'phone': '9000000001', 'firebase_id_token': 'fb-id-token'});
      expect(verify.containsKey('code'), isFalse);
      expect(w.gateway.signOuts, 1, reason: 'the app keeps no Firebase session');

      expect(find.text(S.detailsStepTitle), findsOneWidget);
      expect(find.text(S.phoneVerified), findsOneWidget);
      await _finishSignup(tester, w);
      expect(tester.takeException(), isNull);
    });

    testWidgets('instant verification: no code to type, "Verifying automatically…"', (tester) async {
      _phone(tester);
      final w = _World(_firebaseSend());
      w.gateway.step = const PhoneAutoVerified('fb-auto-token');
      w.api.verifyGate = Completer<void>();
      await tester.pumpWidget(w.app());
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, S.phone), '9000000001');
      await tester.tap(_button(S.sendOtp));
      await tester.pump();
      await tester.pump();
      expect(find.text(S.verifyingAutomatically), findsOneWidget);
      expect(find.text(S.detailsStepTitle), findsNothing);

      w.api.verifyGate!.complete();
      await tester.pumpAndSettle();
      expect(w.gateway.confirms, isEmpty);
      expect(w.api.bodiesFor('/auth/otp/verify').single,
          {'phone': '9000000001', 'firebase_id_token': 'fb-auto-token'});
      expect(w.gateway.signOuts, 1);
      expect(find.text(S.detailsStepTitle), findsOneWidget);
      expect(find.text(S.verifyingAutomatically), findsNothing);
      await _finishSignup(tester, w);
    });

    testWidgets('SMS auto-read after the code field showed → straight to step 2', (tester) async {
      _phone(tester);
      final w = _World(_firebaseSend());
      await tester.pumpWidget(w.app());
      await tester.pumpAndSettle();

      await _sendOtp(tester);
      expect(_codeField, findsOneWidget);

      w.gateway.auto.add('fb-auto-token');
      await tester.pumpAndSettle();
      expect(w.api.bodiesFor('/auth/otp/verify').single,
          {'phone': '9000000001', 'firebase_id_token': 'fb-auto-token'});
      expect(find.text(S.detailsStepTitle), findsOneWidget);
      expect(w.gateway.signOuts, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a Firebase failure on send shows the plain message', (tester) async {
      _phone(tester);
      final w = _World(_firebaseSend());
      w.gateway.startFailure = PhoneAuthFailure.from('quota-exceeded');
      await tester.pumpWidget(w.app());
      await tester.pumpAndSettle();

      await _sendOtp(tester);
      expect(find.text(S.phoneAuthQuotaExceeded), findsOneWidget);
      expect(_codeField, findsNothing);
      expect(_button(S.sendOtp), findsOneWidget);
      expect(w.api.bodiesFor('/auth/otp/verify'), isEmpty);
    });

    testWidgets('a wrong code keeps the field; nothing reaches the server', (tester) async {
      _phone(tester);
      final w = _World(_firebaseSend());
      w.gateway.confirmFailure = PhoneAuthFailure.from('invalid-verification-code');
      await tester.pumpWidget(w.app());
      await tester.pumpAndSettle();

      await _sendOtp(tester);
      await _enterCodeAndVerify(tester, '111111');
      expect(find.text(S.phoneAuthWrongCode), findsOneWidget);
      expect(find.text('111111'), findsOneWidget);
      expect(find.text(S.detailsStepTitle), findsNothing);
      expect(w.api.bodiesFor('/auth/otp/verify'), isEmpty);

      // The right code next.
      w.gateway.confirmFailure = null;
      await _enterCodeAndVerify(tester, '654321');
      expect(find.text(S.detailsStepTitle), findsOneWidget);
    });

    testWidgets('a server refusal shows its message and still signs out of Firebase',
        (tester) async {
      _phone(tester);
      final w = _World(_firebaseSend());
      w.api.verifyError =
          ApiException('phone_mismatch', 'This verification was for another number.', status: 400);
      await tester.pumpWidget(w.app());
      await tester.pumpAndSettle();

      await _sendOtp(tester);
      await _enterCodeAndVerify(tester, '654321');
      expect(find.text('This verification was for another number.'), findsOneWidget);
      expect(find.text(S.detailsStepTitle), findsNothing);
      expect(w.gateway.signOuts, 1);
    });

    testWidgets('firebase without options → "could not send", Firebase untouched', (tester) async {
      _phone(tester);
      final w = _World(_firebaseSend(options: null));
      await tester.pumpWidget(w.app());
      await tester.pumpAndSettle();

      await _sendOtp(tester);
      expect(find.text(S.otpSendFailed), findsOneWidget);
      expect(w.gateway.starts, isEmpty);
      expect(_codeField, findsNothing);
    });

    testWidgets('Resend after 30 s passes the resend token; change number resets it',
        (tester) async {
      _phone(tester);
      final w = _World(_firebaseSend());
      await tester.pumpWidget(w.app());
      await tester.pumpAndSettle();

      await _sendOtp(tester);
      final resend = find.widgetWithText(TextButton, S.resendOtp);
      expect(tester.widget<TextButton>(resend).onPressed, isNull, reason: 'countdown running');

      await tester.pump(const Duration(seconds: 31));
      expect(tester.widget<TextButton>(resend).onPressed, isNotNull);
      w.gateway.step = const PhoneCodeSent('vid-2', 43);
      await _tap(tester, resend);
      expect(w.api.bodiesFor('/auth/otp/send'), hasLength(2));
      expect(w.gateway.starts, hasLength(2));
      expect(w.gateway.starts.last.resendToken, 42);

      // The new verification id is the one confirmed.
      await _enterCodeAndVerify(tester, '222222');
      expect(w.gateway.confirms.last, ('vid-2', '222222'));
      expect(find.text(S.detailsStepTitle), findsOneWidget);

      // Change number → a first send again (no resend token).
      await _tap(tester, find.widgetWithText(TextButton, S.changeNumber));
      expect(find.text(S.otpStepTitle), findsOneWidget);
      expect(w.gateway.signOuts, greaterThanOrEqualTo(1));
      await _tap(tester, _button(S.sendOtp));
      expect(w.gateway.starts.last.resendToken, isNull);
    });
  });

  group('the code flow is unchanged', () {
    testWidgets('mock: test-mode hint, code verify, Firebase never used', (tester) async {
      _phone(tester);
      final w = _World(const {
        'sent': true,
        'provider': 'mock',
        'mock': true,
        'expires_in': 300,
        'retry_after': 30,
        'mock_code': '123456',
      });
      await tester.pumpWidget(w.app());
      await tester.pumpAndSettle();

      await _sendOtp(tester);
      expect(find.text('${S.testModeHint} 123456'), findsOneWidget);
      await _enterCodeAndVerify(tester, '123456');
      expect(w.api.bodiesFor('/auth/otp/verify').single, {'phone': '9000000001', 'code': '123456'});
      expect(find.text(S.detailsStepTitle), findsOneWidget);
      expect(w.gateway.starts, isEmpty);
      expect(w.gateway.confirms, isEmpty);
      expect(w.gateway.signOuts, 0);
      await _finishSignup(tester, w);
    });

    testWidgets('an older server (no provider): the code flow', (tester) async {
      _phone(tester);
      final w = _World(const {'sent': true, 'mock': false, 'expires_in': 300, 'retry_after': 0});
      await tester.pumpWidget(w.app());
      await tester.pumpAndSettle();

      await _sendOtp(tester);
      expect(find.textContaining(S.testModeHint), findsNothing);
      await _enterCodeAndVerify(tester, '482913');
      expect(w.api.bodiesFor('/auth/otp/verify').single, {'phone': '9000000001', 'code': '482913'});
      expect(find.text(S.detailsStepTitle), findsOneWidget);
      expect(w.gateway.starts, isEmpty);
    });
  });
}
