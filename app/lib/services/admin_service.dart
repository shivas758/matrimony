import '../models/agent.dart';
import '../models/customer.dart';
import '../models/master_data.dart';
import 'api_client.dart';

class CommunityRequest {
  const CommunityRequest({
    required this.id,
    required this.status,
    required this.communityId,
    required this.communityName,
    this.agentId,
    this.agentName,
    this.agentPhone,
    this.agencyName,
    this.createdAt,
  });

  final int id;
  final String status;
  final int communityId;
  final String communityName;
  final int? agentId;
  final String? agentName;
  final String? agentPhone;
  final String? agencyName;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory CommunityRequest.fromJson(Map<String, dynamic> j) => CommunityRequest(
        id: j['id'] as int,
        status: '${j['status']}',
        communityId: (j['community_id'] as num).toInt(),
        communityName: '${j['community_name']}',
        agentId: (j['agent_id'] as num?)?.toInt(),
        agentName: j['agent_name'] as String?,
        agentPhone: j['agent_phone'] as String?,
        agencyName: j['agency_name'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal(),
      );
}

class ShareLogEntry {
  const ShareLogEntry({
    required this.id,
    required this.profileName,
    required this.agentName,
    required this.method,
    this.agencyName,
    this.sharedAt,
  });

  final int id;
  final String profileName;
  final String agentName;
  final String method;
  final String? agencyName;
  final DateTime? sharedAt;

  factory ShareLogEntry.fromJson(Map<String, dynamic> j) => ShareLogEntry(
        id: j['id'] as int,
        profileName: '${j['profile_name']}',
        agentName: '${j['agent_name']}',
        method: '${j['method']}',
        agencyName: j['agency_name'] as String?,
        sharedAt: DateTime.tryParse('${j['shared_at']}')?.toLocal(),
      );
}

class ContactLogEntry {
  const ContactLogEntry({
    required this.id,
    required this.profileName,
    required this.requesterName,
    required this.status,
    this.uploaderName,
    this.decidedByName,
    this.requestedAt,
    this.expiresAt,
  });

  final int id;
  final String profileName;
  final String requesterName;
  final String status;
  final String? uploaderName;
  final String? decidedByName;
  final DateTime? requestedAt;
  final DateTime? expiresAt;

  factory ContactLogEntry.fromJson(Map<String, dynamic> j) => ContactLogEntry(
        id: j['id'] as int,
        profileName: '${j['profile_name']}',
        requesterName: '${j['requester_name']}',
        status: '${j['status']}',
        uploaderName: j['uploader_name'] as String?,
        decidedByName: j['decided_by_name'] as String?,
        requestedAt: DateTime.tryParse('${j['requested_at']}')?.toLocal(),
        expiresAt: DateTime.tryParse('${j['expires_at']}')?.toLocal(),
      );
}

/// A "Forgot password?" request waiting for an admin (SPEC §2).
class PasswordResetRequest {
  const PasswordResetRequest({
    required this.id,
    required this.status,
    required this.agentId,
    required this.agentName,
    required this.agentPhone,
    this.agencyName,
    this.agentStatus,
    this.decidedByName,
    this.requestedAt,
    this.decidedAt,
  });

  final int id;
  final String status;
  final int agentId;
  final String agentName;
  final String agentPhone;
  final String? agencyName;
  final String? agentStatus;
  final String? decidedByName;
  final DateTime? requestedAt;
  final DateTime? decidedAt;

  bool get isPending => status == 'pending';

