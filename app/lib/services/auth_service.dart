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
  Future<OtpSendResult> sendSignupOtp(String phone) async {
    final result = OtpSendResult.fromJson(
      await _api.post('/auth/otp/send', body: {'phone': phone, 'firebase': true}),
    );
    if (result.isFirebase && result.firebase == null) {
      throw ApiException('otp_provider_error', S.otpSendFailed);
    }
    return result;
  }

  /// Step 2: checks the code and returns the short-lived verification token
  /// that [signup] must present (`invalid_otp`, `otp_expired`, `too_many_attempts`).
  Future<String> verifySignupOtp(String phone, String code) async {
    final json = await _api.post('/auth/otp/verify', body: {'phone': phone, 'code': code});
    return '${json['verification_token']}';
  }

  /// Step 2 with Firebase phone auth: the server checks the Firebase ID
  /// token instead of a code and answers the same verification token
  /// (`invalid_firebase_token`, `phone_mismatch`, `otp_provider_mismatch`).
  Future<String> verifySignupFirebase(String phone, String firebaseIdToken) async {
    final json = await _api.post(
      '/auth/otp/verify',
      body: {'phone': phone, 'firebase_id_token': firebaseIdToken},
    );
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

  /// "Forgot password?" — files a request the admin settles with a temporary
  /// password. Always succeeds from the app's point of view (SPEC §4 Auth).
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
