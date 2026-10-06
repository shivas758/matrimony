import '../services/api_client.dart';
import 'agent_change.dart';
import 'delete_request.dart';
import 'interest.dart';

/// Compact, public-only profile summary embedded in client, interest and
/// transfer rows (`profileSummary()` in backend/src/lib/profiles.js).
/// Never carries a protected field (SPEC §9.8).
class ProfileSummary {
  const ProfileSummary({
    required this.id,
    required this.fullName,
    this.gender,
    this.age,
    this.community,
    this.subcaste,
    this.status,
    this.photoUrl,
    this.paid,
    this.paidAt,
    this.visibility,
    this.deleteRequestId,
  });

  final int id;
  final String fullName;
  final String? gender;
  final int? age;
  final String? community;
  final String? subcaste;

  /// active | hidden | on_hold | engaged | married — `hidden` while the
  /// customer is still pending (SPEC §9.2).
  final String? status;
  final String? photoUrl;

  /// Client rows' `profiles[]` only (SPEC §9.12): whether the ₹150
  /// registration fee is paid. Null where the server does not say (interest
  /// rows, agent-uploaded profiles).
  final bool? paid;
  final DateTime? paidAt;

  /// payment_pending | awaiting_approval | live | hidden (client rows only).
  final String? visibility;

  /// The customer's pending delete request for this profile (SPEC §9.13).
  final int? deleteRequestId;

  /// True only when the server says the fee is NOT paid.
  bool get isUnpaid => paid == false;

  String? get genderLabel => switch (gender) {
        'bride' => 'Bride',
        'groom' => 'Groom',
        _ => gender,
      };

  String? get photoAbsoluteUrl => photoUrl == null ? null : ApiClient.absoluteUrl(photoUrl!);

  /// "Bride · 27 yrs · Reddy" for list rows.
  String get subtitle => [
        genderLabel,
        if (age != null) '$age yrs',
        community,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  static ProfileSummary? fromJsonOrNull(Object? j) =>
      j is Map<String, dynamic> ? ProfileSummary.fromJson(j) : null;

  factory ProfileSummary.fromJson(Map<String, dynamic> j) {
    final community = j['community'] as Map<String, dynamic>?;
    final subcaste = j['subcaste'] as Map<String, dynamic>?;
    return ProfileSummary(
      id: (j['id'] as num).toInt(),
      fullName: '${j['full_name'] ?? ''}',
      gender: j['gender'] as String?,
      age: (j['age'] as num?)?.toInt(),
      community: community?['name'] as String?,
      subcaste: subcaste?['name'] as String?,
      status: j['status'] as String?,
      photoUrl: j['photo_url'] as String?,
      paid: j['paid'] as bool?,
      paidAt: DateTime.tryParse('${j['paid_at']}')?.toLocal(),
      visibility: j['visibility'] as String?,
      deleteRequestId: (j['delete_request_id'] as num?)?.toInt(),
    );
  }
}

/// An agent's business card as another agent or a customer sees it
/// (`agentDirectory()` / `agentCard` in the backend): name, agency, city,
/// phone — never role or status.
class AgentCard {
  const AgentCard({
    required this.id,
    required this.fullName,
    this.agencyName,
    this.phone,
    this.city,
  });

  final int id;
  final String fullName;
  final String? agencyName;
  final String? phone;
  final String? city;

  /// Placeholder when the server left the card out.
  static const unknown = AgentCard(id: 0, fullName: 'Unknown agent');

  /// "Ravi Kumar · Sri Lakshmi Marriage Bureau"
  String get label =>
      [fullName, agencyName].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  /// "Ravi Kumar, Sri Lakshmi Marriage Bureau" — for sentences.
  String get labelComma =>
      [fullName, agencyName].whereType<String>().where((s) => s.isNotEmpty).join(', ');

  static AgentCard? fromJsonOrNull(Object? j) =>
      j is Map<String, dynamic> ? AgentCard.fromJson(j) : null;

  factory AgentCard.fromJson(Map<String, dynamic> j) => AgentCard(
        id: (j['id'] as num?)?.toInt() ?? 0,
        fullName: '${j['full_name'] ?? ''}',
        agencyName: j['agency_name'] as String?,
        phone: j['phone'] as String?,
        city: j['city'] as String?,
      );
}

/// The latest pending agent-change request embedded in a client row
/// (SPEC §9.5 `pending_agent_change`).
class PendingAgentChange {
  const PendingAgentChange({
    required this.id,
    required this.toAgent,
    this.note,
    this.createdAt,
  });

  final int id;
  final AgentCard toAgent;
  final String? note;
  final DateTime? createdAt;