  factory PasswordResetRequest.fromJson(Map<String, dynamic> j) => PasswordResetRequest(
        id: j['id'] as int,
        status: '${j['status']}',
        agentId: (j['agent_id'] as num).toInt(),
        agentName: '${j['agent_name']}',
        agentPhone: '${j['agent_phone']}',
        agencyName: j['agency_name'] as String?,
        agentStatus: j['agent_status'] as String?,
        decidedByName: j['decided_by_name'] as String?,
        requestedAt: DateTime.tryParse('${j['requested_at']}')?.toLocal(),
        decidedAt: DateTime.tryParse('${j['decided_at']}')?.toLocal(),
      );
}

class AdminStats {
  const AdminStats({
    required this.activeAgents,
    required this.pendingAgents,
    required this.activeProfiles,
    required this.totalProfiles,
    required this.pendingContactRequests,
    required this.pendingCommunityRequests,
    required this.pendingPasswordResets,
    required this.sharesLast7Days,
    this.pendingHoldRequests = 0,
    this.onHoldProfiles = 0,
    this.pendingCustomers = 0,
    this.activeCustomers = 0,
    this.pendingInterests = 0,
    this.pendingAgentChanges = 0,
    this.guestCustomers = 0,
    this.paidRegistrations = 0,
  });

  final int activeAgents;
  final int pendingAgents;
  final int activeProfiles;
  final int totalProfiles;
  final int pendingContactRequests;
  final int pendingCommunityRequests;
  final int pendingPasswordResets;
  final int sharesLast7Days;
  final int pendingHoldRequests;
  final int onHoldProfiles;

  /// SPEC §9.5 — Gandharva customers and their workflows.
  final int pendingCustomers;
  final int activeCustomers;
  final int pendingInterests;
  final int pendingAgentChanges;

  /// SPEC §9.12 — guests (no agent yet) and ₹150 fees actually paid
  /// (grandfathered 'waived' ones excluded).
  final int guestCustomers;
  final int paidRegistrations;

  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
        activeAgents: _i(j['active_agents']),
        pendingAgents: _i(j['pending_agents']),
        activeProfiles: _i(j['active_profiles']),
        totalProfiles: _i(j['total_profiles']),
        pendingContactRequests: _i(j['pending_contact_requests']),
        pendingCommunityRequests: _i(j['pending_community_requests']),
        pendingPasswordResets: _i(j['pending_password_resets']),
        sharesLast7Days: _i(j['shares_last_7_days']),
        pendingHoldRequests: _i(j['pending_hold_requests']),
        onHoldProfiles: _i(j['on_hold_profiles']),
        pendingCustomers: _i(j['pending_customers']),
        activeCustomers: _i(j['active_customers']),
        pendingInterests: _i(j['pending_interests']),
        pendingAgentChanges: _i(j['pending_agent_changes']),
        guestCustomers: _i(j['guest_customers']),
        paidRegistrations: _i(j['paid_registrations']),
      );
}

class AdminService {
  AdminService(this._api);

  final ApiClient _api;

  Future<AdminStats> stats() async {
    final json = await _api.get('/admin/stats');
    return AdminStats.fromJson(json['stats'] as Map<String, dynamic>);
  }

