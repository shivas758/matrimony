import 'package:flutter/material.dart';

import '../../../services/api_client.dart';
import '../../../services/customer_auth_service.dart';
import '../../../services/phone_auth_gateway.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import 'signup_screen.dart';

/// The send → verify steps shared by the phone and OTP screens, for every
/// OTP provider (SPEC §9.1 code flow, §9.19 A Firebase phone auth).

/// A Firebase phone verification in progress — what the OTP screen needs to
/// confirm the typed code and to resend it.
class FirebaseOtpSession {
  const FirebaseOtpSession({required this.options, required this.verificationId, this.resendToken});

  final FirebaseClientOptions options;
  final String verificationId;

  /// Firebase's `forceResendingToken` for "Resend code".
  final int? resendToken;
}

/// How "Send OTP" / "Resend code" ended.
sealed class OtpRequest {
  const OtpRequest();
}

/// A code to type: the server's own (mock / msg91 — [session] is null) or
/// the SMS Firebase sent ([session] set).
final class OtpCodeNeeded extends OtpRequest {
  const OtpCodeNeeded(this.sent, {this.session});

  final OtpSent sent;
  final FirebaseOtpSession? session;
}

/// Android verified the number by itself and the server already answered.
final class OtpAutoVerified extends OtpRequest {
  const OtpAutoVerified(this.result);

  final OtpVerifyResult result;
}

/// The server's send, then — when its provider is `firebase` — Firebase's
/// own verification of `+91<phone>`. Throws [ApiException] (server) or
/// [PhoneAuthFailure] (Firebase).
Future<OtpRequest> requestOtp(
  AuthState auth,
  PhoneAuthGateway gateway,
  String phone, {
  int? resendToken,
}) async {
  final sent = await auth.sendOtp(phone);
  if (!sent.isFirebase) return OtpCodeNeeded(sent);
  final options = sent.firebase;
  if (options == null) {
    // provider firebase without complete client options: nothing to start.
    throw ApiException('otp_provider_error', S.otpCouldNotSend);
  }
  final step = await gateway.start(options, phone, resendToken: resendToken);
  return switch (step) {
    SmsCodeSent(:final verificationId, resendToken: final nextResendToken) => OtpCodeNeeded(
        sent,
        session: FirebaseOtpSession(
          options: options,
          verificationId: verificationId,
          resendToken: nextResendToken,
        ),
      ),
    PhoneAutoVerified(:final idToken) => OtpAutoVerified(await verifyFirebaseIdToken(auth, gateway, phone, idToken)),
  };
}

/// The server's verify with a Firebase ID token; signs out of Firebase
/// whatever the answer — the app keeps no Firebase session, our JWT is the
/// session (SPEC §9.19 A).
Future<OtpVerifyResult> verifyFirebaseIdToken(
  AuthState auth,
  PhoneAuthGateway gateway,
  String phone,
  String idToken,
) async {
  try {
    return await auth.verifyFirebaseToken(phone: phone, idToken: idToken);
  } finally {
    await gateway.signOut();
  }
}

/// Where a verified number goes: a known customer is logged in (the root
/// swaps to Home underneath, so every pushed route is popped); a new number
/// continues to the signup screen ([replace]: instead of the current route).
void continueAfterVerify(NavigatorState nav, String phone, OtpVerifyResult result, {bool replace = false}) {
  switch (result) {
    case LoggedIn():
      nav.popUntil((r) => r.isFirst);
    case NeedsSignup(:final verificationToken):
      final route = MaterialPageRoute<void>(
        builder: (_) => SignupScreen(phone: phone, verificationToken: verificationToken),
      );
      if (replace) {
        nav.pushReplacement(route);
      } else {
        nav.push(route);
      }
  }
}