  static PendingAgentChange? fromJsonOrNull(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    return PendingAgentChange(
      id: (j['id'] as num?)?.toInt() ?? 0,
      toAgent: AgentCard.fromJsonOrNull(j['to_agent']) ?? AgentCard.unknown,
      note: j['note'] as String?,
      createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal(),
    );
  }
}

/// A Gandharva customer as their agent (or an admin) sees them — one row of
/// GET /clients (SPEC §9.5). `interests` and `agentChangeRequests` are filled
/// only by GET /clients/:id; list rows leave them empty.
class Customer {
  const Customer({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.status,
    required this.source,
    this.agentId,
    this.agent,
    this.profile,
    this.profiles = const [],
    this.profileId,
    this.interestsCount = 0,
    this.pendingAgentChange,
    this.phoneVerifiedAt,
    this.approvedAt,
    this.createdAt,
    this.lastLoginAt,
    this.interests = const [],
    this.agentChangeRequests = const [],
    this.deleteRequests = const [],
  });

  final int id;
  final String fullName;
  final String phone;

  /// 'guest' | 'pending' | 'active' | 'rejected' | 'suspended' (SPEC §9.2 /
  /// §9.12 lifecycle). Guests have no agent yet — only admins see them.
  final String status;

  /// 'app' (signed up in Gandharva) | 'form' (the agent's registration form).
  final String source;
  final int? agentId;

  /// Admin rows only — the owning agent. An agent only ever lists their own.
  /// Null for a guest (no agent yet).
  final AgentCard? agent;

  /// The oldest profile (the v1.0 "one profile").
  final ProfileSummary? profile;

  /// Every profile of the customer, oldest first, with `paid` (SPEC §9.12).
  final List<ProfileSummary> profiles;
  final int? profileId;

  /// Interests still in play (pending or accepted).
  final int interestsCount;
  final PendingAgentChange? pendingAgentChange;
  final DateTime? phoneVerifiedAt;
  final DateTime? approvedAt;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final List<Interest> interests;
  final List<AgentChangeRequest> agentChangeRequests;

  /// GET /clients/:id only — requests to delete a paid profile (SPEC §9.13).
  final List<ProfileDeleteRequest> deleteRequests;

  bool get isGuest => status == 'guest';
  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isSuspended => status == 'suspended';
  bool get isRejected => status == 'rejected';
  bool get hasProfile => profile != null || profileId != null || profiles.isNotEmpty;

  /// All profiles, falling back to the single `profile` from an older server.
  List<ProfileSummary> get allProfiles =>
      profiles.isNotEmpty ? profiles : [?profile];

  /// Some profile has a pending delete request (SPEC §9.13).
  bool get hasDeleteRequest => allProfiles.any((p) => p.deleteRequestId != null);

  /// Some profile still owes the registration fee.
  bool get hasUnpaidProfile => allProfiles.any((p) => p.isUnpaid);

  /// Has profiles and none of them is paid — approving will not make any live.
  bool get allProfilesUnpaid =>
      allProfiles.isNotEmpty && allProfiles.every((p) => p.isUnpaid);
  bool get isFromForm => source == 'form';

  String get statusLabel => switch (status) {
        'guest' => 'Guest',
        'pending' => 'Waiting for approval',
        'active' => 'Active',
        'rejected' => 'Rejected',
        'suspended' => 'Suspended',
        _ => status,
      };

  String get sourceLabel => isFromForm ? 'Form' : 'App';

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: (j['id'] as num).toInt(),
        fullName: '${j['full_name'] ?? ''}',
        phone: '${j['phone'] ?? ''}',
        status: '${j['status'] ?? 'pending'}',
        source: '${j['source'] ?? 'app'}',
        agentId: (j['agent_id'] as num?)?.toInt(),
        // A guest's admin row carries an agent object of nulls — no agent.
        agent: j['agent'] is Map && (j['agent'] as Map)['id'] == null
            ? null
            : AgentCard.fromJsonOrNull(j['agent']),
        profile: ProfileSummary.fromJsonOrNull(j['profile']),
        profiles: (j['profiles'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ProfileSummary.fromJson)
            .toList(),
        profileId: (j['profile_id'] as num?)?.toInt(),
        interestsCount: (j['interests_count'] as num?)?.toInt() ?? 0,
        pendingAgentChange: PendingAgentChange.fromJsonOrNull(j['pending_agent_change']),
        phoneVerifiedAt: DateTime.tryParse('${j['phone_verified_at']}')?.toLocal(),
        approvedAt: DateTime.tryParse('${j['approved_at']}')?.toLocal(),
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal(),
        lastLoginAt: DateTime.tryParse('${j['last_login_at']}')?.toLocal(),
        interests: (j['interests'] as List? ?? [])
            .map((e) => Interest.fromJson(e as Map<String, dynamic>))
            .toList(),
        agentChangeRequests: (j['agent_change_requests'] as List? ?? [])
            .map((e) => AgentChangeRequest.fromJson(e as Map<String, dynamic>))
            .toList(),
        deleteRequests: (j['delete_requests'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ProfileDeleteRequest.fromJson)
            .toList(),
      );
}
