import 'dart:convert';

/// Filter state for the profile list (SPEC §5 screen 3).
/// Serialises to query params for GET /api/profiles and to JSON for
/// locally-saved presets.
class ProfileFilters {
  const ProfileFilters({
    this.gender,
    this.ageMin = defaultAgeMin,
    this.ageMax = defaultAgeMax,
    this.heightMin = defaultHeightMin,
    this.heightMax = defaultHeightMax,
    this.communityIds = const {},
    this.subcasteIds = const {},
    this.educationIds = const {},
    this.professionIds = const {},
    this.occupationTypeIds = const {},
    this.workCountryIds = const {},
    this.maritalStatusIds = const {},
    this.complexionIds = const {},
    this.religionIds = const {},
    this.motherTongueIds = const {},
    this.languageIds = const {},
    this.foodHabitIds = const {},
    this.zodiacIds = const {},
    this.nakshatramIds = const {},
    this.nriOnly = false,
    this.countryIds = const {},
    this.city,
    this.query,
    this.sort = 'newest',
    this.mineOnly = false,
    this.status,
  });

  static const int defaultAgeMin = 18;
  static const int defaultAgeMax = 60;

  /// Height slider bounds in cm (≈ 3'11" – 7'3"). The slider shows feet/inches.
  static const int defaultHeightMin = 120;
  static const int defaultHeightMax = 220;

  final String? gender; // 'bride' | 'groom' | null (both)
  final int ageMin;
  final int ageMax;
  final int heightMin;
  final int heightMax;
  final Set<int> communityIds;
  /// Only meaningful alongside communityIds — a subcaste belongs to one community.
  final Set<int> subcasteIds;
  final Set<int> educationIds;
  final Set<int> professionIds;

  /// Occupation type (Private job, Business …) — any of (SPEC §9.7).
  final Set<int> occupationTypeIds;

  /// Work country — the public coarse location (SPEC §9.8) — any of.
  final Set<int> workCountryIds;
  final Set<int> maritalStatusIds;
  final Set<int> complexionIds;
  final Set<int> religionIds;
  final Set<int> motherTongueIds;
  /// Known languages — any of.
  final Set<int> languageIds;
  final Set<int> foodHabitIds;
  final Set<int> zodiacIds;
  final Set<int> nakshatramIds;

  /// NRI profiles only; [countryIds] narrows further (any of, single or many).
  final bool nriOnly;
  final Set<int> countryIds;

  /// "Place" — matches work place / NRI place / native city on the server.
  final String? city;
  final String? query;
  final String sort;
  final bool mineOnly;
  final String? status;

  static const empty = ProfileFilters();

  bool get isAgeDefault => ageMin == defaultAgeMin && ageMax == defaultAgeMax;
  bool get isHeightDefault => heightMin == defaultHeightMin && heightMax == defaultHeightMax;

  /// How many filters the agent has actually set — drives the chip badge.
  int get activeCount {
    var n = 0;
    if (gender != null) n++;
    if (!isAgeDefault) n++;
    if (!isHeightDefault) n++;
    if (communityIds.isNotEmpty) n++;
    if (subcasteIds.isNotEmpty) n++;
    if (educationIds.isNotEmpty) n++;
    if (professionIds.isNotEmpty) n++;
    if (occupationTypeIds.isNotEmpty) n++;
    if (workCountryIds.isNotEmpty) n++;
    if (maritalStatusIds.isNotEmpty) n++;
    if (complexionIds.isNotEmpty) n++;
    if (religionIds.isNotEmpty) n++;
    if (motherTongueIds.isNotEmpty) n++;
    if (languageIds.isNotEmpty) n++;
    if (foodHabitIds.isNotEmpty) n++;
    if (zodiacIds.isNotEmpty) n++;
    if (nakshatramIds.isNotEmpty) n++;
    if (nriOnly || countryIds.isNotEmpty) n++;
    if ((city ?? '').isNotEmpty) n++;
    if (status != null) n++;
    if (mineOnly) n++;
    return n;
  }

