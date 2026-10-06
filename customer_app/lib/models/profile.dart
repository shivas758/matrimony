import 'package:intl/intl.dart';

import '../services/api_client.dart';
import 'master_data.dart';

/// Whether the on-request fields were included. Customers get 'granted' for
/// their own profile and while an accepted interest is unexpired (SPEC §9.4).
enum ContactAccess { none, pending, granted }

enum ProfileStatus {
  active('active', 'Active'),
  engaged('engaged', 'Engaged'),
  married('married', 'Married'),
  hidden('hidden', 'Hidden'),
  onHold('on_hold', 'On hold');

  const ProfileStatus(this.apiValue, this.label);

  /// The `status` value on the wire.
  final String apiValue;

  /// What the customer reads on a chip.
  final String label;

  static ProfileStatus fromApi(String? s) =>
      values.firstWhere((v) => v.apiValue == s, orElse: () => ProfileStatus.active);
}

/// Where one of MY profiles stands with the fee and approval (SPEC §9.12).
enum ProfileVisibility {
  paymentPending('payment_pending'),
  awaitingApproval('awaiting_approval'),
  live('live'),
  hidden('hidden');

  const ProfileVisibility(this.apiValue);

  final String apiValue;

  /// Null for anything unknown (or absent — other people's profiles).
  static ProfileVisibility? fromApi(String? s) {
    for (final v in values) {
      if (v.apiValue == s) return v;
    }
    return null;
  }
}

/// A request to delete one of my PAID profiles — the agent decides
/// (SPEC §9.13). Own-profile views carry the pending one as `delete_request`;
/// the create / cancel routes return the full row.
class DeleteRequest {
  const DeleteRequest({
    required this.id,
    required this.status,
    this.reason,
    this.createdAt,
    this.decidedAt,
    this.profileName,
    this.profileId,
  });

  final int id;

  /// 'pending' | 'approved' | 'rejected' | 'cancelled'
  final String status;
  final String? reason;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String? profileName;
  final int? profileId;

  bool get isPending => status == 'pending';

  static DeleteRequest? tryParse(dynamic j) =>
      j is Map<String, dynamic> ? DeleteRequest.fromJson(j) : null;

  factory DeleteRequest.fromJson(Map<String, dynamic> j) => DeleteRequest(
        id: (j['id'] as num).toInt(),
        status: '${j['status'] ?? 'pending'}',
        reason: j['reason'] as String?,
        createdAt: Profile._date(j['created_at']),
        decidedAt: Profile._date(j['decided_at']),
        profileName: j['profile_name'] as String?,
        profileId: (j['profile_id'] as num?)?.toInt(),
      );
}

/// The registration form's education table (SPEC §9.7) — one row per level.
enum EducationLevel {
  below10th('below_10th', 'Below 10th'),
  tenth('10th', '10th'),
  intermediate('intermediate', 'Intermediate / 12th'),
  graduation('graduation', 'Graduation'),
  postGraduation('post_graduation', 'Post graduation');

  const EducationLevel(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static EducationLevel? fromApi(String? s) {
    for (final v in values) {
      if (v.apiValue == s) return v;
    }
    return null;
  }
}

/// `education_levels[{level, details, country:{id,name}|null}]` on reads;
/// `{level, details?, country_id?}` on writes.
class EducationLevelEntry {
  const EducationLevelEntry({required this.level, this.details, this.country});

  final EducationLevel level;
  final String? details;
  final MasterItem? country;

  /// "Graduation — B.Tech, JNTU (India)"; the label alone when nothing else.
  String get line {
    final parts = [details, country == null ? null : '(${country!.name})']
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    return parts.isEmpty ? level.label : '${level.label} — $parts';
  }

