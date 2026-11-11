/// Master-table rows. Never hardcoded in the app — always fetched from
/// GET /api/masters (CLAUDE.md working style). Same payload as the agents' app
/// (Wedbook Agent) plus `occupation_types` (SPEC §9.7); `countries` starts
/// with India. Since v2.8 it also lists the privacy toggles (SPEC §9.18 D).
class MasterItem {
  const MasterItem({required this.id, required this.name});

  final int id;
  final String name;

  factory MasterItem.fromJson(Map<String, dynamic> j) =>
      MasterItem(id: (j['id'] as num).toInt(), name: '${j['name']}');

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
        id: (j['id'] as num).toInt(),
        englishName: '${j['english_name']}',
        indianName: '${j['indian_name']}',
      );

  @override
  bool operator ==(Object other) => other is ZodiacSign && other.id == id;

  @override
  int get hashCode => id;
}

/// A subcaste belongs to exactly one community. The server finds-or-creates
/// new ones typed on the profile form (SPEC §2).
class Subcaste {
  const Subcaste({required this.id, required this.communityId, required this.name});

  final int id;
  final int communityId;
  final String name;

  factory Subcaste.fromJson(Map<String, dynamic> j) => Subcaste(
        id: (j['id'] as num).toInt(),
        communityId: (j['community_id'] as num).toInt(),
        name: '${j['name']}',
      );

  @override
  bool operator ==(Object other) => other is Subcaste && other.id == id;

  @override
  int get hashCode => id;
}

/// One privacy toggle (SPEC §9.18 D) — `privacy_fields[]` of GET /masters:
/// a detail of the "before approval" sheet the customer may keep back until
/// they approve someone. The list (keys, labels, grouping) is the server's.
class PrivacyField {
  const PrivacyField({required this.key, required this.label, required this.section, this.hint});

  /// The key sent in `hidden_fields` (e.g. `community`, `income`).
  final String key;

  /// What the customer reads next to the switch.
  final String label;

  /// 'personal' | 'professional' | 'horoscope' (anything else is listed last).
  final String section;

  /// A short note under the label, when the server has one.
  final String? hint;

  static const sectionPersonal = 'personal';
  static const sectionProfessional = 'professional';
  static const sectionHoroscope = 'horoscope';

  /// The sections in the order the Privacy screen shows them.
  static const sections = [sectionPersonal, sectionProfessional, sectionHoroscope];

  /// Null for a row without a usable key (never trust the shape blindly).
  static PrivacyField? tryParse(dynamic j) {
    if (j is! Map) return null;
    final key = j['key'];
    if (key is! String || key.isEmpty) return null;
    final label = j['label'];
    final hint = j['hint'];
    return PrivacyField(
      key: key,
      label: label is String && label.isNotEmpty ? label : key,
      section: j['section'] is String ? j['section'] as String : sectionPersonal,
      hint: hint is String && hint.trim().isNotEmpty ? hint.trim() : null,
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

  /// Countries — India first, then the NRI list. Used for nationality, birth
  /// country, work country, education countries and the NRI country.
  final List<MasterItem> countries;

  /// Religions — seeded, admin-editable.
  final List<MasterItem> religions;

  /// One list serves both mother tongue and known languages.
  final List<MasterItem> languages;

  /// Vegetarian, Non-Vegetarian, Eggetarian … — seeded, admin-editable.
  final List<MasterItem> foodHabits;

  /// Private job, Government job, Business … (SPEC §9.7).
  final List<MasterItem> occupationTypes;
  final List<ZodiacSign> zodiacSigns;
  final List<MasterItem> nakshatrams;

  /// The details a customer can switch off (SPEC §9.18 D), in the server's
  /// order. Empty on a server older than v2.8 — the Privacy screen is then
  /// not offered at all.
  final List<PrivacyField> privacyFields;

  /// What can never be hidden — "Main photo", "Age", "Gender".
  final List<String> privacyAlwaysVisible;

  /// The server knows the privacy toggles (v2.8+).
  bool get hasPrivacy => privacyFields.isNotEmpty;

  /// The toggles of one section, in the server's order.
  List<PrivacyField> privacyFieldsIn(String section) =>
      privacyFields.where((f) => f.section == section).toList();

  /// Toggles whose section this app does not know — still shown (last).
  List<PrivacyField> get privacyFieldsElsewhere =>
      privacyFields.where((f) => !PrivacyField.sections.contains(f.section)).toList();

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
        privacyFields: (j['privacy_fields'] is List ? j['privacy_fields'] as List : const [])
            .map(PrivacyField.tryParse)
            .whereType<PrivacyField>()
            .toList(),
        privacyAlwaysVisible: (j['privacy_always_visible'] is List ? j['privacy_always_visible'] as List : const [])
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList(),
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