  Future<List<AdminAgent>> agents({String? status, String? q}) async {
    final json = await _api.get('/admin/agents', query: {
      'status': ?status,
      if (q != null && q.isNotEmpty) 'q': q,
    });
    return (json['agents'] as List? ?? [])
        .map((e) => AdminAgent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> activateAgent(int id) => _api.post('/admin/agents/$id/activate');
  Future<void> suspendAgent(int id) => _api.post('/admin/agents/$id/suspend');
  Future<void> setRole(int id, String role) =>
      _api.post('/admin/agents/$id/role', body: {'role': role});
  Future<void> setAgentCommunities(int id, List<int> communityIds) =>
      _api.put('/admin/agents/$id/communities', body: {'community_ids': communityIds});

  Future<List<CommunityRequest>> communityRequests({String? status}) async {
    final json = await _api.get('/admin/community-requests',
        query: {'status': ?status});
    return (json['community_requests'] as List? ?? [])
        .map((e) => CommunityRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> decideCommunityRequest(int id, {required bool approve}) =>
      _api.post('/admin/community-requests/$id/${approve ? 'approve' : 'reject'}');

  // ---- forgot-password flow (SPEC §4 Admin)

  Future<List<PasswordResetRequest>> passwordResets({String? status}) async {
    final json = await _api.get('/admin/password-resets', query: {'status': ?status});
    return (json['password_resets'] as List? ?? [])
        .map((e) => PasswordResetRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Approves the request by setting [temporaryPassword]; the agent must
  /// change it on their next login.
  Future<void> approvePasswordReset(int id, String temporaryPassword) =>
      _api.post('/admin/password-resets/$id/approve', body: {'temporary_password': temporaryPassword});

  Future<void> rejectPasswordReset(int id) => _api.post('/admin/password-resets/$id/reject');

  /// Same as approving, but for an agent who phoned instead of tapping the button.
  Future<void> resetAgentPassword(int agentId, String temporaryPassword) =>
      _api.post('/admin/agents/$agentId/reset-password', body: {'temporary_password': temporaryPassword});

  // ---- customers (SPEC §9.5) — Gandharva accounts across every agent

  Future<List<Customer>> customers({String? status, String? q}) async {
    final json = await _api.get('/admin/customers', query: {
      'status': ?status,
      if (q != null && q.isNotEmpty) 'q': q,
    });
    return (json['customers'] as List? ?? [])
        .map((e) => Customer.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// pending / rejected / suspended → active (a first approval also makes a
  /// hidden profile active).
  Future<Customer> activateCustomer(int id) => _customerAction(id, 'activate');
  Future<Customer> suspendCustomer(int id) => _customerAction(id, 'suspend'); // active only
  Future<Customer> rejectCustomer(int id) => _customerAction(id, 'reject'); // pending only

  Future<Customer> _customerAction(int id, String action) async {
    final json = await _api.post('/admin/customers/$id/$action');
    return Customer.fromJson(json['customer'] as Map<String, dynamic>);
  }

  /// Moves the customer (and their profile's uploader) to [agentId]; pending
  /// change requests are cancelled. `same_agent` / `agent_not_active` errors.
  Future<Customer> reassignCustomer(int id, int agentId) async {
    final json = await _api.put('/admin/customers/$id/agent', body: {'agent_id': agentId});
    return Customer.fromJson(json['customer'] as Map<String, dynamic>);
  }

  Future<List<ShareLogEntry>> shareLogs({int limit = 100}) async {
    final json = await _api.get('/admin/logs/shares', query: {'limit': limit});
    return (json['logs'] as List? ?? [])
        .map((e) => ShareLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ContactLogEntry>> contactLogs({int limit = 100}) async {
    final json = await _api.get('/admin/logs/contacts', query: {'limit': limit});
    return (json['logs'] as List? ?? [])
        .map((e) => ContactLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Master editor. [table] is one of communities/professions/educations/
  /// marital_statuses/nakshatrams/zodiac_signs.
  Future<void> addMaster(String table, Map<String, dynamic> body) =>
      _api.post('/admin/masters/$table', body: body);

  Future<void> updateMaster(String table, int id, Map<String, dynamic> body) =>
      _api.patch('/admin/masters/$table/$id', body: body);

  /// Includes inactive rows so admins can re-enable them.
  Future<MasterData> allMasters() async =>
      MasterData.fromJson(await _api.get('/masters', query: {'include_inactive': 'true'}));
}

/// Agent self-service: my communities and requests to join more.
class MyAccountService {
  MyAccountService(this._api);

  final ApiClient _api;

  Future<({List<MasterItem> communities, List<CommunityRequest> requests})> communities() async {
    final json = await _api.get('/my/communities');
    return (
      communities: (json['communities'] as List? ?? [])
          .map((e) => MasterItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      requests: (json['requests'] as List? ?? [])
          .map((e) => CommunityRequest.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> requestCommunity(int communityId) =>
      _api.post('/my/community-requests', body: {'community_id': communityId});

  /// PATCH /my/account — the agent's directory details customers see when
  /// picking an agent (SPEC §9.6). Only the keys passed are updated; an empty
  /// string clears the value. Returns the refreshed agent.
  Future<Agent> updateAccount({String? city, String? agencyName}) async {
    final json = await _api.patch('/my/account', body: {
      'city': ?city,
      'agency_name': ?agencyName,
    });
    return Agent.fromJson(json['agent'] as Map<String, dynamic>);
  }
}
