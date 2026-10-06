import '../models/customer.dart';
import 'api_client.dart';

/// POST /customer/auth/otp/send → {sent, mock, expires_in, retry_after, mock_code?}
class OtpSent {
  const OtpSent({
    required this.mock,
    this.mockCode,
    this.expiresIn = 300,
    this.retryAfter = 30,
  });

  /// True when the server runs the mock provider (SPEC §9.1) — nothing was
  /// actually sent, and [mockCode] carries the code to type.
  final bool mock;
  final String? mockCode;
  final int expiresIn;

  /// Seconds before "Resend" is allowed.
  final int retryAfter;

  factory OtpSent.fromJson(Map<String, dynamic> j) => OtpSent(
        mock: j['mock'] == true,
        mockCode: j['mock_code'] == null ? null : '${j['mock_code']}',
        expiresIn: (j['expires_in'] as num?)?.toInt() ?? 300,
        retryAfter: (j['retry_after'] as num?)?.toInt() ?? 30,
      );
}

/// POST /customer/auth/otp/verify answers one of two ways (SPEC §9.3 A).
sealed class OtpVerifyResult {
  const OtpVerifyResult();
}

/// The number is a known customer — token stored, session ready.
class LoggedIn extends OtpVerifyResult {
  const LoggedIn({required this.token, required this.customer});

  final String token;
  final Customer customer;
}

/// Unknown number — carry [verificationToken] (15 min) to the signup call.
class NeedsSignup extends OtpVerifyResult {
  const NeedsSignup({required this.verificationToken});

  final String verificationToken;
}

/// Customers have no password: every login is phone + OTP (SPEC §9.1).
class CustomerAuthService {
  CustomerAuthService(this._api);

  final ApiClient _api;

  Future<OtpSent> sendOtp(String phone) async =>
      OtpSent.fromJson(await _api.post('/customer/auth/otp/send', body: {'phone': phone}));

  Future<OtpVerifyResult> verifyOtp({required String phone, required String code}) async {
    final json = await _api.post('/customer/auth/otp/verify', body: {'phone': phone, 'code': code});
    if (json['new'] == true || json['token'] == null) {
      return NeedsSignup(verificationToken: '${json['verification_token']}');
    }
    return _store(json);
  }

  /// POST /customer/auth/signup {full_name, phone, phone_verification_token}
  /// → 201 {token, customer} as a `guest` with no agent (SPEC §9.12). The
  /// agent is chosen later from Get started.
  Future<LoggedIn> signup({
    required String fullName,
    required String phone,
    required String verificationToken,
  }) async {
    final json = await _api.post('/customer/auth/signup', body: {
      'full_name': fullName,
      'phone': phone,
      'phone_verification_token': verificationToken,
    });
    return _store(json);
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
