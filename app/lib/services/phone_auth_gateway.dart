import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../ui/strings.dart';

/// The public Firebase client options the server hands over with a
/// `provider: 'firebase'` OTP send response (SPEC §9.19 A). The app ships
/// without google-services.json — exactly like push (§9.16).
class FirebaseClientOptions {
  const FirebaseClientOptions({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
  });

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;

  /// `{api_key, app_id, messaging_sender_id, project_id}` — null when the
  /// value is not a map or any option is missing / empty.
  static FirebaseClientOptions? fromJson(Object? j) {
    if (j is! Map) return null;
    String? s(Object? v) {
      final t = v == null ? '' : '$v'.trim();
      return t.isEmpty ? null : t;
    }

    final apiKey = s(j['api_key']);
    final appId = s(j['app_id']);
    final senderId = s(j['messaging_sender_id']);
    final projectId = s(j['project_id']);
    if (apiKey == null || appId == null || senderId == null || projectId == null) return null;
    return FirebaseClientOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
    );
  }
}

/// What [PhoneAuthGateway.start] ends with.
sealed class PhoneVerificationStep {
  const PhoneVerificationStep();
}

/// Firebase sent the SMS; the user types the code (or Android reads it and
/// [PhoneAuthGateway.autoVerifiedIdTokens] fires later).
class PhoneCodeSent extends PhoneVerificationStep {
  const PhoneCodeSent(this.verificationId, this.resendToken);

  final String verificationId;

  /// Firebase's `forceResendingToken`, passed back on Resend.
  final int? resendToken;
}

/// Android verified the number by itself (instant verification) before any
/// code was sent — [idToken] is the Firebase ID token for the verify call.
class PhoneAutoVerified extends PhoneVerificationStep {
  const PhoneAutoVerified(this.idToken);

  final String idToken;
}

/// A Firebase phone-auth error, already worded for the user.
class PhoneAuthFailure implements Exception {
  const PhoneAuthFailure(this.code, this.message);

  /// Firebase's error code (`invalid-verification-code`, …), normalised.
  final String code;

  /// Plain English, ready for the error banner.
  final String message;

  /// The code is no longer usable — the user needs a new one.
  bool get needsNewCode =>
      code == 'session-expired' || code == 'code-expired' || code == 'invalid-verification-id';

  factory PhoneAuthFailure.from(String code, [String? message]) {
    final c = normalisePhoneAuthCode(code);
    return PhoneAuthFailure(c, phoneAuthMessage(c, message));
  }

  @override
  String toString() => message;
}

/// `ERROR_INVALID_PHONE_NUMBER` / `invalid_phone_number` → `invalid-phone-number`.
String normalisePhoneAuthCode(String code) =>
    code.trim().toLowerCase().replaceFirst(RegExp('^error[-_]'), '').replaceAll('_', '-');

/// Firebase phone-auth error → the message the agent reads (SPEC §9.19 A).
String phoneAuthMessage(String code, [String? message]) {
  if ((message ?? '').toUpperCase().contains('BILLING_NOT_ENABLED')) return S.phoneAuthNotSetUp;
  switch (normalisePhoneAuthCode(code)) {
    case 'invalid-verification-code':
      return S.phoneAuthWrongCode;
    case 'session-expired':
    case 'code-expired':
    case 'invalid-verification-id':
      return S.phoneAuthCodeExpired;
    case 'too-many-requests':
      return S.phoneAuthTooManyAttempts;
    case 'quota-exceeded':
      return S.phoneAuthQuotaExceeded;
    case 'invalid-phone-number':
      return S.phoneAuthInvalidNumber;
    case 'network-request-failed':
      return S.phoneAuthNetwork;
    case 'app-not-authorized':
    case 'missing-client-identifier':
    case 'invalid-app-credential':
    case 'operation-not-allowed':
      return S.phoneAuthNotSetUp;
    default:
      return S.phoneAuthFailed;
  }
}

