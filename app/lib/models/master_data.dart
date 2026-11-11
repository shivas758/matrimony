/// Master-table rows. Never hardcoded in the app — always fetched from
/// GET /api/masters (CLAUDE.md working style).
class MasterItem {
  const MasterItem({required this.id, required this.name});

  final int id;
  final String name;

  factory MasterItem.fromJson(Map<String, dynamic> j) =>
      MasterItem(id: j['id'] as int, name: '${j['name']}');

  @override
  bool operator ==(Object other) => other is MasterItem && other.id == id;

  @override
  int get hashCode => id;
}

class ZodiacSign {
  const ZodiacSign({required this.id, required this.englishName, required this.indianName});

  final int id;
  final String englishName;
  final String indianName;

  /// "Mesha / Aries" — the form both families recognise.
  String get label => '$indianName / $englishName';

  factory ZodiacSign.fromJson(Map<String, dynamic> j) => ZodiacSign(
        id: j['id'] as int,
        englishName: '${j['english_name']}',
        indianName: '${j['indian_name']}',
      );

  @override
  bool operator ==(Object other) => other is ZodiacSign && other.id == id;

  @override
  int get hashCode => id;
}

/// A subcaste belongs to exactly one community. Agents create new ones simply
/// by typing on the profile form; the server finds-or-creates them (SPEC §2).
class Subcaste {
  const Subcaste({required this.id, required this.communityId, required this.name});

  final int id;
  final int communityId;
  final String name;

  factory Subcaste.fromJson(Map<String, dynamic> j) => Subcaste(
        id: j['id'] as int,
        communityId: (j['community_id'] as num).toInt(),
        name: '${j['name']}',
      );

  @override
  bool operator ==(Object other) => other is Subcaste && other.id == id;

  @override
  int get hashCode => id;
}

/// An Indian state / union territory with its two-letter code (SPEC §9.18 B).
/// The code starts every agent code issued in that state ("KA" → KA1A).
class StateItem {
  const StateItem({required this.id, required this.name, required this.code, this.active = true});

  final int id;
  final String name;

  /// Two letters, fixed once the state exists: KA, AP, TS …
  final String code;
  final bool active;

  /// "KA — Karnataka" — how dropdowns and confirmations show a state.
  String get label => code.isEmpty ? name : '$code — $name';

  static StateItem? fromJsonOrNull(Object? j) =>
      j is Map<String, dynamic> && j['id'] != null ? StateItem.fromJson(j) : null;

  factory StateItem.fromJson(Map<String, dynamic> j) => StateItem(
        id: (j['id'] as num).toInt(),
        name: '${j['name'] ?? ''}',
        code: '${j['code'] ?? ''}',
        active: j['active'] != false,
      );

  @override
  bool operator ==(Object other) => other is StateItem && other.id == id;

  @override
  int get hashCode => id;
}

/// One switchable detail of a profile (SPEC §9.18 D): the family decides
/// whether it is shown to everyone or only after approval. The list is served
/// by the API so the apps never hardcode it.
class PrivacyField {
  const PrivacyField({required this.key, required this.label, required this.section, this.hint});

  /// What travels in `hidden_fields` / `masked_fields`: name, dob, community …
  final String key;
  final String label;

  /// personal | professional | horoscope.
  final String section;

  /// A short note under the label ("Age stays visible"); null when none.
  final String? hint;

  /// Section values in the order the privacy card shows them.
  static const sections = ['personal', 'professional', 'horoscope'];

  /// "Personal" — the heading for a section value.
  static String sectionLabel(String section) => switch (section) {
        'personal' => 'Personal',
        'professional' => 'Professional',
        'horoscope' => 'Horoscope',
        _ => section.isEmpty ? 'Other' : '${section[0].toUpperCase()}${section.substring(1)}',
      };

  factory PrivacyField.fromJson(Map<String, dynamic> j) {
    final hint = j['hint'];
    return PrivacyField(
      key: '${j['key'] ?? ''}',
      label: '${j['label'] ?? j['key'] ?? ''}',
      section: '${j['section'] ?? 'personal'}',
      hint: hint is String && hint.trim().isNotEmpty ? hint : null,
    );
  }
}

class MasterData {
  const MasterData({
    required this.communities,
    this.subcastes = const [],
    required this.professions,
    required this.educations,
    required this.maritalStatuses,
    this.complexions = const [],
    this.countries = const [],
    this.religions = const [],
    this.languages = const [],
    this.foodHabits = const [],
    this.occupationTypes = const [],
    required this.zodiacSigns,
    required this.nakshatrams,
    this.states = const [],
    this.privacyFields = const [],
    this.privacyAlwaysVisible = const [],
  });

  final List<MasterItem> communities;
  final List<Subcaste> subcastes;
  final List<MasterItem> professions;
  final List<MasterItem> educations;
  final List<MasterItem> maritalStatuses;

  /// Skin complexion (Very Fair … Dark) — seeded, admin-editable.
  final List<MasterItem> complexions;

  /// Countries — starts with India (SPEC §9.7) because nationality, birth
  /// country, work country and the education-level countries pick from it,
  /// as well as the NRI country. Seeded, admin-editable.
  final List<MasterItem> countries;

