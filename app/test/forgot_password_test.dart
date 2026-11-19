import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/notifications.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/phone_auth_gateway.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/state/auth_state.dart';
import 'package:matrimony_agents/ui/screens/auth/forgot_password_screen.dart';
import 'package:matrimony_agents/ui/screens/auth/login_screen.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:provider/provider.dart';

/// "Forgot password?" by OTP (SPEC §9.24 D, release 3.5.0): Login →
/// Forgot password? → mobile → reset code (mock, SMS or Firebase) → new
/// password + confirm → logged in like a login; "Can't get the code? Ask the
/// admin" still files the old admin request.

const _mockSend = {
  'sent': true,
  'provider': 'mock',
  'mock': true,
  'expires_in': 300,
  'retry_after': 30,
  'mock_code': '123456',
};

const _firebaseOptions = {
  'api_key': 'AIza-test',
  'app_id': '1:123:android:abc',
  'messaging_sender_id': '123',
  'project_id': 'wedbook-test',
};

const _firebaseSend = {
  'sent': false,
  'provider': 'firebase',
  'mock': false,
  'expires_in': 300,
  'retry_after': 30,
  'firebase': _firebaseOptions,
};

/// The agent /auth/reset-password answers (an older-server shape: no
/// approval keys, so no extra /auth/me polling).
const _agentJson = {
  'id': 4,
  'full_name': 'Lakshmi Devi',
  'phone': '9000000001',
  'role': 'agent',
  'status': 'active',
  'must_change_password': false,
  'communities': [
    {'id': 1, 'name': 'Reddy'},
  ],
  'state': {'id': 1, 'name': 'Karnataka', 'code': 'KA'},
  'agent_code': 'KA1A',
};

/// Records every POST and answers the auth routes like the server would.
class _FakeApi extends ApiClient {
  Map<String, dynamic> sendResponse = Map.of(_mockSend);
  ApiException? sendError;
  ApiException? verifyError;
  ApiException? resetError;
  String? savedToken;

  final posts = <(String, Map<String, Object?>)>[];

  List<Map<String, Object?>> bodiesFor(String path) =>
      [for (final p in posts) if (p.$1 == path) p.$2];

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    posts.add((path, Map<String, Object?>.from(body as Map)));
    switch (path) {
      case '/auth/otp/send':
        if (sendError != null) throw sendError!;
        return sendResponse;
      case '/auth/otp/verify':
        if (verifyError != null) throw verifyError!;
        return {'verification_token': 'reset-token'};
      case '/auth/reset-password':
        if (resetError != null) throw resetError!;
        return {'token': 'jwt-new', 'agent': _agentJson};
      case '/auth/forgot-password':
        return {'ok': true};
    }
    throw ApiException('not_found', 'unexpected POST $path');
  }

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    if (path == '/auth/me') return {'agent': _agentJson};
    throw ApiException('not_found', 'unexpected GET $path');
  }

  @override
  Future<String?> readToken() async => savedToken;

  @override
  Future<void> saveToken(String token) async => savedToken = token;

  @override
  Future<void> clearToken() async => savedToken = null;
}

class _FakeGateway implements PhoneAuthGateway {
  PhoneVerificationStep step = const PhoneCodeSent('vid-1', 42);
  final starts = <String>[];
  final confirms = <(String, String)>[];
  int signOuts = 0;
  final auto = StreamController<String>.broadcast();

  @override
  Future<PhoneVerificationStep> start(
    FirebaseClientOptions options,
    String phone10, {
    int? resendToken,
  }) async {
    starts.add(phone10);
    return step;
  }

  @override
  Stream<String> get autoVerifiedIdTokens => auto.stream;

  @override
  Future<String> confirmCode(String verificationId, String smsCode) async {
    confirms.add((verificationId, smsCode));
    return 'fb-id-token';
  }

  @override
  Future<void> signOut() async => signOuts++;
}

class _FakeProfiles extends ProfileService {
  _FakeProfiles() : super(ApiClient());

  @override
  Future<NotificationFeed> notifications() async => NotificationFeed.empty;
}

/// Like the app's root: Login while logged out, the app once logged in.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return auth.phase == AuthPhase.loggedIn
        ? Scaffold(body: Center(child: Text('HOME ${auth.agent?.fullName}')))
        : const LoginScreen();
  }
}

class _World {
  _World() {
    auth = AuthState(api: api, auth: AuthService(api), profiles: _FakeProfiles());
  }

