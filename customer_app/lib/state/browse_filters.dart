/// Filter state for Browse (SPEC §9.11 Gandharva 3 / §9.12) — the agent
/// list's filters minus `mine` / `status`. [gender] is the Bride / Groom
/// toggle: null = let the server decide (the opposite of my first paid
/// profile with full access; everyone for guests). Serialises to query
/// params for GET /customer/profiles.
class BrowseFilters {
  const BrowseFilters({
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
    this.foodHabitIds = const {},
    this.nriOnly = false,
    this.countryIds = const {},
    this.city,
    this.query,
    this.sort = 'newest',
    this.gender,
  });

  static const int defaultAgeMin = 18;
  static const int defaultAgeMax = 60;

  /// Height slider bounds in cm (≈ 3'11" – 7'3"). The slider shows feet/inches.
  static const int defaultHeightMin = 120;
  static const int defaultHeightMax = 220;

  static const sortOptions = ['newest', 'oldest', 'name', 'age_asc', 'age_desc'];

  final int ageMin;
  final int ageMax;
  final int heightMin;
  final int heightMax;

  /// Empty = every community my agent serves (the server scope).
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
  final Set<int> foodHabitIds;

  /// NRI profiles only; [countryIds] narrows further (any of).
  final bool nriOnly;
  final Set<int> countryIds;

  /// "Place" — matches work place / NRI place / native city on the server
  /// without revealing them.
  final String? city;
  final String? query;
  final String sort;

  /// 'bride' | 'groom' | null (not sent).
  final String? gender;

  static const empty = BrowseFilters();

  bool get isAgeDefault => ageMin == defaultAgeMin && ageMax == defaultAgeMax;
  bool get isHeightDefault => heightMin == defaultHeightMin && heightMax == defaultHeightMax;

  /// How many filters are actually set — drives the badge on the Filters button.
  int get activeCount {
    var n = 0;
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
    if (foodHabitIds.isNotEmpty) n++;
    if (nriOnly || countryIds.isNotEmpty) n++;
    if ((city ?? '').isNotEmpty) n++;
    return n;
  }

  bool get hasSearch => (query ?? '').isNotEmpty;

  BrowseFilters copyWith({
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
    Set<int>? foodHabitIds,
    bool? nriOnly,
    Set<int>? countryIds,
    String? city,
    bool clearCity = false,
    String? query,
    bool clearQuery = false,
    String? sort,
    String? gender,
    bool clearGender = false,
  }) =>
      BrowseFilters(
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
        foodHabitIds: foodHabitIds ?? this.foodHabitIds,
        nriOnly: nriOnly ?? this.nriOnly,
        countryIds: countryIds ?? this.countryIds,
        city: clearCity ? null : (city ?? this.city),
        query: clearQuery ? null : (query ?? this.query),
        sort: sort ?? this.sort,
        gender: clearGender ? null : (gender ?? this.gender),
      );

  /// Everything except the free-text search, sort and the Bride / Groom
  /// toggle — "Clear all".
  BrowseFilters clearedFilters() => BrowseFilters(query: query, sort: sort, gender: gender);

  /// What a guest may send: everything except name search and sort-by-name
  /// (SPEC §9.13 — a guest card has no name).
  BrowseFilters forGuest() => copyWith(
        clearQuery: true,
        sort: sort == 'name' ? 'newest' : sort,
      );

  /// Query params for GET /customer/profiles. Id lists go as comma lists,
  /// which the server accepts alongside repeated params.
  Map<String, dynamic> toQuery({int page = 1, int limit = 20}) {
    String? csv(Set<int> ids) => ids.isEmpty ? null : (ids.toList()..sort()).join(',');
    return {
      'page': page,
      'limit': limit,
      'sort': sort,
      'gender': ?gender,
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
      if (csv(foodHabitIds) != null) 'food_habit_id': csv(foodHabitIds),
      if (nriOnly || countryIds.isNotEmpty) 'nri': 'true',
      if (csv(countryIds) != null) 'country_id': csv(countryIds),
      if ((city ?? '').isNotEmpty) 'city': city,
      if ((query ?? '').isNotEmpty) 'q': query,
    };
  }
}
