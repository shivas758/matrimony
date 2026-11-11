import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// The Firebase client options the OTP send response carries when the
/// server's provider is `firebase` (SPEC §9.19 A) — the same project as push.
/// They are public; the APK has no google-services.json.
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

  /// `{api_key, app_id, messaging_sender_id, project_id}` → options; null
  /// unless every value is present and non-empty.
  static FirebaseClientOptions? tryParse(Object? json) {
    if (json is! Map) return null;
    String? str(String k) {
      final v = json[k];
      if (v == null) return null;
      final s = '$v'.trim();
      return s.isEmpty ? null : s;
    }

    final apiKey = str('api_key');
    final appId = str('app_id');
    final senderId = str('messaging_sender_id');
    final projectId = str('project_id');
    if (apiKey == null || appId == null || senderId == null || projectId == null) return null;
    return FirebaseClientOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: senderId,
      projectId: projectId,
    );
  }
}

/// What [PhoneAuthGateway.start] ended with.
sealed class PhoneVerificationStep {
  const PhoneVerificationStep();
}

/// Firebase sent the SMS — the user types the code (or Android reads it and
/// [PhoneAuthGateway.autoVerified] fires later).
final class SmsCodeSent extends PhoneVerificationStep {
  const SmsCodeSent({required this.verificationId, this.resendToken});

  final String verificationId;

  /// Firebase's `forceResendingToken` for "Resend code".
  final int? resendToken;
}

/// Android verified the number by itself (instant verification or SMS
/// auto-read) — no code to type.
final class PhoneAutoVerified extends PhoneVerificationStep {
  const PhoneAutoVerified({required this.idToken, this.phone});

  /// The Firebase ID token the server checks (`firebase_id_token`).
  final String idToken;

  /// The 10-digit number it verified, so a late event for an earlier
  /// number can be told apart.
  final String? phone;
}

/// A Firebase phone-auth error. [code] is Firebase's code, normalised to the
/// `kebab-case` form (`invalid-verification-code`, `too-many-requests`, …);
/// [message] is Firebase's raw text (never shown as is — the UI maps [code]
/// to plain words, see `phoneAuthMessage`).
class PhoneAuthFailure implements Exception {
  const PhoneAuthFailure(this.code, [this.message]);

  final String code;
  final String? message;

  /// `ERROR_INVALID_VERIFICATION_CODE` / `invalid-verification-code` → the latter.
  static String normaliseCode(String code) {
    var c = code.trim().toLowerCase();
    if (c.startsWith('error_')) c = c.substring(6);
    return c.replaceAll('_', '-');
  }

  factory PhoneAuthFailure.from(FirebaseException e) => PhoneAuthFailure(normaliseCode(e.code), e.message);

  @override
  String toString() => 'PhoneAuthFailure($code${message == null ? '' : ': $message'})';
}

/// Firebase phone authentication, behind an interface so screens can be
/// tested with a fake (SPEC §9.19 A). The app keeps no Firebase session: it
/// only needs the ID token for the server's verify call, then [signOut].
abstract class PhoneAuthGateway {
  /// Initialises Firebase with [options] (no-op when push already did — same
  /// project), then asks Firebase to verify `+91<phone10>`. Resolves with
  /// [SmsCodeSent] or [PhoneAutoVerified]; throws [PhoneAuthFailure].
  Future<PhoneVerificationStep> start(FirebaseClientOptions options, String phone10, {int? resendToken});

  /// Auto-verification that arrives AFTER [SmsCodeSent] (SMS auto-read).
  Stream<PhoneAutoVerified> get autoVerified;

  /// The typed code → a Firebase ID token. Throws [PhoneAuthFailure].
  Future<String> confirmCode(String verificationId, String smsCode);

  /// Drops the Firebase session; never throws.
  Future<void> signOut();
}

/// The real thing — `firebase_auth` on Android.
class FirebasePhoneAuthGateway implements PhoneAuthGateway {
  FirebasePhoneAuthGateway({this.startTimeout = const Duration(minutes: 3)});

  /// How long [start] waits for Firebase to answer at all (it may first show
  /// a reCAPTCHA page for APKs installed outside the Play Store).
  final Duration startTimeout;

  late final _auto = StreamController<PhoneAutoVerified>.broadcast(onListen: _replayHeld);

  /// An auto-verification that arrived while nobody listened (between
  /// "code sent" and the OTP screen subscribing) — handed to the next
  /// listener if it is still fresh.
  PhoneAutoVerified? _held;
  DateTime? _heldAt;

  @override
  Stream<PhoneAutoVerified> get autoVerified => _auto.stream;

  void _emitAuto(PhoneAutoVerified event) {
    if (_auto.hasListener) {
      _auto.add(event);
    } else {
      _held = event;
      _heldAt = DateTime.now();
    }
  }

  void _replayHeld() {
    final held = _held;
    final at = _heldAt;
    _held = null;
    _heldAt = null;
    if (held == null || at == null) return;
    if (DateTime.now().difference(at) > const Duration(minutes: 5)) return;
    scheduleMicrotask(() => _auto.add(held));
  }

  Future<void> _ensureInitialised(FirebaseClientOptions o) async {
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

  @override
  Future<PhoneVerificationStep> start(FirebaseClientOptions options, String phone10, {int? resendToken}) async {
    try {
      await _ensureInitialised(options);
    } on FirebaseException catch (e) {
      throw PhoneAuthFailure.from(e);
    } catch (e) {
      debugPrint('[otp] Firebase init failed: $e');
      throw PhoneAuthFailure('app-not-authorized', '$e');
    }

    final done = Completer<PhoneVerificationStep>();
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '+91$phone10',
        timeout: const Duration(seconds: 60),
        forceResendingToken: resendToken,
        verificationCompleted: (credential) async {
          try {
            final token = await _signIn(credential);
            final event = PhoneAutoVerified(idToken: token, phone: phone10);
            if (!done.isCompleted) {
              done.complete(event);
            } else {
              _emitAuto(event);
            }
          } on PhoneAuthFailure catch (e) {
            // Before the code was sent this is the answer; afterwards the
            // user can still type the code.
            if (!done.isCompleted) done.completeError(e);
          }
        },
        verificationFailed: (e) {
          if (!done.isCompleted) done.completeError(PhoneAuthFailure.from(e));
        },
        codeSent: (verificationId, token) {
          if (!done.isCompleted) {
            done.complete(SmsCodeSent(verificationId: verificationId, resendToken: token));
          }
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } on FirebaseException catch (e) {
      if (!done.isCompleted) done.completeError(PhoneAuthFailure.from(e));
    } catch (e) {
      if (!done.isCompleted) done.completeError(PhoneAuthFailure('unknown', '$e'));
    }
    return done.future.timeout(
      startTimeout,
      onTimeout: () => throw const PhoneAuthFailure('timeout'),
    );
  }

  @override
  Future<String> confirmCode(String verificationId, String smsCode) =>
      _signIn(PhoneAuthProvider.credential(verificationId: verificationId, smsCode: smsCode));

  Future<String> _signIn(AuthCredential credential) async {
    try {
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final token = await result.user?.getIdToken(true);
      if (token == null || token.isEmpty) throw const PhoneAuthFailure('no-id-token');
      return token;
    } on PhoneAuthFailure {
      rethrow;
    } on FirebaseException catch (e) {
      throw PhoneAuthFailure.from(e);
    } catch (e) {
      throw PhoneAuthFailure('unknown', '$e');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      if (Firebase.apps.isEmpty) return;
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('[otp] Firebase sign-out failed: $e');
    }
  }
}