  static EducationLevelEntry? fromJson(Map<String, dynamic> j) {
    final level = EducationLevel.fromApi(j['level'] as String?);
    if (level == null) return null;
    return EducationLevelEntry(
      level: level,
      details: j['details'] as String?,
      country: j['country'] == null ? null : MasterItem.fromJson(j['country'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'level': level.apiValue,
        if (details != null && details!.isNotEmpty) 'details': details,
        if (country != null) 'country_id': country!.id,
      };
}

class ProfilePhoto {
  const ProfilePhoto({required this.id, required this.url, required this.isPrimary});

  final int id;
  final String url;
  final bool isPrimary;

  /// Absolute, authenticated URL for [AuthedPhoto] / CachedNetworkImage.
  String get absoluteUrl => ApiClient.absoluteUrl(url);

  factory ProfilePhoto.fromJson(Map<String, dynamic> j) => ProfilePhoto(
        id: (j['id'] as num).toInt(),
        url: '${j['url']}',
        isPrimary: j['is_primary'] == true,
      );
}

/// Compact profile embedded in interest rows (SPEC §9.9 `profile: {summary}`).
class ProfileSummary {
  const ProfileSummary({
    required this.id,
    required this.fullName,
    required this.gender,
    this.age,
    this.community,
    this.subcaste,
    this.status,
    this.photoUrl,
    this.paid = false,
    this.paidAt,
    this.visibility,
    this.deleteRequestId,
  });

  final int id;
  final String fullName;
  final String gender;
  final int? age;
  final MasterItem? community;
  final MasterItem? subcaste;
  final String? status;

  /// My own profiles only (`/customer/auth/me` → profiles[]): fee state.
  final bool paid;
  final DateTime? paidAt;
  final ProfileVisibility? visibility;

  /// My pending deletion request on it, when the server says (SPEC §9.13).
  final int? deleteRequestId;

  /// Server-relative, e.g. `/api/customer/photos/12`; null when no photo.
  final String? photoUrl;

  String? get absolutePhotoUrl => photoUrl == null ? null : ApiClient.absoluteUrl(photoUrl!);

  String? get communityLine {
    final parts = [community?.name, subcaste?.name].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  factory ProfileSummary.fromJson(Map<String, dynamic> j) => ProfileSummary(
        id: (j['id'] as num).toInt(),
        fullName: '${j['full_name'] ?? ''}',
        gender: '${j['gender'] ?? ''}',
        age: (j['age'] as num?)?.toInt(),
        community: Profile._ref(j['community']),
        subcaste: Profile._ref(j['subcaste']),
        status: j['status'] as String?,
        photoUrl: j['photo_url'] as String?,
        paid: j['paid'] == true || j['paid_at'] != null,
        paidAt: Profile._date(j['paid_at']),
        visibility: ProfileVisibility.fromApi(j['visibility'] as String?),
        deleteRequestId: (j['delete_request_id'] as num?)?.toInt() ??
            (j['delete_request'] is Map ? ((j['delete_request'] as Map)['id'] as num?)?.toInt() : null),
      );
}

/// My interest in a profile (SPEC §9.4). On the detail route it is the
/// `interest` object; GET /customer/interests rows also carry `profile`.
class Interest {
  const Interest({
    required this.id,
    required this.status,
    this.note,
    this.createdAt,
    this.decidedAt,
    this.accessExpiresAt,
    this.daysLeft,
    this.profile,
    this.fromProfile,
  });

  final int id;

  /// 'pending' | 'accepted' | 'declined' | 'withdrawn' | 'revoked' | 'expired'
  /// ('expired' = accepted but the access window lapsed).
  final String status;
  final String? note;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final DateTime? accessExpiresAt;

  /// Whole days of on-request access left; null unless accepted and live.
  final int? daysLeft;
  final ProfileSummary? profile;

  /// Which of MY profiles is interested (SPEC §9.12); null on old rows.
  final ProfileSummary? fromProfile;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';
  bool get isWithdrawn => status == 'withdrawn';
  bool get isRevoked => status == 'revoked';
  bool get isExpired => status == 'expired';

  /// Accepted and still inside the access window.
  bool get isLive => isAccepted && (daysLeft ?? 0) > 0;

  /// A customer can express interest again after these (SPEC §9.4).
  bool get canReExpress => isDeclined || isWithdrawn || isRevoked || isExpired;

  factory Interest.fromJson(Map<String, dynamic> j) => Interest(
        id: (j['id'] as num).toInt(),
        status: '${j['status'] ?? 'pending'}',
        note: j['note'] as String?,
        createdAt: Profile._date(j['created_at']),
        decidedAt: Profile._date(j['decided_at']),
        accessExpiresAt: Profile._date(j['access_expires_at']),
        daysLeft: (j['days_left'] as num?)?.toInt(),
        profile: j['profile'] == null ? null : ProfileSummary.fromJson(j['profile'] as Map<String, dynamic>),
        fromProfile: j['from_profile'] == null
            ? null
            : ProfileSummary.fromJson(j['from_profile'] as Map<String, dynamic>),
      );
}

/// A profile as the customer routes return it (SPEC §9.8 / §9.9).
///
/// PUBLIC fields are always present. PROTECTED ("on request") fields are
/// OMITTED by the server unless access is granted — never assume they are
/// there: check [detailsShared] before showing the personal-details card.
class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.gender,
    required this.status,
    this.dob,
    this.age,
    this.heightCm,
    this.weightKg,
    this.complexion,
    this.religion,
    this.community,
    this.subcaste,
    this.gothram,
    this.motherTongue,
    this.knownLanguages = const [],
    this.foodHabit,
    this.nationality,
    this.education,
    this.educationDetails,
    this.educationLevels = const [],
    this.profession,
    this.professionDetails,
    this.occupationType,
    this.workCountry,
    this.maritalStatus,
    this.zodiac,
    this.nakshatram,
    this.birthTime,
    this.incomeText,
    this.otherIncome,
    this.isNri = false,
    this.nriCountry,
    this.about,
    this.isCustomerProfile = false,
    this.photos = const [],
    this.primaryPhotoPath,
    this.isMine = false,
    this.createdAt,
    this.updatedAt,
    this.contactAccess = ContactAccess.none,
    this.contactExpiresAt,
    this.hasProtectedFields = false,
    this.interest,
    this.listInterestStatus,
    this.listIsInterested = false,
    this.locked = false,
    this.paid = false,
    this.paidAt,
    this.visibility,
    this.profileFeeInr,
    this.deleteRequest,
    // ---- protected
    this.city,
    this.state,
    this.birthPlace,
    this.birthState,
    this.birthCountry,
    this.workPlace,
    this.nriPlace,
    this.fatherName,
    this.fatherOccupation,
    this.fatherPhone,
    this.motherName,
    this.motherOccupation,
    this.motherPhone,
    this.contactName,
    this.contactPhone,
    this.hasSiblings,
    this.siblingsCount,
    this.siblingsDetails,
    this.elderSisters,
    this.youngerSisters,
    this.elderBrothers,
    this.youngerBrothers,
    this.familyDetails,
    this.propertyShare,
    this.propertyDetails,
  });

  // ---- public ("appearance profile")
  final int id;
  final String fullName;
  final String gender; // 'bride' | 'groom'
  final ProfileStatus status;
  final DateTime? dob;
  final int? age;
  final int? heightCm;
  final int? weightKg;
  final MasterItem? complexion;
  final MasterItem? religion;
  final MasterItem? community;
  final MasterItem? subcaste;
  final String? gothram;
  final MasterItem? motherTongue;

  /// Languages the person knows (M:N on the server). Mother tongue is separate.
  final List<MasterItem> knownLanguages;
  final MasterItem? foodHabit;
  final MasterItem? nationality;

  /// Highest qualification + free text, and the per-level table.
  final MasterItem? education;
  final String? educationDetails;
  final List<EducationLevelEntry> educationLevels;
  final MasterItem? profession;
  final String? professionDetails;
  final MasterItem? occupationType;

  /// Public coarse location: the country of work. The exact place is protected.
  final MasterItem? workCountry;
  final MasterItem? maritalStatus;
  final ZodiacSign? zodiac;
  final MasterItem? nakshatram;

  /// Horoscope birth time — public like star/rasi. "HH:MM" 24-hour.
  final String? birthTime;
  final String? incomeText;
  final String? otherIncome;
  final bool isNri;
  final MasterItem? nriCountry;
  final String? about;

  /// Owned by a Gandharva customer (vs. uploaded by an agent).
  final bool isCustomerProfile;
  final List<ProfilePhoto> photos;

  /// `primary_photo_url` as sent (server-relative); falls back to photos[0].
  final String? primaryPhotoPath;
  final bool isMine;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ---- access state
  final ContactAccess contactAccess;
  final DateTime? contactExpiresAt;

  /// True when the JSON carried any protected key — the server only sends
  /// them once access is granted, so this is the reliable signal.
  final bool hasProtectedFields;

  /// Detail route: my interest in this profile (null = never expressed).
  final Interest? interest;

  /// List rows: `interest_status` / `is_interested` (my latest).
  final String? listInterestStatus;
  final bool listIsInterested;

  /// Guest browse rows (SPEC §9.12): only photo, age, job, caste and package
  /// are present — no name. Tapping one leads to Get started.
  final bool locked;

  // ---- my own profiles only (GET /customer/my-profiles/:id)
  final bool paid;
  final DateTime? paidAt;
  final ProfileVisibility? visibility;
  final num? profileFeeInr;

  /// The pending deletion request on this (paid) profile of mine, if any.
  final DeleteRequest? deleteRequest;

  // ---- protected ("on request") — present only when access is granted
  final String? city;
  final String? state;
  final String? birthPlace;
  final String? birthState;
  final MasterItem? birthCountry;
  final String? workPlace;
  final String? nriPlace;
  final String? fatherName;
  final String? fatherOccupation;
  final String? fatherPhone;
  final String? motherName;
  final String? motherOccupation;
  final String? motherPhone;
  final String? contactName;
  final String? contactPhone;

  /// Siblings: null = not recorded, false = none, true = see counts/details.
  final bool? hasSiblings;
  final int? siblingsCount;
  final String? siblingsDetails;
  final int? elderSisters;
  final int? youngerSisters;
  final int? elderBrothers;
  final int? youngerBrothers;
  final String? familyDetails;
  final String? propertyShare;
  final String? propertyDetails;

  bool get isBride => gender == 'bride';

  /// Job for the guest card: profession, else occupation type.
  String? get jobLabel => profession?.name ?? occupationType?.name;
  String get genderLabel => isBride ? 'Bride' : 'Groom';

  /// The on-request block is available (own profile, or a live accepted interest).
  bool get detailsShared =>
      isMine || hasProtectedFields || contactAccess == ContactAccess.granted || (interest?.isLive ?? false);

  /// My latest interest status on this profile, from either route.
  String? get interestStatus => interest?.status ?? listInterestStatus;

  /// Pending or accepted — the "I'm interested" button becomes a state banner.
  bool get isInterested =>
      listIsInterested || (interest != null && (interest!.isPending || interest!.isAccepted));

  /// Whole days until the shared details lapse; null when not shared.
  int? get accessDaysLeft {
    if (interest?.daysLeft != null) return interest!.daysLeft;
    final exp = contactExpiresAt ?? interest?.accessExpiresAt;
    if (exp == null) return null;
    final diff = exp.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inHours ~/ 24 + (diff.inHours % 24 > 0 ? 1 : 0);
  }

  /// "12 Apr 1998" — the date of birth as families quote it.
  String? get dobLabel => dob == null ? null : DateFormat('d MMM yyyy').format(dob!.toLocal());

  /// "27 yrs (12 Apr 1998)" — the short profile line.
  String? get ageDobLine {
    if (age == null) return null;
    final d = dobLabel;
    return d == null ? '$age yrs' : '$age yrs ($d)';
  }

  /// "10:40 PM" from the API's "22:40"; null when not recorded.
  String? get birthTimeLabel {
    final t = birthTime;
    if (t == null || t.isEmpty) return null;
    final parts = t.split(':');
    final h = parts.length >= 2 ? int.tryParse(parts[0]) : null;
    if (h == null) return t;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${parts[1]} ${h < 12 ? 'AM' : 'PM'}';
  }

  /// "Telugu, Hindi, English"; null when none recorded.
  String? get knownLanguagesLabel =>
      knownLanguages.isEmpty ? null : knownLanguages.map((l) => l.name).join(', ');

  /// "None" / "2" / "Yes"; null when not recorded.
  String? get siblingsLabel {
    if (hasSiblings == null) return null;
    if (hasSiblings == false) return 'None';
    final n = siblingsCount;
    return n != null && n > 0 ? '$n' : 'Yes';
  }

  /// "1 elder sister, 2 younger brothers"; null when nothing recorded.
  String? get siblingsBreakdown {
    if (hasSiblings != true) return null;
    String? part(int? n, String one, String many) =>
        n == null || n == 0 ? null : '$n ${n == 1 ? one : many}';
    final parts = [
      part(elderSisters, 'elder sister', 'elder sisters'),
      part(youngerSisters, 'younger sister', 'younger sisters'),
      part(elderBrothers, 'elder brother', 'elder brothers'),
      part(youngerBrothers, 'younger brother', 'younger brothers'),
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// "Nalgonda, Telangana" — PROTECTED; only present with access.
  String? get nativePlace => _joinPlaces([city, state]);

  /// "Guntur, Andhra Pradesh, India" — PROTECTED.
  String? get birthPlaceLine => _joinPlaces([birthPlace, birthState, birthCountry?.name]);

  /// "United States · California" for NRI profiles (place only with access);
  /// null otherwise.
  String? get nriLabel {
    if (!isNri) return null;
    final parts = [nriCountry?.name, nriPlace].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isEmpty ? 'NRI' : parts.join(' · ');
  }

  /// What list cards show as the location: NRI country, else work country.
  String? get placeLine => nriLabel ?? workCountry?.name;

  /// "Kamma · Chowdary" for list cards; just the community when no subcaste.
  String? get communityLine {
    final parts = [community?.name, subcaste?.name].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// "B.Tech / B.E. — CSE, JNTU 2018"; either half alone when the other is empty.
  String? get educationLine => _withDetails(education?.name, educationDetails);
  String? get professionLine => _withDetails(profession?.name, professionDetails);

  /// "Private job — Software engineer, Infosys".
  String? get occupationLine => _withDetails(occupationType?.name, professionDetails);

  static String? _withDetails(String? name, String? details) {
    final parts = [name, details].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' — ');
  }

  static String? _joinPlaces(List<String?> items) {
    final parts = items.where((s) => s != null && s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// 160 cm → "5' 3\"" — how families talk about height.
  static String feetInches(int cm) {
    final inches = (cm / 2.54).round();
    return '${inches ~/ 12}\' ${inches % 12}"';
  }

  /// "5' 3\" (160 cm)" for detail screens.
  String? get heightLabel => heightCm == null ? null : '${feetInches(heightCm!)} ($heightCm cm)';

  /// "5'3\"" for the compact list card.
  String? get heightShort => heightCm == null ? null : feetInches(heightCm!).replaceAll(' ', '');

  String? get weightLabel => weightKg == null ? null : '$weightKg kg';

  String? get starRasi {
    final parts = [nakshatram?.name, zodiac?.label].where((s) => s != null && s.isNotEmpty);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? get primaryPhotoUrl {
    if (primaryPhotoPath != null && primaryPhotoPath!.isNotEmpty) {
      return ApiClient.absoluteUrl(primaryPhotoPath!);
    }
    return photos.isEmpty ? null : photos.first.absoluteUrl;
  }

  /// Anything at all in the protected block — decides whether the shared
  /// details card shows values or a "nothing recorded" note.
  bool get hasPersonalDetails => [
        nativePlace, birthPlaceLine, workPlace, nriPlace, fatherName, fatherOccupation, fatherPhone,
        motherName, motherOccupation, motherPhone, contactName, contactPhone, siblingsLabel,
        siblingsDetails, familyDetails, propertyShare, propertyDetails,
      ].any((s) => s != null && s.isNotEmpty);

  /// The API keys the server omits until access is granted (PROTECTED_FIELDS
  /// in backend/src/lib/profiles.js).
  static const protectedKeys = [
    'city', 'state', 'birth_place', 'birth_state', 'birth_country', 'work_place', 'nri_place',
    'father_name', 'father_occupation', 'father_phone', 'mother_name', 'mother_occupation',
    'mother_phone', 'contact_name', 'contact_phone', 'has_siblings', 'siblings_count',
    'siblings_details', 'elder_sisters', 'younger_sisters', 'elder_brothers', 'younger_brothers',
    'family_details', 'property_share', 'property_details',
  ];

  static ContactAccess _access(String? s) => switch (s) {
        'granted' => ContactAccess.granted,
        'pending' => ContactAccess.pending,
        _ => ContactAccess.none,
      };

  static MasterItem? _ref(dynamic j) =>
      j == null ? null : MasterItem.fromJson(j as Map<String, dynamic>);

  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

  static int? _int(dynamic v) => (v as num?)?.toInt();

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: (j['id'] as num).toInt(),
        // Guest rows carry no name (SPEC §9.12).
        fullName: '${j['full_name'] ?? ''}',
        gender: '${j['gender'] ?? ''}',
        status: ProfileStatus.fromApi(j['status'] as String?),
        dob: j['dob'] == null ? null : DateTime.tryParse('${j['dob']}'),
        age: _int(j['age']),
        heightCm: _int(j['height_cm']),
        weightKg: _int(j['weight_kg']),
        complexion: _ref(j['complexion']),
        religion: _ref(j['religion']),
        community: _ref(j['community']),
        subcaste: _ref(j['subcaste']),
        gothram: j['gothram'] as String?,
        motherTongue: _ref(j['mother_tongue']),
        knownLanguages: (j['known_languages'] as List? ?? [])
            .map((e) => MasterItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        foodHabit: _ref(j['food_habit']),
        nationality: _ref(j['nationality']),
        education: _ref(j['education']),
        educationDetails: j['education_details'] as String?,
        educationLevels: (j['education_levels'] as List? ?? [])
            .map((e) => EducationLevelEntry.fromJson(e as Map<String, dynamic>))
            .whereType<EducationLevelEntry>()
            .toList(),
        profession: _ref(j['profession']),
        professionDetails: j['profession_details'] as String?,
        occupationType: _ref(j['occupation_type']),
        workCountry: _ref(j['work_country']),
        maritalStatus: _ref(j['marital_status']),
        zodiac: j['zodiac'] == null ? null : ZodiacSign.fromJson(j['zodiac'] as Map<String, dynamic>),
        nakshatram: _ref(j['nakshatram']),
        birthTime: j['birth_time'] as String?,
        incomeText: j['income_text'] as String?,
        otherIncome: j['other_income'] as String?,
        isNri: j['is_nri'] == true,
        nriCountry: _ref(j['nri_country']),
        about: j['about'] as String?,
        isCustomerProfile: j['is_customer_profile'] == true,
        photos: (j['photos'] as List? ?? [])
            .map((e) => ProfilePhoto.fromJson(e as Map<String, dynamic>))
            .toList(),
        primaryPhotoPath: j['primary_photo_url'] as String?,
        isMine: j['is_mine'] == true,
        createdAt: _date(j['created_at']),
        updatedAt: _date(j['updated_at']),
        contactAccess: _access((j['contact_access'] ?? j['access']) as String?),
        contactExpiresAt: _date(j['contact_expires_at']),
        hasProtectedFields: protectedKeys.any(j.containsKey),
        interest: j['interest'] == null ? null : Interest.fromJson(j['interest'] as Map<String, dynamic>),
        listInterestStatus: j['interest_status'] as String?,
        listIsInterested: j['is_interested'] == true,
        locked: j['locked'] == true,
        paid: j['paid'] == true || j['paid_at'] != null,
        paidAt: _date(j['paid_at']),
        visibility: ProfileVisibility.fromApi(j['visibility'] as String?),
        profileFeeInr: j['profile_fee_inr'] as num?,
        deleteRequest: DeleteRequest.tryParse(j['delete_request']),
        // protected
        city: j['city'] as String?,
        state: j['state'] as String?,
        birthPlace: j['birth_place'] as String?,
        birthState: j['birth_state'] as String?,
        birthCountry: _ref(j['birth_country']),
        workPlace: j['work_place'] as String?,
        nriPlace: j['nri_place'] as String?,
        fatherName: j['father_name'] as String?,
        fatherOccupation: j['father_occupation'] as String?,
        fatherPhone: j['father_phone'] as String?,
        motherName: j['mother_name'] as String?,
        motherOccupation: j['mother_occupation'] as String?,
        motherPhone: j['mother_phone'] as String?,
        contactName: j['contact_name'] as String?,
        contactPhone: j['contact_phone'] as String?,
        hasSiblings: j['has_siblings'] as bool?,
        siblingsCount: _int(j['siblings_count']),
        siblingsDetails: j['siblings_details'] as String?,
        elderSisters: _int(j['elder_sisters']),
        youngerSisters: _int(j['younger_sisters']),
        elderBrothers: _int(j['elder_brothers']),
        youngerBrothers: _int(j['younger_brothers']),
        familyDetails: j['family_details'] as String?,
        propertyShare: j['property_share'] as String?,
        propertyDetails: j['property_details'] as String?,
      );
}

class ProfilePage {
  const ProfilePage({
    required this.profiles,
    required this.total,
    required this.page,
    this.access = 'full',
    this.gender,
  });

  final List<Profile> profiles;
  final int total;
  final int page;

  /// 'guest' → locked teaser cards; 'full' → normal cards (SPEC §9.12).
  final String access;

  /// The gender the server filtered on (its default when I sent none).
  final String? gender;

  bool get isGuest => access != 'full';

  factory ProfilePage.fromJson(Map<String, dynamic> j) => ProfilePage(
        profiles: (j['profiles'] as List? ?? [])
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 1,
        access: j['access'] == 'guest' ? 'guest' : 'full',
        gender: j['gender'] as String?,
      );
}
