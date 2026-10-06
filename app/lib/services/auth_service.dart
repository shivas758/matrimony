import '../models/agent.dart';
import 'api_client.dart';

class AuthResult {
  const AuthResult({required this.token, required this.agent});

  final String token;
  final Agent agent;
}

/// Response of POST /auth/otp/send (SPEC §9.1).
class OtpSendResult {
  const OtpSendResult({
    required this.retryAfter,
    required this.expiresIn,
    this.mock = false,
    this.mockCode,
  });

  /// Seconds before another code may be requested.
  final int retryAfter;

  /// Seconds the code stays valid.
  final int expiresIn;
  final bool mock;

  /// Present only in test mode (OTP_PROVIDER=mock with echo on) — the app
  /// shows "Test mode — enter <code>".
  final String? mockCode;

  factory OtpSendResult.fromJson(Map<String, dynamic> j) => OtpSendResult(
        retryAfter: (j['retry_after'] as num?)?.toInt() ?? 30,
        expiresIn: (j['expires_in'] as num?)?.toInt() ?? 300,
        mock: j['mock'] == true,
        mockCode: j['mock_code'] == null ? null : '${j['mock_code']}',
      );
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
  Future<OtpSendResult> sendSignupOtp(String phone) async =>
      OtpSendResult.fromJson(await _api.post('/auth/otp/send', body: {'phone': phone}));

  /// Step 2: checks the code and returns the short-lived verification token
  /// that [signup] must present (`invalid_otp`, `otp_expired`, `too_many_attempts`).
  Future<String> verifySignupOtp(String phone, String code) async {
    final json = await _api.post('/auth/otp/verify', body: {'phone': phone, 'code': code});
    return '${json['verification_token']}';
  }

  Future<AuthResult> signup({
    required String fullName,
    required String phone,
    required String password,
    required List<int> communityIds,
    required String phoneVerificationToken,
    String? agencyName,
  }) async {
    final json = await _api.post('/auth/signup', body: {
      'full_name': fullName,
      'phone': phone,
      'password': password,
      'agency_name': agencyName,
      'community_ids': communityIds,
      'phone_verification_token': phoneVerificationToken,
    });
    return _store(json);
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