  final api = _FakeApi();
  final gateway = _FakeGateway();
  late final AuthState auth;

  Widget app() => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<AuthService>.value(value: AuthService(api)),
          Provider<PhoneAuthGateway>.value(value: gateway),
          ChangeNotifierProvider<AuthState>.value(value: auth),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const _Root()),
      );

  /// The notification poll of a logged-in agent must not outlive the test.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);
Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Login → number typed there → Forgot password?
Future<void> _openReset(WidgetTester tester, [String phone = '9000000001']) async {
  await tester.enterText(_field(S.phone), phone);
  await _tap(tester, find.widgetWithText(TextButton, S.forgotPassword));
  expect(find.byType(ForgotPasswordScreen), findsOneWidget);
}

/// Step 1 with the mock code → step 2.
Future<void> _verifyNumber(WidgetTester tester) async {
  await _tap(tester, _button(S.sendOtp));
  await tester.enterText(_field(S.otpCode), '123456');
  await _tap(tester, _button(S.verifyOtp));
  expect(find.text(S.newPasswordStepTitle), findsOneWidget);
}

Future<void> _newPassword(WidgetTester tester, String password, [String? confirm]) async {
  await tester.enterText(_field(S.newPassword), password);
  await tester.enterText(_field(S.confirmPassword), confirm ?? password);
  await _tap(tester, _button(S.saveAndLogin));
}

