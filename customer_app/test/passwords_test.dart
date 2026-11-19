import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/services/customer_auth_service.dart';
import 'package:gandharva/services/phone_auth_gateway.dart';
import 'package:gandharva/state/auth_state.dart';
import 'package:gandharva/ui/screens/auth/change_password_screen.dart';
import 'package:gandharva/ui/screens/auth/login_screen.dart';
import 'package:gandharva/ui/screens/auth/otp_screen.dart';
import 'package:gandharva/ui/screens/auth/phone_screen.dart';
import 'package:gandharva/ui/screens/auth/reset_password_screen.dart';
import 'package:gandharva/ui/screens/auth/signup_screen.dart';
import 'package:gandharva/ui/screens/more_screen.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:gandharva/ui/widgets/common.dart';
import 'package:gandharva/ui/widgets/password_field.dart';
import 'package:provider/provider.dart';

import 'guest_mode_test.dart' show guestMeJson;

// SPEC §9.24 C / D (v2.14 server, Wedbook Matrimony 3.5.0): log in with
// mobile + password; Create account and Forgot password by one-time code;
// Change password / Set a password in More.

const _phoneNo = '9876543210';
const _loginPath = '/customer/auth/login';
const _sendPath = '/customer/auth/otp/send';
const _verifyPath = '/customer/auth/otp/verify';
const _signupPath = '/customer/auth/signup';
const _resetPath = '/customer/auth/reset-password';
const _changePath = '/customer/auth/change-password';

/// Answers GET / POST from per-path queues (the last answer sticks); an
/// answer may be a map or an [ApiException] to throw. Records every call and
/// keeps the token in memory.
class _FakeApi extends ApiClient {
  final calls = <(String, String, Object?)>[];
  final _answers = <String, List<Object>>{};
  String? token;

  void answer(String path, Object reply, {String method = 'POST'}) =>
      _answers.putIfAbsent('$method $path', () => []).add(reply);

  List<Object?> bodiesFor(String path, {String method = 'POST'}) => [
        for (final (m, p, b) in calls)
          if (m == method && p == path) b,
      ];

  Future<Map<String, dynamic>> _reply(String method, String path, Object? body) async {
    calls.add((method, path, body));
    final queue = _answers['$method $path'];
    if (queue == null || queue.isEmpty) throw StateError('unexpected $method $path');
    final reply = queue.length == 1 ? queue.first : queue.removeAt(0);
    if (reply is ApiException) throw reply;
    return reply as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) => _reply('POST', path, body);

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) => _reply('GET', path, query);

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String t) async => token = t;

  @override
  Future<void> clearToken() async => token = null;

  @override
  String? get tokenSync => token;
}

/// The mock / msg91 code flow never touches Firebase.
class _NoFirebase implements PhoneAuthGateway {
  @override
  Future<PhoneVerificationStep> start(FirebaseClientOptions options, String phone10, {int? resendToken}) =>
      throw StateError('Firebase must not be started');

  @override
  Stream<PhoneAutoVerified> get autoVerified => const Stream.empty();

  @override
  Future<String> confirmCode(String verificationId, String smsCode) => throw StateError('no Firebase');

  @override
  Future<void> signOut() async {}
}

/// The real [ApiClient] (Dio + its interceptor) over canned HTTP answers by
/// path — to see which errors log the customer out.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.answers);

  final Map<String, (int, Map<String, dynamic>)> answers;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final (status, body) = answers[options.path] ?? (404, {'error': 'not_found', 'message': options.path});
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _DioBackedApi extends ApiClient {
  _DioBackedApi(Map<String, (int, Map<String, dynamic>)> answers) {
    dio.httpClientAdapter = _CannedAdapter(answers);
  }

  String? token = 'jwt-1';

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String t) async => token = t;

  @override
  Future<void> clearToken() async => token = null;
}

Map<String, dynamic> _mockSend() => {
      'sent': true,
      'provider': 'mock',
      'mock': true,
      'expires_in': 300,
      'retry_after': 30,
      'mock_code': '123456',
    };

