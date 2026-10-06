import 'package:intl/intl.dart';

import '../services/api_client.dart';
import 'master_data.dart';

enum ContactAccess { none, pending, granted }

enum ProfileStatus {
  active('active', 'Active'),
  engaged('engaged', 'Engaged'),
  married('married', 'Married'),
  hidden('hidden', 'Hidden'),
  /// Talks in progress: hidden from other agents until released (SPEC §2).
  onHold('on_hold', 'On hold');

  const ProfileStatus(this.apiValue, this.label);

  /// The `status` value on the wire.
  final String apiValue;

  /// What agents read on chips and menus.
  final String label;

  static ProfileStatus fromApi(String? s) =>
      values.firstWhere((v) => v.apiValue == s, orElse: () => ProfileStatus.active);
}

/// One row of the registration form's education table (SPEC §9.7):
/// `education_levels[{level, details, country}]` on the wire. The five levels
/// are fixed; a profile carries only the rows that were filled in.
class EducationLevel {
  const EducationLevel({required this.level, this.details, this.country});

  /// below_10th | 10th | intermediate | graduation | post_graduation.
  final String level;

  /// School / college, branch, year — free text.
  final String? details;

  /// Where that level was studied; picked from the countries master.
  final MasterItem? country;

  /// Level values in the paper form's order.
  static const levels = ['below_10th', '10th', 'intermediate', 'graduation', 'post_graduation'];

  /// "Graduation" — the human label for an API level value.
  static String levelLabel(String level) => switch (level) {
        'below_10th' => 'Below 10th',
        '10th' => '10th',
        'intermediate' => 'Intermediate / 12th',
        'graduation' => 'Graduation',
        'post_graduation' => 'Post graduation',
        _ => level,
      };

  /// The human label for this row's level.
  String get label => levelLabel(level);

  /// "B.Tech, JNTU 2018 · India" — the details and country; null when both are empty.
  String? get valueLine {
    final parts = [details, country?.name].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Sort key: the position in [levels]; unknown levels go last.
  int get order {
    final i = levels.indexOf(level);
    return i < 0 ? levels.length : i;
  }

  factory EducationLevel.fromJson(Map<String, dynamic> j) => EducationLevel(
        level: '${j['level']}',
        details: j['details'] as String?,
        country: j['country'] == null ? null : MasterItem.fromJson(j['country'] as Map<String, dynamic>),
      );

  /// What the profile form sends: `{level, details, country_id}`.
  Map<String, dynamic> toJson() => {
        'level': level,
        'details': details,
        'country_id': country?.id,
      };
}

/// Who currently holds a profile — the server sends this only to the
/// uploader and admins, never to other agents.
class HeldBy {
  const HeldBy({
    required this.holdRequestId,
    required this.agentId,
    required this.fullName,
    this.agencyName,
    this.since,
  });

  final int holdRequestId;
  final int agentId;
  final String fullName;
  final String? agencyName;
  final DateTime? since;

  factory HeldBy.fromJson(Map<String, dynamic> j) => HeldBy(
        holdRequestId: (j['hold_request_id'] as num).toInt(),
        agentId: (j['id'] as num).toInt(),
        fullName: '${j['full_name'] ?? ''}',
        agencyName: j['agency_name'] as String?,
        since: DateTime.tryParse('${j['since']}')?.toLocal(),
      );
}

class ProfilePhoto {
  const ProfilePhoto({required this.id, required this.url, required this.isPrimary});

  final int id;
  final String url;
  final bool isPrimary;

  /// Absolute, authenticated URL for CachedNetworkImage.
  String get absoluteUrl => ApiClient.absoluteUrl(url);

