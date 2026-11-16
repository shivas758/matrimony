import 'customer.dart';
import 'profile.dart';

/// A registration-fee checkout (SPEC §9.12) — `paymentPublic()` on the
/// server: {id, profile_id, status, amount_paise, amount_inr, currency,
/// provider, order_id, key_id, created_at, paid_at}; a UPI payment
/// (SPEC §9.20) adds {utr, submitted_at, reject_reason, upi}.
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
    this.utr,
    this.submittedAt,
    this.rejectReason,
    this.upi,
  });

  final int id;
  final int? profileId;

  /// 'created' | 'paid' | 'failed'; UPI also 'submitted' (the payer entered
  /// the UTR, an admin has to verify it) — SPEC §9.20 A.
  final String status;
  final num amountInr;
  final int? amountPaise;
  final String currency;

  /// 'mock' | 'razorpay' | 'upi' | 'waived'
  final String provider;
  final String? orderId;

  /// Razorpay Checkout's public key id; null for mock.
  final String? keyId;
  final DateTime? createdAt;
  final DateTime? paidAt;

  /// UPI: the 12-digit UPI reference the payer entered; null until then.
  final String? utr;
  final DateTime? submittedAt;

  /// UPI: why an admin did not verify it (status `failed`).
  final String? rejectReason;

  /// UPI: who to pay and the `upi://pay` link (SPEC §9.20 A); null for other
  /// providers.
  final UpiDetails? upi;

  bool get isPaid => status == 'paid';
  bool get isFailed => status == 'failed';
  bool get isMock => provider == 'mock';
  bool get isUpi => provider == 'upi';

  /// UPI: the UTR is in, waiting for an admin.
  bool get isSubmitted => status == 'submitted';

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
      utr: _text(j['utr']),
      submittedAt: _date(j['submitted_at']),
      rejectReason: _text(j['reject_reason']),
      upi: UpiDetails.tryParse(j['upi']),
    );
  }

  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

  /// A non-blank string, trimmed; null otherwise.
  static String? _text(dynamic v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
}

/// The `upi` block of a UPI payment (SPEC §9.20 A): pay [amountInr] to [vpa]
/// ([name]) with [note]; [uri] is the `upi://pay?…` link — opened with a UPI
/// app and shown as the QR code. [reference] = `WB<payment id>`.
class UpiDetails {
  const UpiDetails({
    required this.vpa,
    required this.uri,
    this.name,
    this.amountInr,
    this.note,
    this.reference,
  });

  /// The payee's UPI ID, e.g. `wedbook@ybl`.
  final String vpa;
  final String? name;
  final num? amountInr;
  final String? note;
  final String? reference;
  final String uri;

  /// Null unless it is a map with a UPI ID and a link — without those
  /// nobody can pay.
  static UpiDetails? tryParse(dynamic j) {
    if (j is! Map) return null;
    final vpa = Payment._text(j['vpa']);
    final uri = Payment._text(j['uri']);
    if (vpa == null || uri == null) return null;
    final amount = j['amount_inr'];
    return UpiDetails(
      vpa: vpa,
      uri: uri,
      name: Payment._text(j['name']),
      amountInr: amount is num ? amount : (amount is String ? num.tryParse(amount) : null),
      note: Payment._text(j['note']),
      reference: Payment._text(j['reference']),
    );
  }
}

/// The latest UPI payment of one of MY unpaid profiles (SPEC §9.20 B) —
/// `payment: {id, status, utr, submitted_at, reject_reason} | null` on my own
/// profile rows. Tells My profile / Get started whether the fee is being
/// verified or was not verified.
class ProfilePayment {
  const ProfilePayment({required this.id, required this.status, this.utr, this.submittedAt, this.rejectReason});

  final int id;

  /// 'created' | 'submitted' | 'paid' | 'failed'
  final String status;
  final String? utr;
  final DateTime? submittedAt;
  final String? rejectReason;

  /// The UTR is in — an admin is checking it.
  bool get isSubmitted => status == 'submitted';

  /// An admin did not verify it ([rejectReason] says why).
  bool get isRejected => status == 'failed';

  static ProfilePayment? tryParse(dynamic j) {
    if (j is! Map || j['id'] is! num) return null;
    return ProfilePayment(
      id: (j['id'] as num).toInt(),
      status: '${j['status'] ?? 'created'}',
      utr: Payment._text(j['utr']),
      submittedAt: Payment._date(j['submitted_at']),
      rejectReason: Payment._text(j['reject_reason']),
    );
  }
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
