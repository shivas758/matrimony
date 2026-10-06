import 'master_data.dart';

enum AgentStatus { pending, active, suspended }

class Agent {
  const Agent({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.status,
    this.agencyName,
    this.city,
    this.communities = const [],
    this.mustChangePassword = false,
    this.createdAt,
  });

  final int id;
  final String fullName;
  final String phone;
  final String role;
  final AgentStatus status;
  final String? agencyName;

  /// Directory city — shown to Gandharva customers when they pick an agent
  /// (SPEC §9.6). Edited from Settings via PATCH /my/account.
  final String? city;
  final List<MasterItem> communities;

  /// True after an admin issued a temporary password: the server blocks every
  /// data route until the agent sets their own (SPEC §4 Auth).
  final bool mustChangePassword;
  final DateTime? createdAt;

  bool get isAdmin => role == 'admin';
  bool get isActive => status == AgentStatus.active;
  bool get isPending => status == AgentStatus.pending;
  bool get isSuspended => status == AgentStatus.suspended;

  static AgentStatus _status(String? s) => switch (s) {
        'active' => AgentStatus.active,
        'suspended' => AgentStatus.suspended,
        _ => AgentStatus.pending,
      };

  factory Agent.fromJson(Map<String, dynamic> j) => Agent(
        id: j['id'] as int,
        fullName: '${j['full_name']}',
        phone: '${j['phone']}',
        role: '${j['role'] ?? 'agent'}',
        status: _status(j['status'] as String?),
        agencyName: j['agency_name'] as String?,
        city: j['city'] as String?,
        communities: (j['communities'] as List? ?? [])
            .map((e) => MasterItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        mustChangePassword: j['must_change_password'] == true,
        createdAt: DateTime.tryParse('${j['created_at']}'),
      );
}

/// Admin agent list rows carry a couple of extra counters.
class AdminAgent {
  const AdminAgent({required this.agent, required this.profileCount});

  final Agent agent;
  final int profileCount;

  factory AdminAgent.fromJson(Map<String, dynamic> j) => AdminAgent(
        agent: Agent.fromJson(j),
        profileCount: (j['profile_count'] as num?)?.toInt() ?? 0,
      );
}