  ProfileFilters copyWith({
    String? gender,
    bool clearGender = false,
    int? ageMin,
    int? ageMax,
    int? heightMin,
    int? heightMax,
    Set<int>? communityIds,
    Set<int>? subcasteIds,
    Set<int>? educationIds,
    Set<int>? professionIds,
    Set<int>? occupationTypeIds,
    Set<int>? workCountryIds,
    Set<int>? maritalStatusIds,
    Set<int>? complexionIds,
    Set<int>? religionIds,
    Set<int>? motherTongueIds,
    Set<int>? languageIds,
    Set<int>? foodHabitIds,
    Set<int>? zodiacIds,
    Set<int>? nakshatramIds,
    bool? nriOnly,
    Set<int>? countryIds,
    String? city,
    bool clearCity = false,
    String? query,
    bool clearQuery = false,
    String? sort,
    bool? mineOnly,
    String? status,
    bool clearStatus = false,
  }) =>
      ProfileFilters(
        gender: clearGender ? null : (gender ?? this.gender),
        ageMin: ageMin ?? this.ageMin,
        ageMax: ageMax ?? this.ageMax,
        heightMin: heightMin ?? this.heightMin,
        heightMax: heightMax ?? this.heightMax,
        communityIds: communityIds ?? this.communityIds,
        subcasteIds: subcasteIds ?? this.subcasteIds,
        educationIds: educationIds ?? this.educationIds,
        professionIds: professionIds ?? this.professionIds,
        occupationTypeIds: occupationTypeIds ?? this.occupationTypeIds,
        workCountryIds: workCountryIds ?? this.workCountryIds,
        maritalStatusIds: maritalStatusIds ?? this.maritalStatusIds,
        complexionIds: complexionIds ?? this.complexionIds,
        religionIds: religionIds ?? this.religionIds,
        motherTongueIds: motherTongueIds ?? this.motherTongueIds,
        languageIds: languageIds ?? this.languageIds,
        foodHabitIds: foodHabitIds ?? this.foodHabitIds,
        zodiacIds: zodiacIds ?? this.zodiacIds,
        nakshatramIds: nakshatramIds ?? this.nakshatramIds,
        nriOnly: nriOnly ?? this.nriOnly,
        countryIds: countryIds ?? this.countryIds,
        city: clearCity ? null : (city ?? this.city),
        query: clearQuery ? null : (query ?? this.query),
        sort: sort ?? this.sort,
        mineOnly: mineOnly ?? this.mineOnly,
        status: clearStatus ? null : (status ?? this.status),
      );

  /// Everything except the free-text search — "Clear all" in the filter sheet.
  ProfileFilters clearedFilters() => ProfileFilters(query: query, sort: sort);

  Map<String, dynamic> toQuery({int page = 1, int limit = 20}) {
    String? csv(Set<int> ids) => ids.isEmpty ? null : ids.join(',');
    return {
      'page': page,
      'limit': limit,
      'sort': sort,
      if (gender != null) 'gender': gender,
      if (ageMin != defaultAgeMin) 'age_min': ageMin,
      if (ageMax != defaultAgeMax) 'age_max': ageMax,
      if (heightMin != defaultHeightMin) 'height_min': heightMin,
      if (heightMax != defaultHeightMax) 'height_max': heightMax,
      if (csv(communityIds) != null) 'community_id': csv(communityIds),
      if (csv(subcasteIds) != null) 'subcaste_id': csv(subcasteIds),
      if (csv(educationIds) != null) 'education_id': csv(educationIds),
      if (csv(professionIds) != null) 'profession_id': csv(professionIds),
      if (csv(occupationTypeIds) != null) 'occupation_type_id': csv(occupationTypeIds),
      if (csv(workCountryIds) != null) 'work_country_id': csv(workCountryIds),
      if (csv(maritalStatusIds) != null) 'marital_status_id': csv(maritalStatusIds),
      if (csv(complexionIds) != null) 'complexion_id': csv(complexionIds),
      if (csv(religionIds) != null) 'religion_id': csv(religionIds),
      if (csv(motherTongueIds) != null) 'mother_tongue_id': csv(motherTongueIds),
      if (csv(languageIds) != null) 'language_id': csv(languageIds),
      if (csv(foodHabitIds) != null) 'food_habit_id': csv(foodHabitIds),
      if (csv(zodiacIds) != null) 'zodiac_id': csv(zodiacIds),
      if (csv(nakshatramIds) != null) 'nakshatram_id': csv(nakshatramIds),
      if (nriOnly || countryIds.isNotEmpty) 'nri': 'true',
      if (csv(countryIds) != null) 'country_id': csv(countryIds),
      if ((city ?? '').isNotEmpty) 'city': city,
      if ((query ?? '').isNotEmpty) 'q': query,
      if (status != null) 'status': status,
      if (mineOnly) 'mine': 'true',
    };
  }