void main() {
  group('AuthService — reset wire shapes (SPEC §9.24 D)', () {
    test('send asks for the reset code, saying the app can do Firebase', () async {
      final api = _FakeApi();
      final r = await AuthService(api).sendResetOtp('9000000001');
      expect(r.mockCode, '123456');
      expect(api.posts.single.$1, '/auth/otp/send');
      expect(api.posts.single.$2, {'phone': '9000000001', 'purpose': 'reset', 'firebase': true});
    });

    test('verify: the code or the Firebase ID token, with purpose reset', () async {
      final api = _FakeApi();
      final service = AuthService(api);
      expect(await service.verifyResetOtp('9000000001', '123456'), 'reset-token');
      expect(await service.verifyResetFirebase('9000000001', 'fb-id-token'), 'reset-token');
      expect(api.bodiesFor('/auth/otp/verify'), [
        {'phone': '9000000001', 'code': '123456', 'purpose': 'reset'},
        {'phone': '9000000001', 'firebase_id_token': 'fb-id-token', 'purpose': 'reset'},
      ]);
    });

    test('reset-password: the body, and the answer stored like a login', () async {
      final api = _FakeApi();
      final result = await AuthService(api).resetPassword(
        phone: '9000000001',
        phoneVerificationToken: 'reset-token',
        newPassword: 'secret1',
      );
      expect(api.bodiesFor('/auth/reset-password').single, {
        'phone': '9000000001',
        'phone_verification_token': 'reset-token',
        'new_password': 'secret1',
      });
      expect(result.token, 'jwt-new');
      expect(result.agent.fullName, 'Lakshmi Devi');
      expect(api.savedToken, 'jwt-new');
    });

    test('a firebase answer without options → a plain "could not send"', () async {
      final api = _FakeApi()..sendResponse = {..._firebaseSend}..sendResponse.remove('firebase');
      await expectLater(
        AuthService(api).sendResetOtp('9000000001'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'otp_provider_error')
            .having((e) => e.message, 'message', S.otpSendFailed)),
      );
    });

    test('the signup calls carry no purpose', () async {
      final api = _FakeApi();
      final service = AuthService(api);
      await service.sendSignupOtp('9000000001');
      await service.verifySignupOtp('9000000001', '123456');
      expect(api.bodiesFor('/auth/otp/send').single, {'phone': '9000000001', 'firebase': true});
      expect(api.bodiesFor('/auth/otp/verify').single, {'phone': '9000000001', 'code': '123456'});
    });
  });

  test('AuthState.resetPassword logs in exactly like login', () async {
    final api = _FakeApi();
    final auth = AuthState(api: api, auth: AuthService(api), profiles: _FakeProfiles());
    expect(auth.phase, AuthPhase.starting);
    await auth.resetPassword(
      phone: '9000000001',
      phoneVerificationToken: 'reset-token',
      newPassword: 'secret1',
    );
    expect(auth.phase, AuthPhase.loggedIn);
    expect(auth.agent?.fullName, 'Lakshmi Devi');
    expect(auth.mustChangePassword, isFalse);
    expect(auth.canUseApp, isTrue);
    expect(api.savedToken, 'jwt-new');
    // The first notification refresh runs at once, like after a login.
    await pumpEventQueue();
    auth.dispose();
  });

  group('Forgot password screen', () {
    testWidgets('login → number pre-filled → test code → new password → logged in',
        (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app());
      await _openReset(tester);

      expect(find.text(S.resetPasswordTitle), findsOneWidget);
      expect(find.text(S.resetOtpBody), findsOneWidget);
      expect(find.text('9000000001'), findsOneWidget, reason: 'the number from the login field');
      expect(find.byType(AlertDialog), findsNothing, reason: 'no more admin-request dialog');

      await _tap(tester, _button(S.sendOtp));
      expect(w.api.bodiesFor('/auth/otp/send').single,
          {'phone': '9000000001', 'purpose': 'reset', 'firebase': true});
      expect(find.text('${S.testModeHint} 123456'), findsOneWidget);
      expect(find.text(S.cantGetCode), findsOneWidget);

      // Resend waits 30 s, like signup.
      final resend = find.widgetWithText(TextButton, S.resendOtp);
      expect(tester.widget<TextButton>(resend).onPressed, isNull);
      expect(find.textContaining(S.resendIn), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
      expect(tester.widget<TextButton>(resend).onPressed, isNotNull);
      await _tap(tester, resend);
      expect(w.api.bodiesFor('/auth/otp/send'), hasLength(2));
      expect(w.api.bodiesFor('/auth/otp/send').last['purpose'], 'reset');

      await tester.enterText(_field(S.otpCode), '123456');
      await _tap(tester, _button(S.verifyOtp));
      expect(w.api.bodiesFor('/auth/otp/verify').single,
          {'phone': '9000000001', 'code': '123456', 'purpose': 'reset'});
      expect(find.text(S.newPasswordStepTitle), findsOneWidget);
      expect(find.text(S.phoneVerified), findsOneWidget);
      expect(find.text('+91 9000000001'), findsOneWidget);

      // 6–100 characters, and the two must match.
      await _newPassword(tester, 'abc');
      expect(find.text(S.passwordLengthRule), findsOneWidget);
      await _newPassword(tester, 'secret1', 'secret2');
      expect(find.text(S.passwordsDontMatch), findsOneWidget);
      await _newPassword(tester, 'x' * 101);
      expect(find.text(S.passwordLengthRule), findsOneWidget);
      expect(w.api.bodiesFor('/auth/reset-password'), isEmpty);

      await _newPassword(tester, 'secret1');
      expect(w.api.bodiesFor('/auth/reset-password').single, {
        'phone': '9000000001',
        'phone_verification_token': 'reset-token',
        'new_password': 'secret1',
      });
      expect(w.api.savedToken, 'jwt-new');
      expect(w.auth.phase, AuthPhase.loggedIn);
      expect(find.text('HOME Lakshmi Devi'), findsOneWidget, reason: 'lands in the app');
      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text(S.passwordResetDone), findsOneWidget);
      expect(tester.takeException(), isNull);
      await w.dispose(tester);
    });

    testWidgets('a number that is not an agent: "No account with this mobile number"',
        (tester) async {
      _phone(tester);
      final w = _World();
      w.api.sendError =
          ApiException('account_not_found', 'Not found', status: 404);
      await tester.pumpWidget(w.app());
      await _openReset(tester, '9111111111');

      await _tap(tester, _button(S.sendOtp));
      expect(find.text(S.noAccountForNumber), findsOneWidget);
      expect(_field(S.otpCode), findsNothing);
      expect(find.text(S.cantGetCode), findsNothing);
      expect(w.api.bodiesFor('/auth/otp/send').single['phone'], '9111111111');
    });

    testWidgets('the SMS cannot be sent → "Ask the admin" is offered right away', (tester) async {
      _phone(tester);
      final w = _World();
      w.api.sendError = ApiException(
        'otp_provider_error',
        'Could not send the SMS — try again in a minute',
        status: 503,
      );
      await tester.pumpWidget(w.app());
      await _openReset(tester);

      await _tap(tester, _button(S.sendOtp));
      expect(_field(S.otpCode), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('ask-admin')));
      await _tap(tester, _button(S.forgotPasswordSend));
      expect(w.api.bodiesFor('/auth/forgot-password').single, {'phone': '9000000001'});
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('Firebase: the typed code → firebase_id_token with purpose reset', (tester) async {
      _phone(tester);
      final w = _World();
      w.api.sendResponse = Map.of(_firebaseSend);
      await tester.pumpWidget(w.app());
      await _openReset(tester);

      await _tap(tester, _button(S.sendOtp));
      expect(w.gateway.starts, ['9000000001']);
      expect(find.textContaining(S.testModeHint), findsNothing);

      await tester.enterText(_field(S.otpCode), '654321');
      await _tap(tester, _button(S.verifyOtp));
      expect(w.gateway.confirms, [('vid-1', '654321')]);
      expect(w.api.bodiesFor('/auth/otp/verify').single,
          {'phone': '9000000001', 'firebase_id_token': 'fb-id-token', 'purpose': 'reset'});
      expect(w.gateway.signOuts, 1, reason: 'the app keeps no Firebase session');
      expect(find.text(S.newPasswordStepTitle), findsOneWidget);

      await _newPassword(tester, 'secret1');
      expect(w.auth.phase, AuthPhase.loggedIn);
      await w.dispose(tester);
    });

    testWidgets('the verification lapsed (phone_not_verified): back to step 1 to start again',
        (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app());
      await _openReset(tester);
      await _verifyNumber(tester);

      w.api.resetError = ApiException(
        'phone_not_verified',
        'Verify your mobile number with the OTP first',
        status: 400,
      );
      await _newPassword(tester, 'secret1');

      expect(find.text(S.resetStartAgain), findsOneWidget);
      expect(find.text(S.otpStepTitle), findsOneWidget);
      expect(find.text('9000000001'), findsOneWidget, reason: 'the number stays');
      expect(_button(S.sendOtp), findsOneWidget);
      expect(w.auth.phase, isNot(AuthPhase.loggedIn));

      // A fresh code, and this time it works.
      w.api.resetError = null;
      await _verifyNumber(tester);
      await _newPassword(tester, 'secret1');
      expect(w.auth.phase, AuthPhase.loggedIn);
      await w.dispose(tester);
    });

    testWidgets('step 2 → Change number goes back with the number kept', (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app());
      await _openReset(tester);
      await _verifyNumber(tester);

      await _tap(tester, find.widgetWithText(TextButton, S.changeNumber));
      expect(find.text(S.otpStepTitle), findsOneWidget);
      expect(find.text('9000000001'), findsOneWidget);
      expect(find.text(S.resetStartAgain), findsNothing);
    });

    testWidgets("Can't get the code? Ask the admin → the old request, back to login",
        (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app());
      await _openReset(tester);
      await _tap(tester, _button(S.sendOtp));

      final link = find.byKey(const ValueKey('ask-admin'));
      expect(find.text(S.cantGetCode), findsOneWidget);

      // Cancel sends nothing.
      await _tap(tester, link);
      expect(find.text(S.askAdminTitle), findsOneWidget);
      expect(find.text(S.askAdminBody('9000000001')), findsOneWidget);
      await _tap(tester, find.widgetWithText(TextButton, S.cancel));
      expect(w.api.bodiesFor('/auth/forgot-password'), isEmpty);

      await _tap(tester, link);
      await _tap(tester, _button(S.forgotPasswordSend));
      expect(w.api.bodiesFor('/auth/forgot-password').single, {'phone': '9000000001'});
      expect(find.text(S.forgotPasswordSent), findsOneWidget);
      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(w.auth.phase, isNot(AuthPhase.loggedIn));
    });

    testWidgets('Back to login leaves without a request', (tester) async {
      _phone(tester);
      final w = _World();
      await tester.pumpWidget(w.app());
      await _openReset(tester);
      await _tap(tester, find.widgetWithText(TextButton, S.backToLogin));
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ForgotPasswordScreen), findsNothing);
      expect(w.api.posts, isEmpty);
    });

    testWidgets('narrow phone, large text: both steps lay out', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final w = _World();
      await tester.pumpWidget(w.app());
      await _openReset(tester);
      await _tap(tester, _button(S.sendOtp));
      expect(tester.takeException(), isNull);
      await tester.enterText(_field(S.otpCode), '123456');
      await _tap(tester, _button(S.verifyOtp));
      expect(find.text(S.newPasswordStepTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
