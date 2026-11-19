import '../models/customer.dart';
import 'api_client.dart';
import 'phone_auth_gateway.dart';

/// What a one-time code is for (SPEC §9.24 C): checking a new number before
/// *Create account*, or a registered one before *Forgot password?*. The
/// 3.5.0 app always says which — the server checks the number before any
/// SMS (`409 phone_taken` / `404 account_not_found`).
enum OtpPurpose {
  signup('signup'),
  reset('reset');

  const OtpPurpose(this.apiValue);

  /// The `purpose` value on the wire.
  final String apiValue;
}

/// POST /customer/auth/otp/send → {sent, provider, mock, expires_in,
/// retry_after, mock_code?, firebase?} (SPEC §9.1, §9.19 A).
class OtpSent {
  const OtpSent({
    required this.mock,
    this.mockCode,
    this.expiresIn = 300,
    this.retryAfter = 30,
    this.provider,
    this.firebase,
  });

  /// True when the server runs the mock provider (SPEC §9.1) — nothing was
  /// actually sent, and [mockCode] carries the code to type.
  final bool mock;
  final String? mockCode;
  final int expiresIn;

  /// Seconds before "Resend" is allowed.
  final int retryAfter;

  /// 'mock' | 'msg91' | 'startmessaging' | 'firebase' …; null from servers
  /// older than v2.9 (they only know the code flow).
  final String? provider;

  /// The Firebase client options when [provider] is 'firebase' — null when
  /// any option is missing (the app then says it could not send the code).
  final FirebaseClientOptions? firebase;

  /// The phone itself sends and receives the SMS through Firebase; the
  /// server only checks the resulting ID token. Otherwise (mock / msg91 /
  /// an older server) the server sent a code to type.
  bool get isFirebase => provider == 'firebase';

  factory OtpSent.fromJson(Map<String, dynamic> j) => OtpSent(
        mock: j['mock'] == true,
        mockCode: j['mock_code'] == null ? null : '${j['mock_code']}',
        expiresIn: (j['expires_in'] as num?)?.toInt() ?? 300,
        retryAfter: (j['retry_after'] as num?)?.toInt() ?? 30,
        provider: j['provider'] == null ? null : '${j['provider']}',
        firebase: FirebaseClientOptions.tryParse(j['firebase']),
      );
}

/// POST /customer/auth/otp/verify answers one of two ways.
sealed class OtpVerifyResult {
  const OtpVerifyResult();
}

/// Token stored, session ready. Only a server that ignores `purpose` (older
/// than v2.14) answers a verify like this — the old "a known number logs
/// in" (SPEC §9.3 A); the app then simply continues logged in.
class LoggedIn extends OtpVerifyResult {
  const LoggedIn({required this.token, required this.customer});

  final String token;
  final Customer customer;
}

/// The number is checked — carry [verificationToken] (15 min) to the signup
/// call (purpose `signup`) or to the new password (purpose `reset`).
class PhoneVerified extends OtpVerifyResult {
  const PhoneVerified({required this.verificationToken});

  final String verificationToken;
}

/// Customer login with mobile + password; a one-time code only to create an
/// account or to reset a forgotten password (SPEC §9.24 C).
class CustomerAuthService {
  CustomerAuthService(this._api);

  final ApiClient _api;

  /// POST /customer/auth/login {phone, password} → {token, customer}.
  /// `401 bad_credentials`; `409 password_not_set` (the number has no
  /// password yet — the app sends it to Forgot password).
  Future<LoggedIn> login({required String phone, required String password}) async =>
      _store(await _api.post('/customer/auth/login', body: {'phone': phone, 'password': password}));

  /// Always says `firebase: true` ("this app can do Firebase phone auth",
  /// SPEC §9.19 A); mock / msg91 servers ignore it. [purpose] `signup` →
  /// `409 phone_taken`, `reset` → `404 account_not_found`, both before any SMS.
  Future<OtpSent> sendOtp(String phone, {required OtpPurpose purpose}) async =>
      OtpSent.fromJson(await _api.post('/customer/auth/otp/send', body: {
        'phone': phone,
        'purpose': purpose.apiValue,
        'firebase': true,
      }));

