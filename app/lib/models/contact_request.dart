import '../services/api_client.dart';

enum RequestBox { inbox, sent }

class ContactRequest {
  const ContactRequest({
    required this.id,
    required this.profileId,
    required this.profileName,
    required this.status,
    this.profileGender,
    this.profileCommunity,
    this.profilePhotoUrl,
    this.note,
    this.requestedAt,
    this.decidedAt,
    this.expiresAt,
    this.daysLeft,
    this.requesterName,
    this.requesterAgency,
    this.requesterPhone,
  });

  final int id;
  final int profileId;
  final String profileName;

  /// 'pending' | 'approved' | 'rejected' | 'revoked' | 'expired'
  final String status;
  final String? profileGender;
  final String? profileCommunity;
  final String? profilePhotoUrl;
  final String? note;
  final DateTime? requestedAt;
  final DateTime? decidedAt;
  final DateTime? expiresAt;
  final int? daysLeft;

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
        'pending' => 'Waiting for approval',
        'approved' => daysLeft == null ? 'Approved' : 'Approved · $daysLeft days left',
        'rejected' => 'Rejected',
        'revoked' => 'Access revoked',
        'expired' => 'Access expired',
        _ => status,
      };

  factory ContactRequest.fromJson(Map<String, dynamic> j) {
    final requester = j['requester'] as Map<String, dynamic>?;
    return ContactRequest(
      id: j['id'] as int,
      profileId: j['profile_id'] as int,
      profileName: '${j['profile_name'] ?? ''}',
      status: '${j['status']}',
      profileGender: j['profile_gender'] as String?,
      profileCommunity: j['profile_community'] as String?,
      profilePhotoUrl: j['profile_photo_url'] as String?,
      note: j['note'] as String?,
      requestedAt: DateTime.tryParse('${j['requested_at']}')?.toLocal(),
      decidedAt: DateTime.tryParse('${j['decided_at']}')?.toLocal(),
      expiresAt: DateTime.tryParse('${j['expires_at']}')?.toLocal(),
      daysLeft: (j['days_left'] as num?)?.toInt(),
      requesterName: requester?['full_name'] as String?,
      requesterAgency: requester?['agency_name'] as String?,
      requesterPhone: requester?['phone'] as String?,
    );
  }
}