Map<String, dynamic> _session({bool hasPassword = true}) => {
      'token': 'jwt-1',
      'customer': {...guestMeJson(), 'has_password': hasPassword},
    };

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
Future<void> _dispose(WidgetTester tester) => tester.pumpWidget(const SizedBox.shrink());

Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

Finder _field(String label) => find.widgetWithText(TextFormField, label);

String _text(WidgetTester tester, String label) => tester.widget<TextFormField>(_field(label)).controller!.text;

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

/// Like the app's root: the login screen while logged out, Home once in.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) => context.watch<AuthState>().phase == AuthPhase.loggedIn
      ? const Scaffold(body: Center(child: Text('HOME')))
      : const LoginScreen();
}

class _Host {
  _Host() {
    auth = AuthState(api: api, auth: CustomerAuthService(api));
  }

  final api = _FakeApi();
  late final AuthState auth;

  Widget wrap([Widget home = const _Root()]) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<PhoneAuthGateway>.value(value: _NoFirebase()),
          ChangeNotifierProvider<AuthState>.value(value: auth),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );

  Future<void> pump(WidgetTester tester, [Widget home = const _Root()]) async {
    await _phone(tester);
    await tester.pumpWidget(wrap(home));
    await tester.pump();
  }

  /// Logged in with [hasPassword] (the login call), for the More tests.
  Future<void> logIn({bool hasPassword = true}) async {
    api.answer(_loginPath, _session(hasPassword: hasPassword));
    await auth.login(phone: _phoneNo, password: 'secret12');
  }
}

/// The OTP screen of the mock provider: fill the test code, Verify.
Future<void> _enterMockCode(WidgetTester tester) async {
  expect(find.byType(OtpScreen), findsOneWidget);
  expect(find.text(S.testModeHint('123456')), findsOneWidget);
  await tester.tap(find.text(S.testModeHint('123456')));
  await tester.pump();
  await tester.tap(find.text(S.verify));
  await _settle(tester);
}

