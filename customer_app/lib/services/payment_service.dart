import 'dart:ui' show Color;

import '../config.dart';
import '../models/payment.dart';
import '../models/publish.dart';
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
/// - `upi` (SPEC §9.20 B): the profile's open UPI payment ([openUpi]) — pay
///   to the UPI ID shown, then [submitUtr]; an admin verifies it. Never
///   [confirm]ed.
///
/// The Play build ([playStore], SPEC §9.20 G) offers neither UPI nor
/// Razorpay — only Google Play Billing is allowed there; `mock` stays for dev.
class PaymentService {
  PaymentService(this._api, {this.playStore = kPlayStore});

  final ApiClient _api;

  /// This is the Google Play build — defaults to [kPlayStore]; tests flip it.
  final bool playStore;

  /// Providers a build can complete in-app: mock always; razorpay and upi
  /// only outside the Play build.
  static bool supportsInApp(String provider, {bool playStore = kPlayStore}) {
    if (provider == 'mock') return true;
    if (playStore) return false;
    return provider == 'razorpay' || provider == 'upi';
  }

  /// [supportsInApp] for this build.
  bool canPayInApp(String provider) => supportsInApp(provider, playStore: playStore);

  /// Whether screens may offer *Pay* (and the UPI states) for [provider]:
  /// always outside the Play build (an unknown provider leads to "coming
  /// soon" as before); in the Play build only for a provider it can pay.
  bool offersPayment(String provider) => !playStore || canPayInApp(provider);

  /// A UPI reference (UTR) is exactly 12 digits.
  static final _utrPattern = RegExp(r'^\d{12}$');

  /// [text] without spaces / dashes (people copy "1234 5678 9012").
  static String normalizeUtr(String text) => text.replaceAll(RegExp(r'[\s-]'), '');

  static bool isValidUtr(String text) => _utrPattern.hasMatch(normalizeUtr(text));

  /// POST /customer/my-profiles/:id/payment → 201 {payment} — a new order
  /// every time (retries after a failure start fresh). 409 `already_paid`.
  /// UPI reuses the profile's open payment (`created` / `failed`) and answers
  /// 409 `payment_under_review` while one is `submitted`.
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

  /// UPI, step 1 (SPEC §9.20 B): the profile's open UPI payment with who to
  /// pay and the `upi://pay` link. 409 `payment_under_review` while a UTR
  /// is being verified, 409 `already_paid`, 503 `payment_provider_error`
  /// when the server has no UPI ID set up.
  Future<Payment> openUpi(int profileId) async {
    final order = await createOrder(profileId);
    if (!order.isUpi) throw _wrongProvider(order.provider);
    if (order.upi == null && !order.isSubmitted && !order.isPaid) {
      throw ApiException('payment_provider_error', 'UPI payments are not set up yet', status: 503);
    }
    return order;
  }

  /// POST /customer/my-profiles/:id/gift-code {code} → {profile, customer}
  /// (SPEC §9.23 B): an agent's free gift code instead of the fee. It also
  /// links me to that agent if I have none (or am pending / rejected) and
  /// approves me — the profile goes live at once. Sent as typed (trimmed);
  /// the server ignores case, spaces, dashes and the `WB` prefix. Works in
  /// the Play build too (no money involved). Errors: 404
  /// `gift_code_not_found`, 409 `gift_code_used` / `already_paid` /
  /// `payment_under_review` / `gift_code_other_agent`, 400
  /// `agent_not_active` / `agent_has_no_communities`, 403
  /// `account_suspended`, 429 `too_many_attempts`.
  Future<GiftCodeResult> redeemGiftCode(int profileId, String code) async {
    final json = await _api.post('/customer/my-profiles/$profileId/gift-code', body: {'code': code.trim()});
    return GiftCodeResult.fromJson(json);
  }

  /// UPI, step 2: POST /customer/payments/:id/submit {utr} → `submitted` →
  /// {payment, profile, customer}. 409 `utr_already_used`, 409
  /// `wrong_status`, 400 `validation_failed`.
  Future<PaymentResult> submitUtr(int paymentId, String utr) async {
    final json = await _api.post('/customer/payments/$paymentId/submit', body: {'utr': normalizeUtr(utr)});
    return PaymentResult.fromJson(json);
  }

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
  ApiException _wrongProvider(String provider) => canPayInApp(provider)
      ? ApiException('payment_provider_changed', 'The payment method has just changed. Please try again.')
      : ApiException('payment_provider_unsupported', 'Online payment is coming soon — contact your agent');
}