/// The Firebase phone-auth calls the signup screen needs — a seam so widget
/// tests run without Firebase ([FirebasePhoneAuthGateway] is the real one).
abstract class PhoneAuthGateway {
  /// Initialises Firebase from [options] (no-op when push already did),
  /// then asks Firebase to verify `+91<phone10>`. Throws [PhoneAuthFailure].
  Future<PhoneVerificationStep> start(
    FirebaseClientOptions options,
    String phone10, {
    int? resendToken,
  });

  /// ID tokens from an automatic verification (SMS auto-read) that arrives
  /// AFTER [start] already answered [PhoneCodeSent].
  Stream<String> get autoVerifiedIdTokens;

  /// Signs in with the typed [smsCode] → the Firebase ID token.
  /// Throws [PhoneAuthFailure].
  Future<String> confirmCode(String verificationId, String smsCode);

  /// Drops the Firebase session — the app keeps none (our JWT is the
  /// session). Never throws.
  Future<void> signOut();
}

class FirebasePhoneAuthGateway implements PhoneAuthGateway {
  final _autoVerified = StreamController<String>.broadcast();

  /// Only the latest [start] may report an automatic verification.
  int _attempt = 0;

  @override
  Stream<String> get autoVerifiedIdTokens => _autoVerified.stream;

  static Future<void> _ensureInitialized(FirebaseClientOptions o) async {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: o.apiKey,
        appId: o.appId,
        messagingSenderId: o.messagingSenderId,
        projectId: o.projectId,
      ),
    );
  }

  static PhoneAuthFailure _failure(Object e) {
    if (e is PhoneAuthFailure) return e;
    if (e is FirebaseException) return PhoneAuthFailure.from(e.code, e.message);
    debugPrint('phone auth: $e');
    return PhoneAuthFailure.from('unknown', '$e');
  }

  static Future<String> _signIn(AuthCredential credential) async {
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    final token = await result.user?.getIdToken(true);
    if (token == null || token.isEmpty) throw PhoneAuthFailure.from('no-id-token');
    return token;
  }

  @override
  Future<PhoneVerificationStep> start(
    FirebaseClientOptions options,
    String phone10, {
    int? resendToken,
  }) async {
    final attempt = ++_attempt;
    try {
      await _ensureInitialized(options);
    } catch (e) {
      debugPrint('firebase init failed: $e');
      throw const PhoneAuthFailure('not-configured', S.phoneAuthNotSetUp);
    }

    final step = Completer<PhoneVerificationStep>();
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '+91$phone10',
        timeout: const Duration(seconds: 60),
        forceResendingToken: resendToken,
        verificationCompleted: (credential) async {
          try {
            final token = await _signIn(credential);
            if (!step.isCompleted) {
              step.complete(PhoneAutoVerified(token));
            } else if (attempt == _attempt) {
              _autoVerified.add(token);
            }
          } catch (e) {
            // After codeSent the user can still type the code.
            if (!step.isCompleted) step.completeError(_failure(e));
          }
        },
        verificationFailed: (e) {
          if (!step.isCompleted) {
            step.completeError(_failure(e));
          } else {
            debugPrint('phone verification failed after code sent: ${e.code} ${e.message}');
          }
        },
        codeSent: (verificationId, token) {
          if (!step.isCompleted) step.complete(PhoneCodeSent(verificationId, token));
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      if (!step.isCompleted) step.completeError(_failure(e));
    }
    // Firebase always answers (code sent / verified / failed), the reCAPTCHA
    // fallback page included — but never leave the screen busy for good.
    return step.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => throw PhoneAuthFailure.from('timeout'),
    );
  }

  @override
  Future<String> confirmCode(String verificationId, String smsCode) async {
    try {
      return await _signIn(
        PhoneAuthProvider.credential(verificationId: verificationId, smsCode: smsCode),
      );
    } catch (e) {
      throw _failure(e);
    }
  }

  @override
  Future<void> signOut() async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('firebase sign-out failed: $e');
    }
  }
}
