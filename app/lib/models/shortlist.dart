import '../services/api_client.dart';

class ShortlistEntry {
  const ShortlistEntry({
    required this.shortlistId,
    required this.profileId,
    required this.fullName,
    required this.gender,
    required this.status,
    this.age,
    this.workCountry,
    this.nriCountry,
    this.community,
    this.photoUrl,
  });

  final int shortlistId;
  final int profileId;
  final String fullName;
  final String gender;
  final String status;
  final int? age;

  /// Public coarse location only (SPEC §9.8): the country of work and, for
  /// NRI profiles, the country abroad. The native place is never sent here.
  final String? workCountry;
  final String? nriCountry;
  final String? community;
  final String? photoUrl;

  String? get photoAbsoluteUrl => photoUrl == null ? null : ApiClient.absoluteUrl(photoUrl!);

  /// "United States" for NRI profiles, else the work country when it is not India.
  String? get placeLine {
    if ((nriCountry ?? '').isNotEmpty) return nriCountry;
    final w = workCountry ?? '';
    return w.isEmpty || w.toLowerCase() == 'india' ? null : w;
  }

  factory ShortlistEntry.fromJson(Map<String, dynamic> j) => ShortlistEntry(
        shortlistId: j['shortlist_id'] as int,
        profileId: j['profile_id'] as int,
        fullName: '${j['full_name']}',
        gender: '${j['gender']}',
        status: '${j['status']}',
        age: (j['age'] as num?)?.toInt(),
        workCountry: j['work_country'] as String?,
        nriCountry: j['nri_country'] as String?,
        community: j['community'] as String?,
        photoUrl: j['photo_url'] as String?,
      );
}

class ShortlistGroup {
  const ShortlistGroup({required this.clientLabel, required this.profiles});

  final String clientLabel;
  final List<ShortlistEntry> profiles;

  /// Entries saved without a label land in one shared bucket.
  String get displayLabel => clientLabel.isEmpty ? 'Unlabelled' : clientLabel;

  factory ShortlistGroup.fromJson(Map<String, dynamic> j) => ShortlistGroup(
        clientLabel: '${j['client_label'] ?? ''}',
        profiles: (j['profiles'] as List? ?? [])
            .map((e) => ShortlistEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
