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
    this.state,
    this.agentCode,
    this.knowsAgentCodes = false,
  });

  final int id;
  final String fullName;
  final String phone;
  final String role;
  final AgentStatus status;
  final String? agencyName;

  /// Directory city — shown to Wedbook Matrimony customers when they pick an agent
  /// (SPEC §9.6). Edited from Settings via PATCH /my/account.
  final String? city;
  final List<MasterItem> communities;

  /// True after an admin issued a temporary password: the server blocks every
  /// data route until the agent sets their own (SPEC §4 Auth).
  final bool mustChangePassword;
  final DateTime? createdAt;

  /// The state the agent registered in (SPEC §9.18 B). Null until chosen —
  /// agents from before v2.8 pick it once on the "Choose your State" screen.
  final StateItem? state;

  /// The permanent agent code, e.g. "KA1A": state code + number + letter(s).
  /// Null until a state is chosen. Never changes afterwards.
  final String? agentCode;

  /// The server sent an `agent_code` key at all. A server older than v2.8
  /// does not — the app must not ask for a state it cannot save.
  final bool knowsAgentCodes;

  bool get hasAgentCode => (agentCode ?? '').isNotEmpty;

  /// An active agent without a code must choose their state before Home.
  bool get needsState => knowsAgentCodes && isActive && !hasAgentCode;

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
        state: StateItem.fromJsonOrNull(j['state']),
        agentCode: _code(j['agent_code']),
        knowsAgentCodes: j.containsKey('agent_code'),
      );

  static String? _code(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
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
