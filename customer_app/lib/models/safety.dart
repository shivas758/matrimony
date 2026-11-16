/// Reporting and blocking profiles (SPEC §9.22 A / B — Google Play's
/// user-generated-content policy).
library;

/// Why a profile is reported; [apiValue] is the `reason` on the wire. The
/// words people read are `S.reportReasonLabel`.
enum ReportReason {
  fakeProfile('fake_profile'),
  inappropriatePhoto('inappropriate_photo'),
  offensiveContent('offensive_content'),
  scamOrFraud('scam_or_fraud'),
  harassment('harassment'),
  other('other');

  const ReportReason(this.apiValue);

  final String apiValue;
}

/// One row of GET /customer/blocks: `{profile_id, profile_label, created_at}`.
/// [label] is the name as I saw it when I blocked it (the profile itself is
/// hidden from me now).
class BlockedProfile {
  const BlockedProfile({required this.profileId, required this.label, this.createdAt});

  final int profileId;
  final String label;
  final DateTime? createdAt;

  /// Never an empty title.
  String get displayLabel => label.trim().isEmpty ? 'Profile $profileId' : label;

  factory BlockedProfile.fromJson(Map<String, dynamic> j) => BlockedProfile(
        profileId: (j['profile_id'] as num).toInt(),
        label: '${j['profile_label'] ?? ''}',
        createdAt: j['created_at'] == null ? null : DateTime.tryParse('${j['created_at']}')?.toLocal(),
      );
}
