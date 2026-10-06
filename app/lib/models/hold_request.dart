import '../services/api_client.dart';

/// A request to put a profile on hold (SPEC §2 hold_requests). Any agent can
/// ask; the uploader or an admin decides; the holder, uploader or an admin
/// releases. Rows are also the hold log, so decided ones stay listed.
class HoldRequest {
  const HoldRequest({
    required this.id,
    required this.profileId,
    required this.profileName,
    required this.status,
    this.profileGender,
    this.profileCommunity,
    this.profileStatus,
    this.profilePhotoUrl,
    this.note,
    this.requestedAt,
    this.decidedAt,
    this.releasedAt,
    this.isMine = false,
    this.requesterName,
    this.requesterAgency,
    this.requesterPhone,
  });

  final int id;
  final int profileId;
  final String profileName;

  /// 'pending' | 'approved' | 'rejected' | 'cancelled' | 'released'
  final String status;
  final String? profileGender;
  final String? profileCommunity;
  final String? profileStatus;
  final String? profilePhotoUrl;
  final String? note;
  final DateTime? requestedAt;
  final DateTime? decidedAt;
  final DateTime? releasedAt;

  /// I asked for this hold.
  final bool isMine;

  /// Only present in the inbox — the sent box never reveals the uploader.
  final String? requesterName;
  final String? requesterAgency;
  final String? requesterPhone;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  String? get genderLabel => switch (profileGender) {
        'bride' => 'Bride',
        'groom' => 'Groom',
        _ => profileGender,
      };
  String? get photoAbsoluteUrl =>
      profilePhotoUrl == null ? null : ApiClient.absoluteUrl(profilePhotoUrl!);

  String get statusLabel => switch (status) {
        'pending' => 'Hold requested — waiting for approval',
        'approved' => 'On hold',
        'rejected' => 'Hold rejected',
        'cancelled' => 'Hold request cancelled',
        'released' => 'Hold released',
        _ => status,
      };

  factory HoldRequest.fromJson(Map<String, dynamic> j) {
    final requester = j['requester'] as Map<String, dynamic>?;
    return HoldRequest(
      id: j['id'] as int,
      profileId: j['profile_id'] as int,
      profileName: '${j['profile_name'] ?? ''}',
      status: '${j['status']}',
      profileGender: j['profile_gender'] as String?,
      profileCommunity: j['profile_community'] as String?,
      profileStatus: j['profile_status'] as String?,
      profilePhotoUrl: j['profile_photo_url'] as String?,
      note: j['note'] as String?,
      requestedAt: DateTime.tryParse('${j['requested_at']}')?.toLocal(),
      decidedAt: DateTime.tryParse('${j['decided_at']}')?.toLocal(),
      releasedAt: DateTime.tryParse('${j['released_at']}')?.toLocal(),
      isMine: j['is_mine'] == true,
      requesterName: requester?['full_name'] as String?,
      requesterAgency: requester?['agency_name'] as String?,
      requesterPhone: requester?['phone'] as String?,
    );
  }
}
