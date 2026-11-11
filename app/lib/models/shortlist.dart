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
    this.nameHidden = false,
  });

  final int shortlistId;
  final int profileId;

  /// The name, or the neutral "Profile 1042" when [nameHidden] (SPEC §9.18 D).
  final String fullName;

  /// The family hides the name and I have no access to it.
  final bool nameHidden;
  final String gender;
  final String status;
  final int? age;

  /// Public coarse location only (SPEC §9.8): the country of work and, for
  /// NRI profiles, the country abroad. The native place is never sent here.
  final String? workCountry;
  final String? nriCountry;

  /// Null when not recorded or hidden by the family.
  final String? community;
  final String? photoUrl;

  String? get photoAbsoluteUrl => photoUrl == null ? null : ApiClient.absoluteUrl(photoUrl!);

  /// "United States" for NRI profiles, else the work country when it is not India.
  String? get placeLine {
    if ((nriCountry ?? '').isNotEmpty) return nriCountry;
    final w = workCountry ?? '';
    return w.isEmpty || w.toLowerCase() == 'india' ? null : w;
  }

  /// A plain string, or the `name` of a `{id, name}` object; null otherwise.
  static String? _text(Object? v) {
    if (v is Map) return v['name'] as String?;
    return v is String && v.isNotEmpty ? v : null;
  }

  factory ShortlistEntry.fromJson(Map<String, dynamic> j) {
    final profileId = (j['profile_id'] as num).toInt();
    final name = j['full_name'];
    return ShortlistEntry(
      shortlistId: (j['shortlist_id'] as num).toInt(),
      profileId: profileId,
      fullName: name is String && name.trim().isNotEmpty ? name : 'Profile $profileId',
      gender: '${j['gender'] ?? ''}',
      status: '${j['status'] ?? 'active'}',
      age: (j['age'] as num?)?.toInt(),
      workCountry: _text(j['work_country']),
      nriCountry: _text(j['nri_country']),
      community: _text(j['community']),
      photoUrl: j['photo_url'] as String?,
      nameHidden: j['name_hidden'] == true,
    );
  }
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