  /// mock / msg91: the typed code.
  Future<OtpVerifyResult> verifyOtp({
    required String phone,
    required String code,
    required OtpPurpose purpose,
  }) async =>
      _verifyAnswer(await _api.post('/customer/auth/otp/verify', body: {
        'phone': phone,
        'code': code,
        'purpose': purpose.apiValue,
      }));

  /// firebase: the Firebase ID token the phone got once the code was
  /// accepted (SPEC §9.19 A). Same answers as [verifyOtp]; new errors
  /// `invalid_firebase_token`, `phone_mismatch`, `otp_provider_mismatch`.
  Future<OtpVerifyResult> verifyFirebaseToken({
    required String phone,
    required String idToken,
    required OtpPurpose purpose,
  }) async =>
      _verifyAnswer(await _api.post('/customer/auth/otp/verify', body: {
        'phone': phone,
        'firebase_id_token': idToken,
        'purpose': purpose.apiValue,
      }));

  Future<OtpVerifyResult> _verifyAnswer(Map<String, dynamic> json) async {
    if (json['token'] == null || json['customer'] is! Map) {
      return PhoneVerified(verificationToken: '${json['verification_token']}');
    }
    return _store(json);
  }

  /// POST /customer/auth/signup {full_name, phone, password,
  /// phone_verification_token, accepted_terms} → 201 {token, customer} as a
  /// `guest` with no agent (SPEC §9.12 / §9.24 C). The agent is chosen later
  /// from Get started. [acceptedTerms]: the Terms & Privacy checkbox was
  /// ticked (SPEC §9.22 C).
  Future<LoggedIn> signup({
    required String fullName,
    required String phone,
    required String password,
    required String verificationToken,
    bool acceptedTerms = false,
  }) async {
    final json = await _api.post('/customer/auth/signup', body: {
      'full_name': fullName,
      'phone': phone,
      'password': password,
      'phone_verification_token': verificationToken,
      if (acceptedTerms) 'accepted_terms': true,
    });
    return _store(json);
  }

  /// POST /customer/auth/reset-password {phone, phone_verification_token,
  /// new_password} → {token, customer} — logged in (SPEC §9.24 C / D). The
  /// token comes from a verify with purpose `reset`; `400 phone_not_verified`
  /// when it lapsed.
  Future<LoggedIn> resetPassword({
    required String phone,
    required String verificationToken,
    required String newPassword,
  }) async =>
      _store(await _api.post('/customer/auth/reset-password', body: {
        'phone': phone,
        'phone_verification_token': verificationToken,
        'new_password': newPassword,
      }));

  /// POST /customer/auth/change-password {current_password?, new_password}
  /// → {ok: true}. [currentPassword] is left out when the account has none
  /// yet (*Set a password*); a wrong one is `401 bad_credentials`.
  Future<void> changePassword({String? currentPassword, required String newPassword}) async {
    await _api.post('/customer/auth/change-password', body: {
      'current_password': ?currentPassword,
      'new_password': newPassword,
    });
  }

  /// Allowed in every state (guest … suspended).
  Future<Customer> me() async {
    final json = await _api.get('/customer/auth/me');
    return Customer.fromJson(json['customer'] as Map<String, dynamic>);
  }

  Future<bool> hasToken() async => (await _api.readToken())?.isNotEmpty ?? false;

  Future<void> logout() => _api.clearToken();

  Future<LoggedIn> _store(Map<String, dynamic> json) async {
    final token = '${json['token']}';
    await _api.saveToken(token);
    return LoggedIn(
      token: token,
      customer: Customer.fromJson(json['customer'] as Map<String, dynamic>),
    );
  }
}
