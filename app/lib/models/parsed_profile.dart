import 'profile.dart';

/// Result of POST /profiles/parse (AI import). `draft` holds profile-form
/// fields ready to pre-fill; `unmatched` holds raw text the server could not
/// map to a master row; `warnings` are things the agent must check.
/// Nothing here has been saved — the agent reviews and submits as usual.
///
/// Draft keys mirror the profile write body. Besides the original set the
/// v2.1 registration-form keys are accepted when present and ignored when
/// absent: `nationality_id`, `occupation_type_id`, `work_country_id`,
/// `other_income`, `birth_state`, `birth_country_id`, `father_occupation`,
/// `mother_occupation`, `property_share`, `property_details`,
/// `elder_sisters`, `younger_sisters`, `elder_brothers`, `younger_brothers`
/// and `education_levels[{level, details?, country_id?}]`.
class ParsedProfile {
  const ParsedProfile({
    required this.draft,
    required this.unmatched,
    required this.warnings,
    this.model,
  });

  final Map<String, dynamic> draft;
  final Map<String, String> unmatched;
  final List<String> warnings;
  final String? model;

  factory ParsedProfile.fromJson(Map<String, dynamic> j) => ParsedProfile(
        draft: Map<String, dynamic>.from(j['draft'] as Map? ?? const {}),
        unmatched: (j['unmatched'] as Map? ?? const {})
            .map((k, v) => MapEntry('$k', '$v')),
        warnings: (j['warnings'] as List? ?? const []).map((e) => '$e').toList(),
        model: (j['ai'] as Map?)?['model'] as String?,
      );

  bool has(String key) => draft.containsKey(key);

  int? intField(String key) {
    final v = draft[key];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  String? textField(String key) {
    final v = draft[key];
    return v == null ? null : '$v';
  }

  /// The draft's education table, normalised to `{level, details, country_id}`
  /// rows in level order. Rows with an unknown level are dropped; an absent or
  /// malformed key yields an empty list (= "nothing to pre-fill").
  List<Map<String, dynamic>> get educationLevels {
    final raw = draft['education_levels'];
    if (raw is! List) return const [];
    final rows = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final level = '${e['level'] ?? ''}';
      if (!EducationLevel.levels.contains(level)) continue;
      final details = e['details'];
      final country = e['country_id'];
      rows.add({
        'level': level,
        'details': details == null ? null : '$details',
        'country_id': country is num
            ? country.toInt()
            : country is String
                ? int.tryParse(country)
                : null,
      });
    }
    rows.sort((a, b) => EducationLevel.levels
        .indexOf(a['level'] as String)
        .compareTo(EducationLevel.levels.indexOf(b['level'] as String)));
    return rows;
  }
}