  Map<String, dynamic> toJson() => {
        'gender': gender,
        'age_min': ageMin,
        'age_max': ageMax,
        'height_min': heightMin,
        'height_max': heightMax,
        'community_ids': communityIds.toList(),
        'subcaste_ids': subcasteIds.toList(),
        'education_ids': educationIds.toList(),
        'profession_ids': professionIds.toList(),
        'occupation_type_ids': occupationTypeIds.toList(),
        'work_country_ids': workCountryIds.toList(),
        'marital_status_ids': maritalStatusIds.toList(),
        'complexion_ids': complexionIds.toList(),
        'religion_ids': religionIds.toList(),
        'mother_tongue_ids': motherTongueIds.toList(),
        'language_ids': languageIds.toList(),
        'food_habit_ids': foodHabitIds.toList(),
        'zodiac_ids': zodiacIds.toList(),
        'nakshatram_ids': nakshatramIds.toList(),
        'nri_only': nriOnly,
        'country_ids': countryIds.toList(),
        'city': city,
        'sort': sort,
      };

  /// Missing keys (presets saved by an older app) read as "not set".
  static Set<int> _ids(dynamic v) =>
      (v as List? ?? []).map((e) => (e as num).toInt()).toSet();

  factory ProfileFilters.fromJson(Map<String, dynamic> j) => ProfileFilters(
        gender: j['gender'] as String?,
        ageMin: (j['age_min'] as num?)?.toInt() ?? defaultAgeMin,
        ageMax: (j['age_max'] as num?)?.toInt() ?? defaultAgeMax,
        heightMin: (j['height_min'] as num?)?.toInt() ?? defaultHeightMin,
        heightMax: (j['height_max'] as num?)?.toInt() ?? defaultHeightMax,
        communityIds: _ids(j['community_ids']),
        subcasteIds: _ids(j['subcaste_ids']),
        educationIds: _ids(j['education_ids']),
        professionIds: _ids(j['profession_ids']),
        occupationTypeIds: _ids(j['occupation_type_ids']),
        workCountryIds: _ids(j['work_country_ids']),
        maritalStatusIds: _ids(j['marital_status_ids']),
        complexionIds: _ids(j['complexion_ids']),
        religionIds: _ids(j['religion_ids']),
        motherTongueIds: _ids(j['mother_tongue_ids']),
        languageIds: _ids(j['language_ids']),
        foodHabitIds: _ids(j['food_habit_ids']),
        zodiacIds: _ids(j['zodiac_ids']),
        nakshatramIds: _ids(j['nakshatram_ids']),
        nriOnly: j['nri_only'] == true,
        countryIds: _ids(j['country_ids']),
        city: j['city'] as String?,
        sort: '${j['sort'] ?? 'newest'}',
      );

  String encode() => jsonEncode(toJson());

  static ProfileFilters decode(String s) =>
      ProfileFilters.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

/// A named filter preset, stored on the device only (SPEC §5 screen 3).
class FilterPreset {
  const FilterPreset({required this.name, required this.filters});

  final String name;
  final ProfileFilters filters;

  Map<String, dynamic> toJson() => {'name': name, 'filters': filters.toJson()};

  factory FilterPreset.fromJson(Map<String, dynamic> j) => FilterPreset(
        name: '${j['name']}',
        filters: ProfileFilters.fromJson(j['filters'] as Map<String, dynamic>),
      );
}
