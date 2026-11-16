// Direct UPI payments verified by an admin (SPEC §9.20).

/// The UPI block on every UPI payment: who to pay, how much, and the
/// `upi://pay?…` link that opens any UPI app (also shown as a QR code).
class UpiInfo {
  const UpiInfo({
    required this.vpa,
    required this.name,
    required this.amountInr,
    required this.uri,
    this.note,
    this.reference,
  });

  final String vpa;
  final String name;
  final int amountInr;
  final String uri;

  /// "Wedbook WB12" — the remark the payer's app puts on the transfer.
  final String? note;

  /// "WB12" — the payment's reference.
  final String? reference;

  static UpiInfo? fromJsonOrNull(Object? j) =>
      j is Map<String, dynamic> && j['uri'] != null ? UpiInfo.fromJson(j) : null;

  factory UpiInfo.fromJson(Map<String, dynamic> j) => UpiInfo(
    vpa: '${j['vpa'] ?? ''}',
    name: '${j['name'] ?? ''}',
    amountInr: _int(j['amount_inr']),
    uri: '${j['uri']}',
    note: j['note'] as String?,
    reference: j['reference'] as String?,
  );
}

/// Payment statuses (SPEC §9.20 A): `created` → `submitted` (the payer
/// entered the UTR) → `paid` (an admin verified it) or `failed` (rejected —
/// the payer may submit a corrected UTR on the same row). `refund_due`: the
/// admin rejected the community request after the money arrived.
class PaymentStatus {
  static const created = 'created';
  static const submitted = 'submitted';
  static const paid = 'paid';
  static const failed = 'failed';
  static const refundDue = 'refund_due';
}

/// The payer's own UPI payment (an agent's extra-community fee).
class UpiPayment {
  const UpiPayment({
    required this.id,
    required this.status,
    this.utr,
    this.submittedAt,
    this.rejectReason,
    this.upi,
  });

  final int id;
  final String status;
  final String? utr;
  final DateTime? submittedAt;
  final String? rejectReason;
  final UpiInfo? upi;

  bool get isCreated => status == PaymentStatus.created;
  bool get isSubmitted => status == PaymentStatus.submitted;
  bool get isPaid => status == PaymentStatus.paid;
  bool get isFailed => status == PaymentStatus.failed;
  bool get isRefundDue => status == PaymentStatus.refundDue;

  /// A UTR can be (re)submitted only from these (else `409 wrong_status`).
  bool get canSubmit => isCreated || isFailed;

  static UpiPayment? fromJsonOrNull(Object? j) =>
      j is Map<String, dynamic> && j['id'] != null ? UpiPayment.fromJson(j) : null;

  factory UpiPayment.fromJson(Map<String, dynamic> j) => UpiPayment(
    id: _int(j['id']),
    status: '${j['status']}',
    utr: _str(j['utr']),
    submittedAt: _date(j['submitted_at']),
    rejectReason: _str(j['reject_reason']),
    upi: UpiInfo.fromJsonOrNull(j['upi']),
  );
}

/// What a payment is for.
class PaymentPurpose {
  static const profileRegistration = 'profile_registration';
  static const extraCommunity = 'extra_community';
}

/// One row of the admin's "Payments to verify" list (SPEC §9.20 D).
class AdminPayment {
  const AdminPayment({
    required this.id,
    required this.purpose,
    required this.status,
    required this.amountInr,
    this.utr,
    this.reference,
    this.submittedAt,
    this.verifiedAt,
    this.rejectReason,
    this.customer,
    this.profile,
    this.agent,
    this.community,
  });

  final int id;
  final String purpose;
  final String status;
  final int amountInr;
  final String? utr;
  final String? reference;
  final DateTime? submittedAt;
  final DateTime? verifiedAt;
  final String? rejectReason;
  final PaymentCustomer? customer;
  final PaymentProfile? profile;
  final PaymentAgent? agent;
  final PaymentCommunity? community;

  bool get isSubmitted => status == PaymentStatus.submitted;
  bool get isPaid => status == PaymentStatus.paid;
  bool get isFailed => status == PaymentStatus.failed;
  bool get isExtraCommunity => purpose == PaymentPurpose.extraCommunity;

  factory AdminPayment.fromJson(Map<String, dynamic> j) => AdminPayment(
    id: _int(j['id']),
    purpose: '${j['purpose']}',
    status: '${j['status']}',
    amountInr: _int(j['amount_inr']),
    utr: _str(j['utr']),
    reference: _str(j['reference']),
    submittedAt: _date(j['submitted_at']),
    verifiedAt: _date(j['verified_at']),
    rejectReason: _str(j['reject_reason']),
    customer: _map(j['customer'], PaymentCustomer.fromJson),
    profile: _map(j['profile'], PaymentProfile.fromJson),
    agent: _map(j['agent'], PaymentAgent.fromJson),
    community: _map(j['community'], PaymentCommunity.fromJson),
  );
}

class PaymentCustomer {
  const PaymentCustomer({required this.id, required this.fullName, this.phone});
  final int id;
  final String fullName;
  final String? phone;

  factory PaymentCustomer.fromJson(Map<String, dynamic> j) => PaymentCustomer(
    id: _int(j['id']),
    fullName: '${j['full_name'] ?? ''}',
    phone: _str(j['phone']),
  );
}

class PaymentProfile {
  const PaymentProfile({required this.id, required this.fullName, this.profileCode});
  final int id;
  final String fullName;

  /// The permanent profile ID — admins may see it (SPEC §9.18 C).
  final String? profileCode;

  factory PaymentProfile.fromJson(Map<String, dynamic> j) => PaymentProfile(
    id: _int(j['id']),
    fullName: '${j['full_name'] ?? ''}',
    profileCode: _str(j['profile_code']),
  );
}

class PaymentAgent {
  const PaymentAgent({required this.id, required this.fullName, this.phone, this.agentCode});
  final int id;
  final String fullName;
  final String? phone;
  final String? agentCode;

  factory PaymentAgent.fromJson(Map<String, dynamic> j) => PaymentAgent(
    id: _int(j['id']),
    fullName: '${j['full_name'] ?? ''}',
    phone: _str(j['phone']),
    agentCode: _str(j['agent_code']),
  );
}

class PaymentCommunity {
  const PaymentCommunity({required this.id, required this.name});
  final int id;
  final String name;

  factory PaymentCommunity.fromJson(Map<String, dynamic> j) =>
      PaymentCommunity(id: _int(j['id']), name: '${j['name'] ?? ''}');
}

int _int(Object? v) => v is num ? v.toInt() : num.tryParse('${v ?? ''}')?.toInt() ?? 0;

String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

T? _map<T>(Object? v, T Function(Map<String, dynamic>) parse) =>
    v is Map<String, dynamic> ? parse(v) : null;
