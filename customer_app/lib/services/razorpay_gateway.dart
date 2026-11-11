import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// How Razorpay Checkout ended (SPEC §9.19 B).
sealed class RazorpayOutcome {
  const RazorpayOutcome();
}

/// Paid in Checkout — the server still has to confirm it (signature check).
final class RazorpaySuccess extends RazorpayOutcome {
  const RazorpaySuccess({required this.paymentId, required this.signature, this.orderId});

  /// `razorpay_payment_id`
  final String paymentId;

  /// `razorpay_signature`
  final String signature;

  /// `razorpay_order_id`
  final String? orderId;
}

/// The customer closed Checkout.
final class RazorpayCancelled extends RazorpayOutcome {
  const RazorpayCancelled();
}

/// Checkout reported an error (bank declined, network, bad options …).
/// [message] is Razorpay's own text, for logs only.
final class RazorpayFailed extends RazorpayOutcome {
  const RazorpayFailed([this.message]);

  final String? message;
}

/// Razorpay Checkout behind an interface so the checkout screen can be
/// tested with a fake.
abstract class RazorpayGateway {
  /// Opens Checkout with [options] (`key`, `order_id`, `amount`, …) and
  /// resolves once it closes. Never throws.
  Future<RazorpayOutcome> open(Map<String, dynamic> options);
}

/// The real thing — `razorpay_flutter` (Android CheckoutActivity). A fresh
/// [Razorpay] per checkout, cleared when it ends.
class RazorpayCheckoutGateway implements RazorpayGateway {
  RazorpayCheckoutGateway({this.armDelay = const Duration(milliseconds: 300)});

  /// Registering listeners makes the plugin `resync`: an answer of an
  /// earlier checkout that never reached Dart (the activity was recreated)
  /// comes back right away. Answers within this delay are not ours.
  final Duration armDelay;

  @override
  Future<RazorpayOutcome> open(Map<String, dynamic> options) async {
    final done = Completer<RazorpayOutcome>();
    var armed = false;
    void finish(RazorpayOutcome outcome) {
      if (armed && !done.isCompleted) done.complete(outcome);
    }

    // `open` and `resync` are fire-and-forget async calls inside the plugin:
    // the guarded zones turn a platform error there into a failed checkout
    // instead of an endless spinner.
    void onZoneError(Object error, StackTrace stack) {
      debugPrint('[razorpay] $error');
      finish(RazorpayFailed('$error'));
    }

    final expectedOrderId = options['order_id'];
    Razorpay? razorpay;
    runZonedGuarded(() {
      final r = razorpay = Razorpay();
      r.on(Razorpay.EVENT_PAYMENT_SUCCESS, (dynamic s) {
        if (s is! PaymentSuccessResponse) return finish(const RazorpayFailed('unexpected success payload'));
        // A late answer for another order is not ours.
        if (s.orderId != null && expectedOrderId != null && s.orderId != expectedOrderId) return;
        final paymentId = s.paymentId;
        final signature = s.signature;
        if (paymentId == null || paymentId.isEmpty || signature == null || signature.isEmpty) {
          return finish(const RazorpayFailed('success without payment id or signature'));
        }
        finish(RazorpaySuccess(paymentId: paymentId, signature: signature, orderId: s.orderId));
      });
      r.on(Razorpay.EVENT_PAYMENT_ERROR, (dynamic f) {
        if (f is PaymentFailureResponse && f.code == Razorpay.PAYMENT_CANCELLED) {
          return finish(const RazorpayCancelled());
        }
        finish(RazorpayFailed(f is PaymentFailureResponse ? '${f.code}: ${f.message}' : null));
      });
      // Only offered when external wallets are configured (they are not).
      r.on(Razorpay.EVENT_EXTERNAL_WALLET, (dynamic w) {
        finish(RazorpayFailed(w is ExternalWalletResponse ? 'external wallet ${w.walletName}' : 'external wallet'));
      });
    }, onZoneError);

    await Future<void>.delayed(armDelay);
    armed = true;
    final r = razorpay;
    if (r == null) return const RazorpayFailed('Razorpay unavailable');
    runZonedGuarded(() => r.open(options), onZoneError);

    try {
      return await done.future;
    } finally {
      try {
        r.clear();
      } catch (_) {}
    }
  }
}
