import '../models/agent.dart';
import '../ui/strings.dart';
import 'api_client.dart';
import 'phone_auth_gateway.dart';

class AuthResult {
  const AuthResult({required this.token, required this.agent});

  final String token;
  final Agent agent;
}

/// Response of POST /auth/otp/send (SPEC §9.1 / §9.19 A).
class OtpSendResult {
  const OtpSendResult({
    required this.retryAfter,
    required this.expiresIn,
    this.mock = false,
    this.mockCode,
    this.provider,
    this.firebase,
  });

  /// Seconds before another code may be requested.
  final int retryAfter;

  /// Seconds the code stays valid.
  final int expiresIn;
  final bool mock;

  /// Present only in test mode (OTP_PROVIDER=mock with echo on) — the app
  /// shows "Test mode — enter <code>".
  final String? mockCode;

  /// `mock` | `msg91` | `firebase`; null from a server older than v2.9
  /// (= the code flow).
  final String? provider;

  /// The Firebase client options when [provider] is `firebase` (null when
  /// any option is missing).
  final FirebaseClientOptions? firebase;

  /// The phone sends and checks the SMS through Firebase phone auth; the
  /// server only verifies the resulting Firebase ID token.
  bool get isFirebase => provider == 'firebase';

  factory OtpSendResult.fromJson(Map<String, dynamic> j) {
    final provider = j['provider'] == null ? null : '${j['provider']}'.trim().toLowerCase();
    return OtpSendResult(
      retryAfter: (j['retry_after'] as num?)?.toInt() ?? 30,
      expiresIn: (j['expires_in'] as num?)?.toInt() ?? 300,
      mock: j['mock'] == true,
      mockCode: j['mock_code'] == null ? null : '${j['mock_code']}',
      provider: provider == null || provider.isEmpty ? null : provider,
      firebase: provider == 'firebase' ? FirebaseClientOptions.fromJson(j['firebase']) : null,
    );
  }
}

/// Which one-time code the OTP routes send and check: the signup one
/// (SPEC §9.1) or the "Forgot password?" one (SPEC §9.24 D).
enum OtpPurpose { signup, reset }

