import 'dart:ui' show Color;

import '../models/payment.dart';
import 'api_client.dart';
import 'razorpay_gateway.dart';

/// A Razorpay attempt: the order the server created and how Checkout ended.
class RazorpayAttempt {
  const RazorpayAttempt(this.order, this.outcome);

  final Payment order;
  final RazorpayOutcome outcome;
}

/// The ₹ registration fee checkout (SPEC §9.12, §9.19 B), kept behind one
/// small class so screens never talk to a payment provider directly.
///
/// - `mock`: nothing is charged, and [confirm] with `simulateFailure`
///   records a failed attempt to exercise the error path ([payMock]).
/// - `razorpay`: a fresh order → Razorpay Checkout ([openRazorpay]) → the
///   checkout's payment id + signature to [confirmRazorpay].
class PaymentService {
  PaymentService(this._api);

  final ApiClient _api;

  /// Providers this build can complete in-app.
  static bool supportsInApp(String provider) => provider == 'mock' || provider == 'razorpay';

  /// POST /customer/my-profiles/:id/payment → 201 {payment} — a new order
  /// every time (retries after a failure start fresh). 409 `already_paid`.
  Future<Payment> createOrder(int profileId) async {
    final json = await _api.post('/customer/my-profiles/$profileId/payment');
    return Payment.fromJson(json['payment'] as Map<String, dynamic>);
  }

  /// POST /customer/payments/:id/confirm → {payment, profile, customer}.
  /// Mock: `{}` succeeds, `{outcome: 'failure'}` fails. A failure answers
  /// 200 with `payment.status == 'failed'`. Razorpay: the checkout's
  /// payment id + signature; `400 payment_verification_failed` when the
  /// signature does not match.
  Future<PaymentResult> confirm(
    Payment payment, {
    bool simulateFailure = false,
    String? providerPaymentId,
    String? signature,
  }) async {
    final json = await _api.post('/customer/payments/${payment.id}/confirm', body: {
      if (simulateFailure) 'outcome': 'failure',
      'provider_payment_id': ?providerPaymentId,
      'signature': ?signature,
    });
    return PaymentResult.fromJson(json);
  }

  /// The whole mock checkout: a fresh order, then confirm it.
  Future<PaymentResult> payMock(int profileId, {bool simulateFailure = false}) async {
    final order = await createOrder(profileId);
    if (!order.isMock) throw _wrongProvider(order.provider);
    return confirm(order, simulateFailure: simulateFailure);
  }

  /// Razorpay, step 1: a fresh order, then Checkout (SPEC §9.19 B). The
  /// server must be confirming with Razorpay too — otherwise the order is
  /// not opened. Cancel / failure need no server call; trying again starts a
  /// new order.
  Future<RazorpayAttempt> openRazorpay(
    int profileId,
    RazorpayGateway gateway, {
    String? phone,
    String? themeColor,
  }) async {
    final order = await createOrder(profileId);
    if (order.provider != 'razorpay') throw _wrongProvider(order.provider);
    if ((order.keyId ?? '').isEmpty || (order.orderId ?? '').isEmpty) {
      return RazorpayAttempt(order, const RazorpayFailed('order without key_id / order_id'));
    }
    final outcome = await gateway.open(razorpayOptions(order, phone: phone, themeColor: themeColor));
    return RazorpayAttempt(order, outcome);
  }

  /// Razorpay, step 2: the server checks the signature and settles the
  /// payment → {payment, profile, customer}.
  Future<PaymentResult> confirmRazorpay(Payment order, RazorpaySuccess success) =>
      confirm(order, providerPaymentId: success.paymentId, signature: success.signature);

  /// Razorpay Checkout's options for [order] (SPEC §9.19 B).
  static Map<String, dynamic> razorpayOptions(Payment order, {String? phone, String? themeColor}) {
    final paise = order.amountPaise ?? (order.amountInr * 100).round();
    final contact = (phone ?? '').trim();
    return {
      'key': order.keyId,
      'order_id': order.orderId,
      'amount': paise,
      'currency': 'INR',
      'name': 'Wedbook Matrimony',
      'description': 'Profile registration fee',
      if (contact.isNotEmpty) 'prefill': {'contact': contact.startsWith('+') ? contact : '+91$contact'},
      if (themeColor != null) 'theme': {'color': themeColor},
    };
  }

  /// `#RRGGBB` for Razorpay's `theme.color`.
  static String hexColor(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// The order came back for another provider than the screen expected (the
  /// server switched): a provider this app handles → "try again" (the screen
  /// re-reads the account); anything else → "coming soon".
  static ApiException _wrongProvider(String provider) => supportsInApp(provider)
      ? ApiException('payment_provider_changed', 'The payment method has just changed. Please try again.')
      : ApiException('payment_provider_unsupported', 'Online payment is coming soon — contact your agent');
}