void main() {
  // ================================================================ models + service

  group('Models and calls (SPEC §9.24 C)', () {
    test('has_password: parsed, true when an older server leaves it out; copyWith keeps the rest', () {
      expect(Customer.fromJson(guestMeJson()).hasPassword, isTrue);
      final none = Customer.fromJson({...guestMeJson(), 'has_password': false});
      expect(none.hasPassword, isFalse);
      expect(Customer.fromJson({...guestMeJson(), 'has_password': true}).hasPassword, isTrue);
      final set = none.copyWith(hasPassword: true);
      expect(set.hasPassword, isTrue);
      expect((set.id, set.phone, set.status, set.profileFeeInr), (none.id, none.phone, none.status, none.profileFeeInr));
    });

    test('a wrong password never counts as a dead session; a dead token does', () {
      expect(ApiException('bad_credentials', 'x', status: 401).isAuthProblem, isFalse);
      expect(ApiException('bad_credentials', 'x', status: 401).isBadCredentials, isTrue);
      expect(ApiException('invalid_token', 'x', status: 401).isAuthProblem, isTrue);
      expect(ApiException('missing_token', 'x').isAuthProblem, isTrue);
      expect(ApiException('password_not_set', 'x', status: 409).isAuthProblem, isFalse);
    });

    test('error codes in plain words', () {
      String m(String code) => friendlyMessage(ApiException(code, 'server words'));
      expect(m('bad_credentials'), S.errBadCredentials);
      expect(m('password_not_set'), S.setPasswordFirst);
      expect(m('account_not_found'), S.errAccountNotFound);
      expect(m('phone_taken'), S.errPhoneTaken);
      expect(S.errBadCredentials, 'Mobile number or password is incorrect');
      expect(S.errPhoneTaken, 'This number is already registered — log in with your password');
      expect(S.errAccountNotFound, 'No account with this mobile number');
    });

    test('password rules: 6–100 characters; the confirmation must match', () {
      expect(validateNewPassword('12345'), S.passwordTooShort);
      expect(validateNewPassword('123456'), isNull);
      expect(validateNewPassword('x' * 100), isNull);
      expect(validateNewPassword('x' * 101), S.passwordTooLong);
      final c = TextEditingController(text: 'secret12');
      addTearDown(c.dispose);
      expect(confirmPasswordValidator(c)('secret12'), isNull);
      expect(confirmPasswordValidator(c)('secret13'), S.passwordsDoNotMatch);
    });

    test('every call carries the right body', () async {
      final api = _FakeApi()
        ..answer(_loginPath, _session())
        ..answer(_sendPath, _mockSend())
        ..answer(_verifyPath, {'verification_token': 'vt-r'})
        ..answer(_resetPath, _session())
        ..answer(_changePath, {'ok': true});
      final s = CustomerAuthService(api);

      final login = await s.login(phone: _phoneNo, password: 'pw 123');
      expect(api.bodiesFor(_loginPath).single, {'phone': _phoneNo, 'password': 'pw 123'});
      expect(login.customer.hasPassword, isTrue);
      expect(api.token, 'jwt-1');

      await s.sendOtp(_phoneNo, purpose: OtpPurpose.reset);
      expect(api.bodiesFor(_sendPath).single, {'phone': _phoneNo, 'purpose': 'reset', 'firebase': true});
      final verified = await s.verifyOtp(phone: _phoneNo, code: '123456', purpose: OtpPurpose.reset);
      expect(api.bodiesFor(_verifyPath).single, {'phone': _phoneNo, 'code': '123456', 'purpose': 'reset'});
      expect((verified as PhoneVerified).verificationToken, 'vt-r');

      await s.resetPassword(phone: _phoneNo, verificationToken: 'vt-r', newPassword: 'newpass1');
      expect(api.bodiesFor(_resetPath).single,
          {'phone': _phoneNo, 'phone_verification_token': 'vt-r', 'new_password': 'newpass1'});

      await s.changePassword(currentPassword: 'old', newPassword: 'newpass2');
      await s.changePassword(newPassword: 'newpass3');
      expect(api.bodiesFor(_changePath), [
        {'current_password': 'old', 'new_password': 'newpass2'},
        {'new_password': 'newpass3'},
      ]);
    });

    test('through the real client: 401 bad_credentials keeps me logged in, 401 invalid_token logs out', () async {
      Future<(_DioBackedApi, AuthState)> loggedIn(int status, String code) async {
        final api = _DioBackedApi({
          '/customer/auth/me': (200, {'customer': guestMeJson()}),
          _changePath: (status, {'error': code, 'message': 'no'}),
        });
        final auth = AuthState(api: api, auth: CustomerAuthService(api));
        await auth.bootstrap();
        expect(auth.phase, AuthPhase.loggedIn);
        return (api, auth);
      }

      final (wrongApi, wrong) = await loggedIn(401, 'bad_credentials');
      await expectLater(
        wrong.changePassword(currentPassword: 'nope', newPassword: 'newpass1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'bad_credentials')),
      );
      expect(wrong.phase, AuthPhase.loggedIn, reason: 'a wrong current password never logs out');
      expect(wrongApi.token, 'jwt-1');

      final (deadApi, dead) = await loggedIn(401, 'invalid_token');
      await expectLater(
        dead.changePassword(currentPassword: 'old', newPassword: 'newpass1'),
        throwsA(isA<ApiException>()),
      );
      expect(dead.phase, AuthPhase.loggedOut, reason: 'a dead token logs out');
      expect(deadApi.token, isNull);
    });
  });

  // ================================================================ log in

  group('Log in with mobile + password', () {
    testWidgets('the entry screen: mobile, password, Log in, Forgot password?, Create account', (tester) async {
      final host = _Host();
      await host.pump(tester);
      expect(_field(S.phone), findsOneWidget);
      expect(_field(S.password), findsOneWidget);
      expect(find.text(S.forgotPassword), findsOneWidget);
      expect(_button(S.createAccount), findsOneWidget);
      expect(_button(S.logIn), findsOneWidget);
      expect(find.text(S.sendOtp), findsNothing, reason: 'no SMS to log in');
      // The password is hidden until the eye is tapped.
      final input = find.descendant(of: _field(S.password), matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(input).obscureText, isTrue);
      await tester.tap(find.byTooltip(S.showPassword));
      await tester.pump();
      expect(tester.widget<EditableText>(input).obscureText, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('success → token stored, Home', (tester) async {
      final host = _Host();
      host.api.answer(_loginPath, _session());
      await host.pump(tester);
      await tester.enterText(_field(S.phone), _phoneNo);
      await tester.enterText(_field(S.password), 'secret12');
      await _tap(tester, _button(S.logIn));
      expect(host.api.bodiesFor(_loginPath).single, {'phone': _phoneNo, 'password': 'secret12'});
      expect(host.api.token, 'jwt-1');
      expect(host.auth.phase, AuthPhase.loggedIn);
      expect(find.text('HOME'), findsOneWidget);
      expect(host.api.bodiesFor(_sendPath), isEmpty, reason: 'no SMS');
    });

    testWidgets('missing number / password are asked for; nothing is sent', (tester) async {
      final host = _Host();
      await host.pump(tester);
      await _tap(tester, _button(S.logIn));
      expect(find.text(S.phoneInvalid), findsOneWidget);
      expect(find.text(S.passwordRequired), findsOneWidget);
      expect(host.api.calls, isEmpty);
    });

    testWidgets('401 bad_credentials → "Mobile number or password is incorrect"', (tester) async {
      final host = _Host();
      host.api.answer(_loginPath, ApiException('bad_credentials', 'Mobile number or password is incorrect', status: 401));
      await host.pump(tester);
      await tester.enterText(_field(S.phone), _phoneNo);
      await tester.enterText(_field(S.password), 'wrong-pw');
      await _tap(tester, _button(S.logIn));
      expect(find.text(S.errBadCredentials), findsOneWidget);
      expect(host.auth.phase, isNot(AuthPhase.loggedIn));
      expect(host.api.token, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('409 password_not_set → Forgot password for that number → code → new password → in',
        (tester) async {
      final host = _Host();
      host.api
        ..answer(_loginPath, ApiException('password_not_set', 'Set a password for this number first', status: 409))
        ..answer(_sendPath, _mockSend())
        ..answer(_verifyPath, {'verification_token': 'vt-r'})
        ..answer(_resetPath, {'token': 'jwt-r', 'customer': guestMeJson()});
      await host.pump(tester);
      await tester.enterText(_field(S.phone), _phoneNo);
      await tester.enterText(_field(S.password), 'anything');
      await _tap(tester, _button(S.logIn));

      // Straight into Forgot password, the number filled in, with the reason.
      expect(find.byType(PhoneScreen), findsOneWidget);
      expect(find.text(S.resetPhoneTitle), findsOneWidget);
      expect(find.text(S.setPasswordFirst), findsOneWidget);
      expect(_text(tester, S.phone), _phoneNo);
      expect(host.api.bodiesFor(_sendPath), isEmpty, reason: 'the SMS goes only on Send OTP');

      await _tap(tester, find.text(S.sendOtp));
      expect(host.api.bodiesFor(_sendPath).single, {'phone': _phoneNo, 'purpose': 'reset', 'firebase': true});
      await _enterMockCode(tester);
      expect(host.api.bodiesFor(_verifyPath).single, {'phone': _phoneNo, 'code': '123456', 'purpose': 'reset'});

      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.text('+91 $_phoneNo'), findsOneWidget);
      await tester.enterText(_field(S.newPassword), 'newpass1');
      await tester.enterText(_field(S.confirmPassword), 'newpass1');
      await _tap(tester, _button(S.saveAndLogIn));
      expect(host.api.bodiesFor(_resetPath).single,
          {'phone': _phoneNo, 'phone_verification_token': 'vt-r', 'new_password': 'newpass1'});
      expect(host.api.token, 'jwt-r');
      expect(find.text('HOME'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  // ================================================================ create account

  group('Create account: mobile → code → name + password + terms', () {
    testWidgets('the whole way in; password + confirm sent with the signup', (tester) async {
      final host = _Host();
      host.api
        ..answer(_sendPath, _mockSend())
        ..answer(_verifyPath, {'verification_token': 'vt-s'})
        ..answer(_signupPath, {'token': 'jwt-new', 'customer': guestMeJson()});
      await host.pump(tester);
      await _tap(tester, _button(S.createAccount));
      expect(find.text(S.signupPhoneBody), findsOneWidget);
      await tester.enterText(_field(S.phone), _phoneNo);
      await _tap(tester, find.text(S.sendOtp));
      expect(host.api.bodiesFor(_sendPath).single, {'phone': _phoneNo, 'purpose': 'signup', 'firebase': true});

      // Six digits verify by themselves.
      await tester.enterText(find.byType(TextFormField), '123456');
      await _settle(tester);
      expect(host.api.bodiesFor(_verifyPath).single, {'phone': _phoneNo, 'code': '123456', 'purpose': 'signup'});

      expect(find.byType(SignupScreen), findsOneWidget);
      expect(find.textContaining('I agree to the'), findsOneWidget, reason: 'the Terms consent stays');
      await tester.enterText(_field(S.fullName), 'Srinivasa Reddy');
      await tester.enterText(_field(S.password), 'secret12');
      await tester.enterText(_field(S.confirmPassword), 'secret12');
      await _tap(tester, find.byType(Checkbox));
      await _tap(tester, _button(S.createAccount));
      expect(host.api.bodiesFor(_signupPath).single, {
        'full_name': 'Srinivasa Reddy',
        'phone': _phoneNo,
        'password': 'secret12',
        'phone_verification_token': 'vt-s',
        'accepted_terms': true,
      });
      expect(host.api.token, 'jwt-new');
      expect(find.text('HOME'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('a short or mismatched password is caught before sending', (tester) async {
      final host = _Host();
      await host.pump(tester, const SignupScreen(phone: _phoneNo, verificationToken: 'vt-s'));
      await tester.enterText(_field(S.fullName), 'Srinivasa Reddy');
      await tester.enterText(_field(S.password), '12345');
      await tester.enterText(_field(S.confirmPassword), '123456');
      await _tap(tester, find.byType(Checkbox));
      await _tap(tester, _button(S.createAccount));
      expect(find.text(S.passwordTooShort), findsOneWidget);
      expect(find.text(S.passwordsDoNotMatch), findsOneWidget);
      expect(host.api.calls, isEmpty);
    });

    testWidgets('409 phone_taken → "already registered" + Log in with this number → back, number filled',
        (tester) async {
      final host = _Host();
      host.api.answer(
        _sendPath,
        ApiException('phone_taken', 'This number is already registered — log in with your password', status: 409),
      );
      await host.pump(tester);
      expect(_text(tester, S.phone), isEmpty);
      await _tap(tester, _button(S.createAccount));
      await tester.enterText(_field(S.phone), _phoneNo);
      await _tap(tester, find.text(S.sendOtp));
      expect(find.text(S.errPhoneTaken), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing, reason: 'no SMS for a registered number');

      await _tap(tester, _button(S.logInWithNumber));
      expect(find.byType(PhoneScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(_text(tester, S.phone), _phoneNo);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an expired verification (400 phone_not_verified) → Start again → the login screen',
        (tester) async {
      final host = _Host();
      host.api.answer(_signupPath, ApiException('phone_not_verified', 'expired', status: 400));
      await host.pump(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(builder: (_) => const SignupScreen(phone: _phoneNo, verificationToken: 'vt')));
      await _settle(tester);
      await tester.enterText(_field(S.fullName), 'Srinivasa Reddy');
      await tester.enterText(_field(S.password), 'secret12');
      await tester.enterText(_field(S.confirmPassword), 'secret12');
      await _tap(tester, find.byType(Checkbox));
      await _tap(tester, _button(S.createAccount));
      expect(find.text(S.errPhoneNotVerified), findsOneWidget);
      await _tap(tester, _button(S.startAgain));
      expect(find.byType(SignupScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  // ================================================================ forgot password

  group('Forgot password: mobile → code → new password → logged in', () {
    testWidgets('from the login screen, the typed number prefilled; resend waits as before', (tester) async {
      final host = _Host();
      host.api
        ..answer(_sendPath, _mockSend())
        ..answer(_verifyPath, {'verification_token': 'vt-r'})
        ..answer(_resetPath, {'token': 'jwt-r', 'customer': guestMeJson()});
      await host.pump(tester);
      await tester.enterText(_field(S.phone), _phoneNo);
      await _tap(tester, find.text(S.forgotPassword));
      expect(find.text(S.resetPhoneBody), findsOneWidget);
      expect(find.text(S.setPasswordFirst), findsNothing);
      expect(_text(tester, S.phone), _phoneNo);
      await _tap(tester, find.text(S.sendOtp));

      // Resend after the 30 s cooldown, again for a reset.
      expect(find.textContaining('Resend code in'), findsOneWidget);
      expect(find.text(S.resendOtp), findsNothing);
      await tester.pump(const Duration(seconds: 31));
      await _tap(tester, find.text(S.resendOtp));
      expect(find.text(S.otpResent), findsOneWidget);
      expect(host.api.bodiesFor(_sendPath), [
        {'phone': _phoneNo, 'purpose': 'reset', 'firebase': true},
        {'phone': _phoneNo, 'purpose': 'reset', 'firebase': true},
      ]);

      await _enterMockCode(tester);
      await tester.enterText(_field(S.newPassword), 'newpass1');
      await tester.enterText(_field(S.confirmPassword), 'newpass1');
      await tester.showKeyboard(_field(S.confirmPassword));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(host.api.bodiesFor(_resetPath).single,
          {'phone': _phoneNo, 'phone_verification_token': 'vt-r', 'new_password': 'newpass1'});
      expect(host.auth.phase, AuthPhase.loggedIn);
      expect(find.text('HOME'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('404 account_not_found → "No account" + Create account with the number', (tester) async {
      final host = _Host();
      host.api.answer(_sendPath, ApiException('account_not_found', 'No account with this mobile number', status: 404));
      await host.pump(tester);
      await _tap(tester, find.text(S.forgotPassword));
      await tester.enterText(_field(S.phone), _phoneNo);
      await _tap(tester, find.text(S.sendOtp));
      expect(find.text(S.errAccountNotFound), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);

      await _tap(tester, _button(S.createAccount));
      // Now the Create account step, with the same number.
      expect(find.text(S.signupPhoneBody), findsOneWidget);
      expect(find.text(S.resetPhoneBody), findsNothing);
      expect(_text(tester, S.phone), _phoneNo);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mismatched new passwords are caught; an expired verification offers Start again',
        (tester) async {
      final host = _Host();
      host.api.answer(_resetPath, ApiException('phone_not_verified', 'expired', status: 400));
      await host.pump(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(MaterialPageRoute<void>(
        builder: (_) => const ResetPasswordScreen(phone: _phoneNo, verificationToken: 'vt-r'),
      ));
      await _settle(tester);
      await tester.enterText(_field(S.newPassword), 'newpass1');
      await tester.enterText(_field(S.confirmPassword), 'newpass2');
      await _tap(tester, _button(S.saveAndLogIn));
      expect(find.text(S.passwordsDoNotMatch), findsOneWidget);
      expect(host.api.calls, isEmpty);

      await tester.enterText(_field(S.confirmPassword), 'newpass1');
      await _tap(tester, _button(S.saveAndLogIn));
      expect(find.text(S.errPhoneNotVerified), findsOneWidget);
      expect(_button(S.saveAndLogIn), findsNothing);
      await _tap(tester, _button(S.startAgain));
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  // ================================================================ More → change / set

  group('More → Change password / Set a password', () {
    Future<void> openFromMore(WidgetTester tester, _Host host, String tile) async {
      await host.pump(tester, const MoreScreen());
      await tester.scrollUntilVisible(find.text(tile), 300, scrollable: find.byType(Scrollable).first);
      await _tap(tester, find.text(tile));
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
    }

    testWidgets('Change password: current + new + confirm; a wrong current one never logs out', (tester) async {
      final host = _Host();
      await host.logIn();
      host.api
        ..answer(_changePath, ApiException('bad_credentials', 'Current password is incorrect', status: 401))
        ..answer(_changePath, {'ok': true});
      await openFromMore(tester, host, S.changePassword);
      expect(find.text(S.changePasswordBody), findsOneWidget);
      expect(find.byType(PasswordField), findsNWidgets(3));
      expect(_field(S.currentPassword), findsOneWidget);

      await tester.enterText(_field(S.currentPassword), 'wrong-pw');
      await tester.enterText(_field(S.newPassword), 'newpass1');
      await tester.enterText(_field(S.confirmPassword), 'newpass1');
      await _tap(tester, _button(S.savePassword));
      expect(find.text(S.errCurrentPasswordWrong), findsOneWidget);
      expect(host.auth.phase, AuthPhase.loggedIn);
      expect(host.api.token, 'jwt-1');

      await tester.enterText(_field(S.currentPassword), 'secret12');
      await _tap(tester, _button(S.savePassword));
      expect(host.api.bodiesFor(_changePath).last, {'current_password': 'secret12', 'new_password': 'newpass1'});
      expect(find.byType(ChangePasswordScreen), findsNothing);
      expect(find.text(S.passwordChanged), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new password must be 6+ characters and confirmed', (tester) async {
      final host = _Host();
      await host.logIn();
      await openFromMore(tester, host, S.changePassword);
      await tester.enterText(_field(S.currentPassword), 'secret12');
      await tester.enterText(_field(S.newPassword), 'abc');
      await tester.enterText(_field(S.confirmPassword), 'abd');
      await _tap(tester, _button(S.savePassword));
      expect(find.text(S.passwordTooShort), findsOneWidget);
      expect(find.text(S.passwordsDoNotMatch), findsOneWidget);
      expect(host.api.bodiesFor(_changePath), isEmpty);
    });

    testWidgets('no password yet: Set a password (new + confirm only) → More then offers Change password',
        (tester) async {
      final host = _Host();
      await host.logIn(hasPassword: false);
      host.api.answer(_changePath, {'ok': true});
      await host.pump(tester, const MoreScreen());
      expect(find.text(S.changePassword), findsNothing);
      await tester.scrollUntilVisible(find.text(S.setPassword), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text(S.setPasswordHint), findsOneWidget);
      await _tap(tester, find.text(S.setPassword));

      expect(find.text(S.setPasswordBody), findsOneWidget);
      expect(find.byType(PasswordField), findsNWidgets(2));
      expect(_field(S.currentPassword), findsNothing);
      await tester.enterText(_field(S.newPassword), 'newpass1');
      await tester.enterText(_field(S.confirmPassword), 'newpass1');
      await _tap(tester, _button(S.savePassword));
      expect(host.api.bodiesFor(_changePath).single, {'new_password': 'newpass1'});
      expect(find.text(S.passwordSet), findsOneWidget);
      expect(host.auth.customer!.hasPassword, isTrue);
      expect(find.text(S.changePassword), findsOneWidget);
      expect(find.text(S.setPassword), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('logout says how to come back in', () {
      expect(S.logoutConfirm, contains('password'));
      expect(S.logoutConfirm, isNot(contains('one-time code')));
    });
  });
}
