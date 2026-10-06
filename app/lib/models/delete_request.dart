import 'customer.dart';

/// The customer on a profile delete request. `phone` for their own agent or
/// an admin — the only people who see these requests.
class DeleteRequestCustomer {
  const DeleteRequestCustomer({
    required this.id,
    required this.fullName,
    this.phone,
    this.agentId,
  });

  final int id;
  final String fullName;
  final String? phone;
  final int? agentId;

  factory DeleteRequestCustomer.fromJson(Map<String, dynamic> j) => DeleteRequestCustomer(
        id: (j['id'] as num?)?.toInt() ?? 0,
        fullName: '${j['full_name'] ?? ''}',
        phone: j['phone'] as String?,
        agentId: (j['agent_id'] as num?)?.toInt(),
      );
}

/// A customer asking to delete one of their PAID profiles (SPEC §9.13).
/// The customer's agent (or an admin) approves — the profile is then deleted
/// for good — or rejects it.
class ProfileDeleteRequest {
  const ProfileDeleteRequest({
    required this.id,
    required this.status,
    required this.profileName,
    required this.customer,
    this.reason,
    this.profileId,
    this.profile,
    this.createdAt,
    this.decidedAt,
    this.canDecide = false,
  });

  final int id;

  /// pending | approved | rejected | cancelled
  final String status;
  final String? reason;

  /// Kept on the request, so it still reads right after the profile is gone.
  final String profileName;
  final int? profileId;

  /// Null once the profile has been deleted.
  final ProfileSummary? profile;
  final DeleteRequestCustomer customer;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final bool canDecide;

  bool get isPending => status == 'pending';

  String get statusLabel => switch (status) {
        'pending' => 'Waiting for you',
        'approved' => 'Deleted',
        'rejected' => 'Rejected',
        'cancelled' => 'Cancelled',
        _ => status,
      };

  factory ProfileDeleteRequest.fromJson(Map<String, dynamic> j) {
    final profile = ProfileSummary.fromJsonOrNull(j['profile']);
    return ProfileDeleteRequest(
      id: (j['id'] as num).toInt(),
      status: '${j['status'] ?? 'pending'}',
      reason: j['reason'] as String?,
      profileName: '${j['profile_name'] ?? profile?.fullName ?? ''}',
      profileId: (j['profile_id'] as num?)?.toInt() ?? profile?.id,
      profile: profile,
      customer: DeleteRequestCustomer.fromJson(j['customer'] as Map<String, dynamic>? ?? const {}),
      createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal(),
      decidedAt: DateTime.tryParse('${j['decided_at']}')?.toLocal(),
      canDecide: j['can_decide'] == true,
    );
  }
}
