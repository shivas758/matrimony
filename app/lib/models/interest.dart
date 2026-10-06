import 'customer.dart';

/// The customer behind an interest. `phone` is present only for the
/// customer's own agent or an admin (SPEC §9.4).
class InterestCustomer {
  const InterestCustomer({
    required this.id,
    required this.fullName,
    this.phone,
    this.agentId,
  });

  final int id;
  final String fullName;
  final String? phone;
  final int? agentId;

  factory InterestCustomer.fromJson(Map<String, dynamic> j) => InterestCustomer(
        id: (j['id'] as num?)?.toInt() ?? 0,
        fullName: '${j['full_name'] ?? ''}',
        phone: j['phone'] as String?,
        agentId: (j['agent_id'] as num?)?.toInt(),
      );
}

/// A customer's interest in a profile, as an agent sees it (SPEC §9.4).
/// `customerAgent` (the customer's agent) is set for the target profile's
/// uploader; `targetAgent` (the uploader) for the customer's own agent —
/// the one place uploader identity crosses agents. Admins get both.
class Interest {
  const Interest({
    required this.id,
    required this.status,
    required this.customer,
    this.profile,
    this.customerProfile,
    this.customerAgent,
    this.targetAgent,
    this.note,
    this.createdAt,
    this.decidedAt,
    this.accessExpiresAt,
    this.daysLeft,
    this.canDecide = false,
  });

  final int id;

  /// 'pending' | 'accepted' | 'declined' | 'withdrawn' | 'revoked' | 'expired'
  /// (an accepted interest whose 15-day window lapsed reads as 'expired').
  final String status;
  final InterestCustomer customer;

  /// The profile the customer is interested in.
  final ProfileSummary? profile;

  /// The customer's own profile, when they have one.
  final ProfileSummary? customerProfile;
  final AgentCard? customerAgent;
  final AgentCard? targetAgent;
  final String? note;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final DateTime? accessExpiresAt;

  /// Days of access left while accepted; null otherwise.
  final int? daysLeft;

  /// True for the target profile's uploader and admins.
  final bool canDecide;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';

  /// The agent on the other side of this interest, whichever side I am on.
  AgentCard? get otherAgent => customerAgent ?? targetAgent;

  String get statusLabel => switch (status) {
        'pending' => 'Waiting for a decision',
        'accepted' => daysLeft == null ? 'Details shared' : 'Details shared · $daysLeft days left',
        'declined' => 'Declined',
        'withdrawn' => 'Withdrawn by the client',
        'revoked' => 'Access revoked',
        'expired' => 'Access expired',
        _ => status,
      };

  factory Interest.fromJson(Map<String, dynamic> j) => Interest(
        id: (j['id'] as num).toInt(),
        status: '${j['status'] ?? 'pending'}',
        customer: InterestCustomer.fromJson(j['customer'] as Map<String, dynamic>? ?? const {}),
        profile: ProfileSummary.fromJsonOrNull(j['profile']),
        customerProfile: ProfileSummary.fromJsonOrNull(j['customer_profile']),
        customerAgent: AgentCard.fromJsonOrNull(j['customer_agent']),
        targetAgent: AgentCard.fromJsonOrNull(j['target_agent']),
        note: j['note'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal(),
        decidedAt: DateTime.tryParse('${j['decided_at']}')?.toLocal(),
        accessExpiresAt: DateTime.tryParse('${j['access_expires_at']}')?.toLocal(),
        daysLeft: (j['days_left'] as num?)?.toInt(),
        canDecide: j['can_decide'] == true,
      );
}
