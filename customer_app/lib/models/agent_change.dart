import 'customer.dart';

/// A request to move to another agent (SPEC §9.6), as the customer routes
/// return it: `{id, status, note, created_at, decided_at, from_agent, to_agent}`.
/// Both agents are directory cards (name, agency, city, phone — no communities).
class AgentChangeRequest {
  const AgentChangeRequest({
    required this.id,
    required this.status,
    required this.fromAgent,
    required this.toAgent,
    this.note,
    this.createdAt,
    this.decidedAt,
  });

  final int id;

  /// 'pending' | 'approved' | 'rejected' | 'cancelled'
  final String status;
  final String? note;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final AgentCard fromAgent;
  final AgentCard toAgent;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  factory AgentChangeRequest.fromJson(Map<String, dynamic> j) => AgentChangeRequest(
        id: (j['id'] as num).toInt(),
        status: '${j['status'] ?? 'pending'}',
        note: j['note'] as String?,
        createdAt: _date(j['created_at']),
        decidedAt: _date(j['decided_at']),
        fromAgent: AgentCard.fromJson(j['from_agent'] as Map<String, dynamic>),
        toAgent: AgentCard.fromJson(j['to_agent'] as Map<String, dynamic>),
      );

  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
}
