import '../models/payment.dart';
import 'api_client.dart';

/// The ₹ registration fee checkout (SPEC §9.12), kept behind one small class
/// so Razorpay Checkout can be dropped in later without touching screens.
///
/// Today only the server's `mock` provider can be completed in the app:
/// nothing is charged, and [confirm] with `simulateFailure` records a failed
/// attempt to exercise the error path. For `razorpay` a later app version
/// must open Razorpay Checkout with [Payment.orderId] / [Payment.keyId] and
/// pass its `razorpay_payment_id` + `razorpay_signature` to [confirm].
class PaymentService {
  PaymentService(this._api);

  final ApiClient _api;

  /// Providers this build can complete in-app.
  static bool supportsInApp(String provider) => provider == 'mock';

  /// POST /customer/my-profiles/:id/payment → 201 {payment} — a new order
  /// every time (retries after a failure start fresh). 409 `already_paid`.
  Future<Payment> createOrder(int profileId) async {
    final json = await _api.post('/customer/my-profiles/$profileId/payment');
    return Payment.fromJson(json['payment'] as Map<String, dynamic>);
  }

  /// POST /customer/payments/:id/confirm → {payment, profile, customer}.
  /// Mock: `{}` succeeds, `{outcome: 'failure'}` fails. A failure answers
  /// 200 with `payment.status == 'failed'`.
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
    if (!supportsInApp(order.provider)) {
      throw ApiException(
        'payment_provider_unsupported',
        'Online payment is coming soon — contact your agent',
      );
    }
    return confirm(order, simulateFailure: simulateFailure);
  }
}
