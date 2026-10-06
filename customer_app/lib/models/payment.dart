import 'customer.dart';
import 'profile.dart';

/// A registration-fee checkout (SPEC §9.12) — `paymentPublic()` on the
/// server: {id, profile_id, status, amount_paise, amount_inr, currency,
/// provider, order_id, key_id, created_at, paid_at}.
class Payment {
  const Payment({
    required this.id,
    required this.status,
    required this.amountInr,
    required this.provider,
    this.profileId,
    this.amountPaise,
    this.currency = 'INR',
    this.orderId,
    this.keyId,
    this.createdAt,
    this.paidAt,
  });

  final int id;
  final int? profileId;

  /// 'created' | 'paid' | 'failed'
  final String status;
  final num amountInr;
  final int? amountPaise;
  final String currency;

  /// 'mock' | 'razorpay' | 'waived'
  final String provider;
  final String? orderId;

  /// Razorpay Checkout's public key id; null for mock.
  final String? keyId;
  final DateTime? createdAt;
  final DateTime? paidAt;

  bool get isPaid => status == 'paid';
  bool get isFailed => status == 'failed';
  bool get isMock => provider == 'mock';

  factory Payment.fromJson(Map<String, dynamic> j) {
    final paise = (j['amount_paise'] as num?)?.toInt();
    return Payment(
      id: (j['id'] as num).toInt(),
      profileId: (j['profile_id'] as num?)?.toInt(),
      status: '${j['status'] ?? 'created'}',
      amountInr: (j['amount_inr'] as num?) ?? (paise == null ? 0 : paise / 100),
      amountPaise: paise,
      currency: '${j['currency'] ?? 'INR'}',
      provider: '${j['provider'] ?? 'mock'}',
      orderId: j['order_id'] as String?,
      keyId: j['key_id'] as String?,
      createdAt: _date(j['created_at']),
      paidAt: _date(j['paid_at']),
    );
  }

  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
}

/// POST /customer/payments/:id/confirm → {payment, profile, customer}.
class PaymentResult {
  const PaymentResult({required this.payment, this.profile, this.customer});

  final Payment payment;

  /// The profile's own view after the attempt (its new `visibility`).
  final Profile? profile;

  /// The refreshed "me" (access / unlock may have changed).
  final Customer? customer;

  factory PaymentResult.fromJson(Map<String, dynamic> j) => PaymentResult(
        payment: Payment.fromJson(j['payment'] as Map<String, dynamic>),
        profile: j['profile'] == null ? null : Profile.fromJson(j['profile'] as Map<String, dynamic>),
        customer: j['customer'] == null ? null : Customer.fromJson(j['customer'] as Map<String, dynamic>),
      );
}