  /// Religions — seeded, admin-editable.
  final List<MasterItem> religions;

  /// One list serves both mother tongue and known languages.
  final List<MasterItem> languages;

  /// Vegetarian, Non-Vegetarian, Eggetarian … — seeded, admin-editable.
  final List<MasterItem> foodHabits;

  /// Private job, Government job, Business … (SPEC §9.7) — seeded, admin-editable.
  final List<MasterItem> occupationTypes;
  final List<ZodiacSign> zodiacSigns;
  final List<MasterItem> nakshatrams;

  /// States and union territories (SPEC §9.18 B) — an agent's state decides
  /// their agent code. Empty on a server older than v2.8.
  final List<StateItem> states;

  /// The profile details a family can switch off (SPEC §9.18 D), in display
  /// order. Empty on an older server — the privacy card is hidden then.
  final List<PrivacyField> privacyFields;

  /// What can never be hidden: "Main photo", "Age", "Gender".
  final List<String> privacyAlwaysVisible;

  static List<MasterItem> _items(dynamic list) =>
      (list as List? ?? []).map((e) => MasterItem.fromJson(e as Map<String, dynamic>)).toList();

  factory MasterData.fromJson(Map<String, dynamic> j) => MasterData(
        communities: _items(j['communities']),
        subcastes: (j['subcastes'] as List? ?? [])
            .map((e) => Subcaste.fromJson(e as Map<String, dynamic>))
            .toList(),
        professions: _items(j['professions']),
        educations: _items(j['educations']),
        maritalStatuses: _items(j['marital_statuses']),
        complexions: _items(j['complexions']),
        countries: _items(j['countries']),
        religions: _items(j['religions']),
        languages: _items(j['languages']),
        foodHabits: _items(j['food_habits']),
        occupationTypes: _items(j['occupation_types']),
        zodiacSigns: (j['zodiac_signs'] as List? ?? [])
            .map((e) => ZodiacSign.fromJson(e as Map<String, dynamic>))
            .toList(),
        nakshatrams: _items(j['nakshatrams']),
        states: (j['states'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .where((e) => e['id'] != null)
            .map(StateItem.fromJson)
            .toList(),
        privacyFields: (j['privacy_fields'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PrivacyField.fromJson)
            .where((f) => f.key.isNotEmpty)
            .toList(),
        privacyAlwaysVisible:
            (j['privacy_always_visible'] as List? ?? []).map((e) => '$e').toList(),
      );

  static const empty = MasterData(
    communities: [],
    professions: [],
    educations: [],
    maritalStatuses: [],
    zodiacSigns: [],
    nakshatrams: [],
  );

  /// Subcastes that belong to one community — what the form and filters show.
  List<Subcaste> subcastesFor(int? communityId) =>
      communityId == null ? const [] : subcastes.where((s) => s.communityId == communityId).toList();

  /// Subcastes for any of several communities (filter sheet multi-select).
  List<Subcaste> subcastesForAny(Set<int> communityIds) =>
      communityIds.isEmpty ? const [] : subcastes.where((s) => communityIds.contains(s.communityId)).toList();

  /// The state with this id; null when unknown (or the list has not loaded).
  StateItem? stateById(int? id) {
    if (id == null) return null;
    for (final s in states) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// States an agent can pick: the active ones, in the served order.
  List<StateItem> get activeStates => states.where((s) => s.active).toList();

  /// [privacyFields] of one section, in the served order.
  List<PrivacyField> privacyFieldsIn(String section) =>
      privacyFields.where((f) => f.section == section).toList();

  /// Sections that actually have fields: the three known ones first, then
  /// anything a newer server adds.
  List<String> get privacySections {
    final present = privacyFields.map((f) => f.section).toSet();
    return [
      ...PrivacyField.sections.where(present.contains),
      ...present.where((s) => !PrivacyField.sections.contains(s)),
    ];
  }

  String? communityName(int? id) => _nameOf(communities, id);
  String? educationName(int? id) => _nameOf(educations, id);
  String? professionName(int? id) => _nameOf(professions, id);
  String? maritalStatusName(int? id) => _nameOf(maritalStatuses, id);
  String? complexionName(int? id) => _nameOf(complexions, id);
  String? countryName(int? id) => _nameOf(countries, id);
  String? religionName(int? id) => _nameOf(religions, id);
  String? languageName(int? id) => _nameOf(languages, id);
  String? foodHabitName(int? id) => _nameOf(foodHabits, id);
  String? occupationTypeName(int? id) => _nameOf(occupationTypes, id);
  String? nakshatramName(int? id) => _nameOf(nakshatrams, id);

  /// The id of "India" in [countries] — the default work country / nationality
  /// on a new profile. Null until the masters have loaded.
  int? get indiaCountryId {
    for (final c in countries) {
      if (c.name.trim().toLowerCase() == 'india') return c.id;
    }
    return null;
  }

  String? subcasteName(int? id) {
    if (id == null) return null;
    for (final s in subcastes) {
      if (s.id == id) return s.name;
    }
    return null;
  }

  static String? _nameOf(List<MasterItem> list, int? id) {
    if (id == null) return null;
    for (final item in list) {
      if (item.id == id) return item.name;
    }
    return null;
  }
}