  factory ProfilePhoto.fromJson(Map<String, dynamic> j) => ProfilePhoto(
        id: j['id'] as int,
        url: '${j['url']}',
        isPrimary: j['is_primary'] == true,
      );
}

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
    this.workPlace,
    this.maritalStatus,
    this.zodiac,
    this.nakshatram,
    this.birthTime,
    this.birthPlace,
    this.birthState,
    this.birthCountry,
    this.incomeText,
    this.otherIncome,
    this.isNri = false,
    this.nriCountry,
    this.nriPlace,
    this.hasSiblings,
    this.siblingsCount,
    this.siblingsDetails,
    this.elderSisters,
    this.youngerSisters,
    this.elderBrothers,
    this.youngerBrothers,
    this.about,
    this.familyDetails,
    this.propertyShare,
    this.propertyDetails,
    this.photos = const [],
    this.isMine = false,
    this.isCustomerProfile = false,
    this.canEdit = false,
    this.canDelete = false,
    this.holdRequestStatus,
    this.holdRequestId,
    this.heldBy,
    this.pendingHoldRequests = 0,
    this.contactAccess = ContactAccess.none,
    this.contactExpiresAt,
    this.contactRequestStatus,
    this.city,
    this.state,
    this.fatherName,
    this.fatherOccupation,
    this.fatherPhone,
    this.motherName,
    this.motherOccupation,
    this.motherPhone,
    this.contactName,
    this.contactPhone,
    this.createdAt,
  });

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

  /// From the countries master (SPEC §9.7). Public.
  final MasterItem? nationality;

  /// Highest qualification + "other education details". Public.
  final MasterItem? education;
  final String? educationDetails;

  /// The registration form's education table, in level order. Public.
  final List<EducationLevel> educationLevels;
  final MasterItem? profession;
  final String? professionDetails;

  /// Private job, Government job, Business … (SPEC §9.7). Public.
  final MasterItem? occupationType;

  /// The country of work — the PUBLIC coarse location (SPEC §9.8). India for
  /// most profiles; the exact [workPlace] is on request.
  final MasterItem? workCountry;

  /// PROTECTED since v2.1 (SPEC §9.8): the exact town / city of work. Absent
  /// from JSON unless contact access is granted; never in lists or shares.
  final String? workPlace;
  final MasterItem? maritalStatus;
  final ZodiacSign? zodiac;
  final MasterItem? nakshatram;

  /// Horoscope birth time — public like star/rasi. "HH:MM" 24-hour.
  final String? birthTime;

  /// PROTECTED (SPEC §9.8): birth place / state / country are on request.
  /// Absent from JSON unless contact access is granted.
  final String? birthPlace;
  final String? birthState;
  final MasterItem? birthCountry;
  final String? incomeText;

  /// "Other income" from the registration form (rent, farm …). Public.
  final String? otherIncome;
  final bool isNri;

  /// The NRI country — public like [workCountry].
  final MasterItem? nriCountry;

  /// PROTECTED (SPEC §9.8): the exact place abroad. Absent from JSON unless
  /// contact access is granted — never on cards or in shares.
  final String? nriPlace;

  /// Siblings — ALL PROTECTED since v2.1 (SPEC §9.8), absent from JSON unless
  /// access is granted. null = not recorded, false = none, true = see counts.
  final bool? hasSiblings;
  final int? siblingsCount;
  final String? siblingsDetails;

  /// PROTECTED: the registration form's breakdown (0–20 each).
  final int? elderSisters;
  final int? youngerSisters;
  final int? elderBrothers;
  final int? youngerBrothers;
  final String? about;

  /// PROTECTED since v2.1 (SPEC §9.8): family background is on request.
  final String? familyDetails;

  /// PROTECTED (SPEC §9.8): property share / details from the registration form.
  final String? propertyShare;
  final String? propertyDetails;
  final List<ProfilePhoto> photos;
  final bool isMine;

  /// Owned by a Gandharva customer account (SPEC §9.2).
  final bool isCustomerProfile;
  final bool canEdit;

  /// Uploader or admin (SPEC §4 DELETE /profiles/:id).
  final bool canDelete;

  /// Hold workflow (SPEC §2 hold_requests). My latest request on this profile:
  /// null | 'pending' | 'approved' | 'rejected' | 'cancelled' | 'released'.
  final String? holdRequestStatus;
  final int? holdRequestId;

  /// Uploader/admin only: who holds the profile now, and how many are waiting.
  final HeldBy? heldBy;
  final int pendingHoldRequests;

  /// Protected-field state (SPEC §3.2 / §9.8). The protected fields are
  /// OMITTED by the server unless access is granted — never assume they are
  /// present: native place (city/state), birth place/state/country, work
  /// place, NRI place, parents (names, occupations, phones), the contact
  /// person, every siblings field, family details and property.
  final ContactAccess contactAccess;
  final DateTime? contactExpiresAt;
  final String? contactRequestStatus;
  final String? city;
  final String? state;
  final String? fatherName;
  final String? fatherOccupation;
  final String? fatherPhone;
  final String? motherName;
  final String? motherOccupation;
  final String? motherPhone;
  final String? contactName;
  final String? contactPhone;

  final DateTime? createdAt;

  bool get isBride => gender == 'bride';
  String get genderLabel => isBride ? 'Bride' : 'Groom';
  bool get hasContact => contactAccess == ContactAccess.granted && contactPhone != null;
  bool get isOnHold => status == ProfileStatus.onHold;

  /// I asked for a hold and the uploader has not decided yet.
  bool get holdPending => holdRequestStatus == 'pending';

  /// My hold was approved — the profile is on hold for my client.
  bool get holdMine => holdRequestStatus == 'approved' && isOnHold;

  /// "12 Apr 1998" — the date of birth as families quote it.
  String? get dobLabel => dob == null ? null : DateFormat('d MMM yyyy').format(dob!.toLocal());

  /// "27 yrs (12 Apr 1998)" — the short profile line (SPEC §5 screen 3).
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

  /// "None" / "2" / "Yes"; null when not recorded. PROTECTED source fields.
  String? get siblingsLabel {
    if (hasSiblings == null) return null;
    if (hasSiblings == false) return 'None';
    final n = siblingsCount;
    return n != null && n > 0 ? '$n' : 'Yes';
  }

  /// "2 elder sisters · 1 younger brother" from the breakdown counts; null
  /// when nothing is above zero. PROTECTED source fields.
  String? get siblingsBreakdown {
    String? part(int? n, String singular, String plural) =>
        n == null || n <= 0 ? null : '$n ${n == 1 ? singular : plural}';
    final parts = [
      part(elderSisters, 'elder sister', 'elder sisters'),
      part(youngerSisters, 'younger sister', 'younger sisters'),
      part(elderBrothers, 'elder brother', 'elder brothers'),
      part(youngerBrothers, 'younger brother', 'younger brothers'),
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// "Guntur, Andhra Pradesh, India" — PROTECTED; only with contact access.
  String? get birthPlaceLine {
    final parts = [birthPlace, birthState, birthCountry?.name]
        .where((s) => s != null && s.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// "Graduation: B.Tech, JNTU · India; Post graduation: M.Tech" — one entry
  /// per filled level, in level order; null when the table is empty.
  String? get educationLevelsLabel {
    if (educationLevels.isEmpty) return null;
    final sorted = [...educationLevels]..sort((a, b) => a.order.compareTo(b.order));
    return sorted.map((e) {
      final v = e.valueLine;
      return v == null ? e.label : '${e.label}: $v';
    }).join('; ');
  }

  /// Anything at all in the protected block — decides whether the granted
  /// card shows details or a "nothing saved" note.
  bool get hasPersonalDetails =>
      [
        nativePlace,
        birthPlaceLine,
        workPlace,
        nriPlace,
        fatherName,
        fatherOccupation,
        fatherPhone,
        motherName,
        motherOccupation,
        motherPhone,
        contactName,
        contactPhone,
        siblingsLabel,
        siblingsBreakdown,
        siblingsDetails,
        familyDetails,
        propertyShare,
        propertyDetails,
      ].any((s) => s != null && s.isNotEmpty);

  /// Whole days until the approval lapses; null when access isn't granted.
  int? get contactDaysLeft {
    final exp = contactExpiresAt;
    if (exp == null) return null;
    final diff = exp.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inHours ~/ 24 + (diff.inHours % 24 > 0 ? 1 : 0);
  }

  /// "Nalgonda, Telangana" — PROTECTED; only present with contact access.
  String? get nativePlace {
    final parts = [city, state].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// "United States" for NRI profiles — the country only, never the exact
  /// place abroad (protected); "NRI" when the country is not recorded.
  String? get nriLabel {
    if (!isNri) return null;
    final c = nriCountry?.name;
    return c == null || c.isEmpty ? 'NRI' : c;
  }

  /// "Dubai" — PROTECTED; the exact place abroad, only with contact access.
  String? get nriPlaceLabel => !isNri || (nriPlace ?? '').isEmpty ? null : nriPlace;

  /// What list cards show as the location (SPEC §9.8): the NRI country, else
  /// the work country when it is set and is not India. Never a protected field.
  String? get placeLine {
    final nri = nriLabel;
    if (nri != null) return nri;
    final wc = workCountry?.name;
    if (wc == null || wc.isEmpty || wc.trim().toLowerCase() == 'india') return null;
    return wc;
  }

  /// "Works in" for the at-a-glance tile: the NRI country, else the work
  /// country (India included). Null when neither is recorded.
  String? get worksIn {
    final nri = isNri ? nriCountry?.name : null;
    if (nri != null && nri.isNotEmpty) return nri;
    final wc = workCountry?.name;
    return wc == null || wc.isEmpty ? null : wc;
  }

  /// "Kamma · Chowdary" for list cards; just the community when no subcaste.
  String? get communityLine {
    final parts = [community?.name, subcaste?.name].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// "B.Tech / B.E. — CSE, JNTU 2018"; either half alone when the other is empty.
  String? get educationLine => _withDetails(education?.name, educationDetails);
  String? get professionLine => _withDetails(profession?.name, professionDetails);

  static String? _withDetails(String? name, String? details) {
    final parts = [name, details].where((s) => s != null && s.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' — ');
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

  String? get primaryPhotoUrl => photos.isEmpty ? null : photos.first.absoluteUrl;

  static ContactAccess _access(String? s) => switch (s) {
        'granted' => ContactAccess.granted,
        'pending' => ContactAccess.pending,
        _ => ContactAccess.none,
      };

  static MasterItem? _ref(dynamic j) =>
      j == null ? null : MasterItem.fromJson(j as Map<String, dynamic>);

  static int? _int(dynamic v) => (v as num?)?.toInt();

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as int,
        fullName: '${j['full_name']}',
        gender: '${j['gender']}',
        status: ProfileStatus.fromApi(j['status'] as String?),
        dob: DateTime.tryParse('${j['dob']}'),
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
            .map((e) => EducationLevel.fromJson(e as Map<String, dynamic>))
            .toList(),
        profession: _ref(j['profession']),
        professionDetails: j['profession_details'] as String?,
        occupationType: _ref(j['occupation_type']),
        workCountry: _ref(j['work_country']),
        workPlace: j['work_place'] as String?,
        maritalStatus: _ref(j['marital_status']),
        zodiac: j['zodiac'] == null ? null : ZodiacSign.fromJson(j['zodiac'] as Map<String, dynamic>),
        nakshatram: _ref(j['nakshatram']),
        birthTime: j['birth_time'] as String?,
        birthPlace: j['birth_place'] as String?,
        birthState: j['birth_state'] as String?,
        birthCountry: _ref(j['birth_country']),
        incomeText: j['income_text'] as String?,
        otherIncome: j['other_income'] as String?,
        isNri: j['is_nri'] == true,
        nriCountry: _ref(j['nri_country']),
        nriPlace: j['nri_place'] as String?,
        hasSiblings: j['has_siblings'] as bool?,
        siblingsCount: _int(j['siblings_count']),
        siblingsDetails: j['siblings_details'] as String?,
        elderSisters: _int(j['elder_sisters']),
        youngerSisters: _int(j['younger_sisters']),
        elderBrothers: _int(j['elder_brothers']),
        youngerBrothers: _int(j['younger_brothers']),
        about: j['about'] as String?,
        familyDetails: j['family_details'] as String?,
        propertyShare: j['property_share'] as String?,
        propertyDetails: j['property_details'] as String?,
        photos: (j['photos'] as List? ?? [])
            .map((e) => ProfilePhoto.fromJson(e as Map<String, dynamic>))
            .toList(),
        isMine: j['is_mine'] == true,
        isCustomerProfile: j['is_customer_profile'] == true,
        canEdit: j['can_edit'] == true,
        canDelete: j['can_delete'] == true,
        holdRequestStatus: j['hold_request_status'] as String?,
        holdRequestId: _int(j['hold_request_id']),
        heldBy: j['held_by'] == null ? null : HeldBy.fromJson(j['held_by'] as Map<String, dynamic>),
        pendingHoldRequests: _int(j['pending_hold_requests']) ?? 0,
        contactAccess: _access(j['contact_access'] as String?),
        contactExpiresAt: j['contact_expires_at'] == null
            ? null
            : DateTime.tryParse('${j['contact_expires_at']}')?.toLocal(),
        contactRequestStatus: j['contact_request_status'] as String?,
        city: j['city'] as String?,
        state: j['state'] as String?,
        fatherName: j['father_name'] as String?,
        fatherOccupation: j['father_occupation'] as String?,
        fatherPhone: j['father_phone'] as String?,
        motherName: j['mother_name'] as String?,
        motherOccupation: j['mother_occupation'] as String?,
        motherPhone: j['mother_phone'] as String?,
        contactName: j['contact_name'] as String?,
        contactPhone: j['contact_phone'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}'),
      );
}

class ProfilePage {
  const ProfilePage({required this.profiles, required this.total, required this.page});

  final List<Profile> profiles;
  final int total;
  final int page;

  factory ProfilePage.fromJson(Map<String, dynamic> j) => ProfilePage(
        profiles: (j['profiles'] as List? ?? [])
            .map((e) => Profile.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 1,
      );
}
