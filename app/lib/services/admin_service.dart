import '../config.dart';
import '../models/agent.dart';
import '../models/customer.dart';
import '../models/deletion_request.dart';
import '../models/gift_code.dart';
import '../models/master_data.dart';
import '../models/moderation.dart';
import '../models/payment.dart';
import 'api_client.dart';

/// A request to join one more community (SPEC §2). Beyond the free ones it
/// carries a one-time fee paid by UPI (SPEC §9.20 C): the agent's own rows
/// have the whole [payment]; the admin's rows only its id, status and UTR.
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
    this.agentCode,
    this.createdAt,
    this.feeInr = 0,
    this.payment,
    this.paymentId,
    this.paymentStatus,
    this.utr,
  });

  final int id;
  final String status;
  final int communityId;
  final String communityName;
  final int? agentId;
  final String? agentName;
  final String? agentPhone;
  final String? agencyName;
  final String? agentCode;
  final DateTime? createdAt;

  /// 0 = a free request; otherwise the one-time fee in ₹.
  final int feeInr;

  /// The agent's own rows (`GET /my/communities`, `POST /my/community-requests`).
  final UpiPayment? payment;

  /// The admin's rows (`GET /admin/community-requests`).
  final int? paymentId;
  final String? paymentStatus;
  final String? utr;

  bool get isPending => status == 'pending';
  bool get hasFee => feeInr > 0;

  /// The fee payment's status from either shape of row; null when free.
  String? get feePaymentStatus => payment?.status ?? paymentStatus;

  /// The fee payment's UTR from either shape of row.
  String? get feeUtr => payment?.utr ?? utr;

  /// A pending fee request whose UTR has not been accepted yet: never sent
  /// (`created`) or rejected by the admin (`failed`).
  bool get needsPayment {
    if (!isPending || !hasFee) return false;
    final s = feePaymentStatus;
    return s == PaymentStatus.created || s == PaymentStatus.failed;
  }

  factory CommunityRequest.fromJson(Map<String, dynamic> j) => CommunityRequest(
        id: (j['id'] as num).toInt(),
        status: '${j['status']}',
        communityId: (j['community_id'] as num).toInt(),
        communityName: '${j['community_name']}',
        agentId: (j['agent_id'] as num?)?.toInt(),
        agentName: j['agent_name'] as String?,
        agentPhone: j['agent_phone'] as String?,
        agencyName: j['agency_name'] as String?,
        agentCode: j['agent_code'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal(),
        feeInr: (j['fee_inr'] as num?)?.toInt() ?? 0,
        payment: UpiPayment.fromJsonOrNull(j['payment']),
        paymentId: (j['payment_id'] as num?)?.toInt(),
        paymentStatus: j['payment_status'] as String?,
        utr: j['utr'] as String?,
      );
}

/// `GET /my/communities` (SPEC §9.20 C): my communities, my requests, and
/// the fee rule — [freeLimit] communities free, then [extraFeeInr] each.
class MyCommunities {
  const MyCommunities({
    required this.communities,
    required this.requests,
    this.freeLimit = AppConfig.communityFreeLimit,
    this.extraFeeInr = AppConfig.extraCommunityFeeInr,
  });

  final List<MasterItem> communities;
  final List<CommunityRequest> requests;
  final int freeLimit;
  final int extraFeeInr;

  List<CommunityRequest> get pending => requests.where((r) => r.isPending).toList();

  /// What the server counts against the free limit: current communities
  /// plus pending requests.
  int get used => communities.length + pending.length;

  /// The next request costs [extraFeeInr] (admins never pay — the server
  /// decides; this only warns before sending).
  bool get nextIsPaid => used >= freeLimit;

  /// 1-based position of the next community ("your 4th community").
  int get nextNumber => used + 1;

  factory MyCommunities.fromJson(Map<String, dynamic> j) => MyCommunities(
        communities: (j['communities'] as List? ?? [])
            .map((e) => MasterItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        requests: (j['requests'] as List? ?? [])
            .map((e) => CommunityRequest.fromJson(e as Map<String, dynamic>))
            .toList(),
        freeLimit: (j['free_limit'] as num?)?.toInt() ?? AppConfig.communityFreeLimit,
        extraFeeInr: (j['extra_fee_inr'] as num?)?.toInt() ?? AppConfig.extraCommunityFeeInr,
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
    this.paymentsToVerify = 0,
    this.deletionRequests = 0,
    this.reportsOpen = 0,
    this.unapprovedAgents,
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

  /// SPEC §9.20 D — UPI payments whose UTR waits for an admin's check.
  final int paymentsToVerify;

  /// SPEC §9.20 F — account deletion requests waiting for an admin.
  final int deletionRequests;

  /// SPEC §9.22 A — reported profiles waiting for an admin.
  final int reportsOpen;

  /// SPEC §9.23 A — active agents below 10 live clients, not approved by
  /// hand. Null on an older server.
  final int? unapprovedAgents;

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
        paymentsToVerify: _i(j['payments_to_verify']),
        deletionRequests: _i(j['deletion_requests']),
        reportsOpen: _i(j['reports_open']),
        unapprovedAgents: (j['unapproved_agents'] as num?)?.toInt(),
      );
}

class AdminService {
  AdminService(this._api);

  final ApiClient _api;

  Future<AdminStats> stats() async {
    final json = await _api.get('/admin/stats');
    return AdminStats.fromJson(json['stats'] as Map<String, dynamic>);
  }

