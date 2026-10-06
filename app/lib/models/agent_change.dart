import 'customer.dart';

/// The customer on an agent-change request. `phone` only while I am their
/// current agent (or an admin).
class AgentChangeCustomer {
  const AgentChangeCustomer({
    required this.id,
    required this.fullName,
    this.phone,
    this.status,
    this.agentId,
  });

  final int id;
  final String fullName;
  final String? phone;
  final String? status;
  final int? agentId;

  factory AgentChangeCustomer.fromJson(Map<String, dynamic> j) => AgentChangeCustomer(
        id: (j['id'] as num?)?.toInt() ?? 0,
        fullName: '${j['full_name'] ?? ''}',
        phone: j['phone'] as String?,
        status: j['status'] as String?,
        agentId: (j['agent_id'] as num?)?.toInt(),
      );
}

/// A customer's request to move to another agent (SPEC §9.6). For me it is
/// `outgoing` (my client leaving — I decide) or `incoming` (joining me —
/// read-only); admins see every request.
class AgentChangeRequest {
  const AgentChangeRequest({
    required this.id,
    required this.status,
    required this.fromAgent,
    required this.toAgent,
    required this.customer,
    this.box,
    this.customerProfile,
    this.note,
    this.createdAt,
    this.decidedAt,
    this.canDecide = false,
  });

  final int id;

  /// 'pending' | 'approved' | 'rejected' | 'cancelled'
  final String status;
  final AgentCard fromAgent;
  final AgentCard toAgent;
  final AgentChangeCustomer customer;

  /// 'outgoing' | 'incoming' | null (admin looking at someone else's).
  final String? box;
  final ProfileSummary? customerProfile;
  final String? note;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final bool canDecide;

  bool get isPending => status == 'pending';
  bool get isOutgoing => box == 'outgoing';
  bool get isIncoming => box == 'incoming';

  String get statusLabel => switch (status) {
        'pending' => 'Waiting for a decision',
        'approved' => 'Approved — moved',
        'rejected' => 'Rejected',
        'cancelled' => 'Cancelled by the client',
        _ => status,
      };

  factory AgentChangeRequest.fromJson(Map<String, dynamic> j) => AgentChangeRequest(
        id: (j['id'] as num).toInt(),
        status: '${j['status'] ?? 'pending'}',
        fromAgent: AgentCard.fromJsonOrNull(j['from_agent']) ?? AgentCard.unknown,
        toAgent: AgentCard.fromJsonOrNull(j['to_agent']) ?? AgentCard.unknown,
        customer:
            AgentChangeCustomer.fromJson(j['customer'] as Map<String, dynamic>? ?? const {}),
        box: j['box'] as String?,
        customerProfile: ProfileSummary.fromJsonOrNull(j['customer_profile']),
        note: j['note'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal(),
        decidedAt: DateTime.tryParse('${j['decided_at']}')?.toLocal(),
        canDecide: j['can_decide'] == true,
      );
}
