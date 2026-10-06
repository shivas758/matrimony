import 'master_data.dart';
import 'profile.dart';

/// Customer lifecycle (SPEC §9.2 / §9.12): guest (no agent yet) → pending
/// (agent linked) → active; agent/admin may reject a pending one or suspend /
/// re-activate an active one.
enum CustomerStatus {
  guest('guest'),
  pending('pending'),
  active('active'),
  rejected('rejected'),
  suspended('suspended');

  const CustomerStatus(this.apiValue);

  /// The `status` value on the wire.
  final String apiValue;

  static CustomerStatus fromApi(String? s) =>
      values.firstWhere((v) => v.apiValue == s, orElse: () => CustomerStatus.pending);
}

/// An agent as customers see them: business details only (SPEC §9.6). Used
/// for `customer.agent`, the agent directory rows and `to_agent` in a
/// pending change (where phone and communities may be absent).
class AgentCard {
  const AgentCard({
    required this.id,
    required this.fullName,
    this.agencyName,
    this.city,
    this.phone,
    this.communities = const [],
    this.isCurrent = false,
  });

  final int id;
  final String fullName;
  final String? agencyName;
  final String? city;
  final String? phone;
  final List<MasterItem> communities;

  /// Directory rows flag the customer's current agent.
  final bool isCurrent;

  /// "Sri Lakshmi Marriage Bureau · Guntur" — whichever parts are present.
  String? get agencyLine {
    final parts = [agencyName, city].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get communitiesLabel =>
      communities.isEmpty ? null : communities.map((c) => c.name).join(', ');

  factory AgentCard.fromJson(Map<String, dynamic> j) => AgentCard(
        id: (j['id'] as num).toInt(),
        fullName: '${j['full_name'] ?? ''}',
        agencyName: j['agency_name'] as String?,
        city: j['city'] as String?,
        phone: j['phone'] as String?,
        communities: (j['communities'] as List? ?? [])
            .map((e) => MasterItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        isCurrent: j['is_current'] == true,
      );
}

/// The customer's open request to move to another agent (SPEC §9.6).
class PendingAgentChange {
  const PendingAgentChange({required this.id, required this.toAgent, this.createdAt});

  final int id;
  final AgentCard toAgent;
  final DateTime? createdAt;

  factory PendingAgentChange.fromJson(Map<String, dynamic> j) => PendingAgentChange(
        id: (j['id'] as num).toInt(),
        toAgent: AgentCard.fromJson(j['to_agent'] as Map<String, dynamic>),
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal(),
      );
}

/// The steps between a guest and full access (SPEC §9.12 `unlock`).
class UnlockChecklist {
  const UnlockChecklist({
    this.agentLinked = false,
    this.profileRegistered = false,
    this.paid = false,
    this.approved = false,
  });

  final bool agentLinked;
  final bool profileRegistered;
  final bool paid;
  final bool approved;

  bool get allDone => agentLinked && profileRegistered && paid && approved;

  factory UnlockChecklist.fromJson(Map<String, dynamic>? j) => j == null
      ? const UnlockChecklist()
      : UnlockChecklist(
          agentLinked: j['agent_linked'] == true,
          profileRegistered: j['profile_registered'] == true,
          paid: j['paid'] == true,
          approved: j['approved'] == true,
        );
}

/// The signed-in customer — GET /customer/auth/me (SPEC §9.9 / §9.12).
class Customer {
  const Customer({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.status,
    this.source = 'app',
    this.phoneVerifiedAt,
    this.approvedAt,
    this.createdAt,
    this.agent,
    this.profileId,
    this.hasProfile = false,
    this.pendingAgentChange,
    this.access = 'guest',
    this.profiles = const [],
    this.maxProfiles = 5,
    this.profileFeeInr,
    this.paymentProvider = 'mock',
    this.unlock = const UnlockChecklist(),
  });

  final int id;
  final String fullName;
  final String phone;
  final CustomerStatus status;

  /// 'app' (signed up in Gandharva) or 'form' (the agent's web form).
  final String source;
  final DateTime? phoneVerifiedAt;
  final DateTime? approvedAt;
  final DateTime? createdAt;

  /// Null while a guest has not chosen an agent yet (SPEC §9.12).
  final AgentCard? agent;

  /// The oldest of my profiles (the v1.0 field), if any.
  final int? profileId;
  final bool hasProfile;
  final PendingAgentChange? pendingAgentChange;

  /// 'full' (active + a paid profile) or 'guest' — computed by the server.
  final String access;

  /// My profiles, oldest first, with their fee / approval state.
  final List<ProfileSummary> profiles;
  final int maxProfiles;

  /// The registration fee per profile, in rupees (never hard-coded in the
  /// app); null only if the server did not say.
  final num? profileFeeInr;

  /// 'mock' | 'razorpay' — this app version can only check out with 'mock'.
  final String paymentProvider;
  final UnlockChecklist unlock;

  bool get isGuest => status == CustomerStatus.guest;
  bool get isActive => status == CustomerStatus.active;
  bool get isPending => status == CustomerStatus.pending;
  bool get isRejected => status == CustomerStatus.rejected;
  bool get isSuspended => status == CustomerStatus.suspended;

  bool get hasFullAccess => access == 'full';

  /// Guests, pending and rejected customers pick their agent themselves
  /// (POST /customer/agent); active ones go through Change agent (SPEC §9.6).
  bool get canLinkAgent => isGuest || isPending || isRejected;

  bool get canAddProfile => profiles.length < maxProfiles;

  /// The first profile still waiting for its fee, if any.
  ProfileSummary? get firstUnpaid {
    for (final p in profiles) {
      if (!p.paid) return p;
    }
    return null;
  }

  /// My live profiles that can express interest in someone of [targetGender].
  List<ProfileSummary> liveProfilesFor(String targetGender) => profiles
      .where((p) => p.visibility == ProfileVisibility.live && p.gender != targetGender)
      .toList();

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: (j['id'] as num).toInt(),
        fullName: '${j['full_name'] ?? ''}',
        phone: '${j['phone'] ?? ''}',
        status: CustomerStatus.fromApi(j['status'] as String?),
        source: '${j['source'] ?? 'app'}',
        phoneVerifiedAt: _date(j['phone_verified_at']),
        approvedAt: _date(j['approved_at']),
        createdAt: _date(j['created_at']),
        agent: j['agent'] == null ? null : AgentCard.fromJson(j['agent'] as Map<String, dynamic>),
        profileId: (j['profile_id'] as num?)?.toInt(),
        hasProfile: j['has_profile'] == true ||
            j['profile_id'] != null ||
            (j['profiles'] is List && (j['profiles'] as List).isNotEmpty),
        pendingAgentChange: j['pending_agent_change'] == null
            ? null
            : PendingAgentChange.fromJson(j['pending_agent_change'] as Map<String, dynamic>),
        access: j['access'] == 'full' ? 'full' : 'guest',
        profiles: (j['profiles'] as List? ?? [])
            .map((e) => ProfileSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
        maxProfiles: (j['max_profiles'] as num?)?.toInt() ?? 5,
        profileFeeInr: j['profile_fee_inr'] as num?,
        paymentProvider: '${j['payment_provider'] ?? 'mock'}',
        unlock: UnlockChecklist.fromJson(j['unlock'] as Map<String, dynamic>?),
      );

  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
}