  /// [approved]: true = approved agents only, false = not approved yet
  /// (SPEC §9.23 A); null = both.
  Future<List<AdminAgent>> agents({String? status, String? q, bool? approved}) async {
    final json = await _api.get('/admin/agents', query: {
      'status': ?status,
      if (q != null && q.isNotEmpty) 'q': q,
      if (approved != null) 'approved': '$approved',
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

  /// Approves an agent by hand before they reach 10 live clients (SPEC
  /// §9.23 A). `409 already_approved`. Returns the agent when sent back.
  Future<Agent?> approveAgent(int id) async {
    final json = await _api.post('/admin/agents/$id/approve');
    final agent = json['agent'];
    return agent is Map<String, dynamic> ? Agent.fromJson(agent) : null;
  }

  /// Gives an agent [count] (1–50) more gift codes (SPEC §9.23 B); returns
  /// their new counts.
  Future<GiftCodeCounts> addGiftCodes(int id, int count) async {
    final json = await _api.post('/admin/agents/$id/gift-codes', body: {'count': count});
    return GiftCodeCounts.fromJsonOrNull(json['gift_codes']) ?? GiftCodeCounts.empty;
  }

  Future<List<CommunityRequest>> communityRequests({String? status}) async {
    final json = await _api.get('/admin/community-requests',
        query: {'status': ?status});
    return (json['community_requests'] as List? ?? [])
        .map((e) => CommunityRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Approving a fee request needs its payment submitted or paid
  /// (`409 payment_not_submitted` otherwise, SPEC §9.20 C).
  Future<void> decideCommunityRequest(int id, {required bool approve}) =>
      _api.post('/admin/community-requests/$id/${approve ? 'approve' : 'reject'}');

  // ---- UPI payments to verify (SPEC §9.20 D)

  /// [status]: `submitted` (to verify, the default), `paid`, `failed` or `all`.
  Future<List<AdminPayment>> payments({String status = PaymentStatus.submitted}) async {
    final json = await _api.get('/admin/payments', query: {'status': status});
    return (json['payments'] as List? ?? [])
        .map((e) => AdminPayment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The admin saw the money arrive: a profile fee is settled, an extra
  /// community is added. Only from `submitted` (`409 wrong_status`).
  Future<void> approvePayment(int id) => _api.post('/admin/payments/$id/approve');

  /// [reason] (3–200 characters) is shown to the payer, who may submit again.
  Future<void> rejectPayment(int id, String reason) =>
      _api.post('/admin/payments/$id/reject', body: {'reason': reason});

  // ---- reports (SPEC §9.22 A)

  /// [status]: `open` (the default), `actioned`, `dismissed` or `all`.
  Future<List<AdminReport>> reports({String status = 'open'}) async {
    final json = await _api.get('/admin/reports', query: {'status': status});
    return (json['reports'] as List? ?? [])
        .map((e) => AdminReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Closes the report; nothing changes for the profile.
  Future<void> dismissReport(int id, {String? note}) => _reportAction(id, 'dismiss', note);

  /// The profile becomes hidden; every open report on it is actioned.
  Future<void> hideReportedProfile(int id, {String? note}) =>
      _reportAction(id, 'hide-profile', note);

  /// The family's account (or the uploading agent) is suspended and the
  /// profile hidden.
  Future<void> suspendReportedAccount(int id, {String? note}) =>
      _reportAction(id, 'suspend-account', note);

  Future<void> _reportAction(int id, String action, String? note) => _api.post(
    '/admin/reports/$id/$action',
    body: {if (note != null && note.isNotEmpty) 'note': note},
  );

  // ---- account deletion requests (SPEC §9.20 F)

  /// [status]: `pending` (the default), `done`, `rejected` or `all`.
  Future<List<DeletionRequest>> deletionRequests({String status = 'pending'}) async {
    final json = await _api.get('/admin/deletion-requests', query: {'status': status});
    return (json['deletion_requests'] as List? ?? [])
        .map((e) => DeletionRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Deletes the account (customer) or scrubs and suspends it (agent).
  /// `409 agent_has_data` while an agent still owns profiles or clients;
  /// `409 already_decided`.
  Future<DeletionDecision> completeDeletion(int id) async {
    final json = await _api.post('/admin/deletion-requests/$id/complete');
    return DeletionDecision.fromJson(json['deletion_request'] as Map<String, dynamic>? ?? const {});
  }

  /// [note] (3–200 characters) says why.
  Future<void> rejectDeletion(int id, String note) =>
      _api.post('/admin/deletion-requests/$id/reject', body: {'note': note});

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

  Future<MyCommunities> communities() async =>
      MyCommunities.fromJson(await _api.get('/my/communities'));

  /// Beyond the free limit the request comes back with `fee_inr` and a UPI
  /// payment to make (SPEC §9.20 C); `503 payment_provider_error` while UPI
  /// is not set up on the server.
  Future<CommunityRequest> requestCommunity(int communityId) async {
    final json = await _api.post('/my/community-requests', body: {'community_id': communityId});
    return CommunityRequest.fromJson(json['community_request'] as Map<String, dynamic>);
  }

  /// The 12-digit UTR of my fee payment → `submitted` (an admin checks it).
  /// `409 utr_already_used` / `409 wrong_status`. Returns the updated
  /// payment when the server sends it back.
  Future<UpiPayment?> submitPayment(int paymentId, String utr) async {
    final json = await _api.post('/my/payments/$paymentId/submit', body: {'utr': utr});
    return UpiPayment.fromJsonOrNull(json['payment']);
  }

  /// Profiles I blocked (SPEC §9.22 B), newest first.
  Future<List<BlockedProfile>> blocks() async {
    final json = await _api.get('/my/blocks');
    return (json['blocks'] as List? ?? [])
        .map((e) => BlockedProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> unblock(int profileId) => _api.delete('/my/blocks/$profileId');

  /// My gift codes (SPEC §9.23 B) — the first call issues the free ten.
  Future<GiftCodeList> giftCodes() async =>
      GiftCodeList.fromJson(await _api.get('/my/gift-codes'));

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