class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  Future<AuthResult> login({required String phone, required String password}) async {
    final json = await _api.post('/auth/login', body: {'phone': phone, 'password': password});
    return _store(json);
  }

  // ---- OTP signup (SPEC §9.1)

  /// Step 1: sends a code to [phone]. `409 phone_taken` when the number is
  /// already an agent; `429 otp_cooldown` / `otp_limit` when asked too often.
  /// `firebase: true` tells the server this app can do Firebase phone auth
  /// (SPEC §9.19 A) — then the phone sends the SMS itself, with the options
  /// in the answer. A firebase answer without complete options is unusable:
  /// `otp_provider_error` with a plain "could not send" message.
  Future<OtpSendResult> sendSignupOtp(String phone) => _sendOtp(phone);

  /// Step 2: checks the code and returns the short-lived verification token
  /// that [signup] must present (`invalid_otp`, `otp_expired`, `too_many_attempts`).
  Future<String> verifySignupOtp(String phone, String code) =>
      _verifyOtp({'phone': phone, 'code': code});

  /// Step 2 with Firebase phone auth: the server checks the Firebase ID
  /// token instead of a code and answers the same verification token
  /// (`invalid_firebase_token`, `phone_mismatch`, `otp_provider_mismatch`).
  Future<String> verifySignupFirebase(String phone, String firebaseIdToken) =>
      _verifyOtp({'phone': phone, 'firebase_id_token': firebaseIdToken});

  // ---- "Forgot password?" by OTP (SPEC §9.24 D)

  /// Step 1: like [sendSignupOtp] with `purpose: 'reset'` — `404
  /// account_not_found` when the number is not an agent (before any SMS).
  Future<OtpSendResult> sendResetOtp(String phone) => _sendOtp(phone, purpose: 'reset');

  /// Step 2: the reset code → the verification token for [resetPassword].
  Future<String> verifyResetOtp(String phone, String code) =>
      _verifyOtp({'phone': phone, 'code': code, 'purpose': 'reset'});

  /// Step 2 with Firebase phone auth, as [verifySignupFirebase].
  Future<String> verifyResetFirebase(String phone, String firebaseIdToken) =>
      _verifyOtp({'phone': phone, 'firebase_id_token': firebaseIdToken, 'purpose': 'reset'});

  /// Step 3: the new password; answers `{token, agent}` exactly like [login]
  /// (`must_change_password` is cleared). `400 phone_not_verified` when the
  /// 15-minute verification token has lapsed.
  Future<AuthResult> resetPassword({
    required String phone,
    required String phoneVerificationToken,
    required String newPassword,
  }) async {
    final json = await _api.post('/auth/reset-password', body: {
      'phone': phone,
      'phone_verification_token': phoneVerificationToken,
      'new_password': newPassword,
    });
    return _store(json);
  }

  Future<OtpSendResult> _sendOtp(String phone, {String? purpose}) async {
    final result = OtpSendResult.fromJson(
      await _api.post('/auth/otp/send', body: {
        'phone': phone,
        'purpose': ?purpose,
        'firebase': true,
      }),
    );
    if (result.isFirebase && result.firebase == null) {
      throw ApiException('otp_provider_error', S.otpSendFailed);
    }
    return result;
  }

  Future<String> _verifyOtp(Map<String, Object> body) async {
    final json = await _api.post('/auth/otp/verify', body: body);
    return '${json['verification_token']}';
  }

  Future<AuthResult> signup({
    required String fullName,
    required String phone,
    required String password,
    required List<int> communityIds,
    required String phoneVerificationToken,
    String? agencyName,
    int? stateId,
    bool acceptedTerms = false,
  }) async {
    final json = await _api.post('/auth/signup', body: {
      'full_name': fullName,
      'phone': phone,
      'password': password,
      'agency_name': agencyName,
      'community_ids': communityIds,
      'phone_verification_token': phoneVerificationToken,
      // SPEC §9.18 B: the state decides the agent code, issued with the
      // account (`400 invalid_state`). Left out against an older server.
      'state_id': ?stateId,
      // SPEC §9.22 C: the Terms & Privacy checkbox (stamps the time).
      if (acceptedTerms) 'accepted_terms': true,
    });
    return _store(json);
  }

  /// `POST /my/state` — an agent registered before v2.8 chooses their state
  /// once and gets their permanent agent code (SPEC §9.18 B). Returns the
  /// refreshed agent. `409 state_already_set` when a code already exists,
  /// `400 invalid_state` for an unknown / inactive state.
  Future<Agent> chooseState(int stateId) async {
    final json = await _api.post('/my/state', body: {'state_id': stateId});
    return Agent.fromJson(json['agent'] as Map<String, dynamic>);
  }

  Future<Agent> me() async {
    final json = await _api.get('/auth/me');
    return Agent.fromJson(json['agent'] as Map<String, dynamic>);
  }

  Future<void> changePassword({required String current, required String next}) =>
      _api.post('/auth/change-password', body: {
        'current_password': current,
        'new_password': next,
      });

  /// "Can't get the code? Ask the admin" (SPEC §9.24 D) — files a request the
  /// admin settles with a temporary password. Always succeeds from the app's
  /// point of view (SPEC §4 Auth).
  Future<void> forgotPassword(String phone) =>
      _api.post('/auth/forgot-password', body: {'phone': phone});

  Future<bool> hasToken() async => (await _api.readToken())?.isNotEmpty ?? false;

  Future<void> logout() => _api.clearToken();

  Future<AuthResult> _store(Map<String, dynamic> json) async {
    final token = '${json['token']}';
    await _api.saveToken(token);
    return AuthResult(
      token: token,
      agent: Agent.fromJson(json['agent'] as Map<String, dynamic>),
    );
  }
}
