import 'dart:convert';

import '../ui/strings.dart';

/// The four steps of the Add / Edit profile form (SPEC §9.18 F). Pure data,
/// so "which step does this field live on" is testable without widgets.
enum ProfileFormStep {
  personal(S.stepPersonal, S.stepPersonalShort),
  professional(S.stepProfessional, S.stepProfessionalShort),
  horoscope(S.stepHoroscope, S.stepHoroscopeShort),
  family(S.stepFamily, S.stepFamilyShort);

  const ProfileFormStep(this.title, this.shortLabel);

  /// "Personal details" — the heading of the step.
  final String title;

  /// The same on two lines, for the narrow step header ("Personal\ndetails").
  final String shortLabel;

  bool get isFirst => index == 0;
  bool get isLast => index == values.length - 1;

  /// The step after this one; null on the last.
  ProfileFormStep? get next => isLast ? null : values[index + 1];

  /// The step before this one; null on the first.
  ProfileFormStep? get previous => isFirst ? null : values[index - 1];

  /// "Step 2 of 4"
  String get position => '${S.stepOf} ${index + 1} of ${values.length}';

  /// API keys (profile write body) of the fields on each step — exactly the
  /// mapping of SPEC §9.18 F. The four required fields are all on [personal].
  static const _fields = <ProfileFormStep, Set<String>>{
    personal: {
      'full_name',
      'gender',
      'dob',
      'marital_status',
      'religion',
      'community',
      'subcaste',
      'subcaste_name',
      'mother_tongue',
      'known_languages',
      'known_language_ids',
      'height_cm',
      'height',
      'weight_kg',
      'weight',
      'complexion',
      'food_habit',
      'nationality',
      'about',
      'photos',
    },
    professional: {
      'education_levels',
      'education',
      'education_details',
      'occupation_type',
      'profession',
      'profession_details',
      'income_text',
      'income',
      'other_income',
      'work_country',
      'work_place',
      'is_nri',
      'nri',
      'nri_country',
      'nri_place',
    },
    horoscope: {
      'nakshatram',
      'zodiac',
      'gothram',
      'birth_time',
      'birth_place',
      'birth_state',
      'birth_country',
    },
    family: {
      'father_name',
      'father_occupation',
      'father_phone',
      'mother_name',
      'mother_occupation',
      'mother_phone',
      'has_siblings',
      'siblings_count',
      'siblings_details',
      'elder_sisters',
      'younger_sisters',
      'elder_brothers',
      'younger_brothers',
      'family_details',
      'property_share',
      'property_details',
      'city',
      'state',
      'contact_name',
      'contact_phone',
      'status',
      'hidden_fields',
      'audience_all',
      'audience_community_ids',
    },
  };

  /// Fields that must be filled before a profile can be saved.
  static const requiredFields = ['full_name', 'gender', 'dob', 'community_id'];

  /// The step that holds the field the API calls [apiKey] — `community_id`,
  /// `community`, `education_levels[2].details` and `education_levels.2`
  /// all resolve. Null for a key no step owns.
  static ProfileFormStep? forField(String? apiKey) {
    if (apiKey == null) return null;
    final match = RegExp(r'^[a-z_]+').firstMatch(apiKey.trim().toLowerCase());
    if (match == null) return null;
    var key = match.group(0)!;
    for (final step in values) {
      if (_fields[step]!.contains(key)) return step;
    }
    // `community_id` → `community`, `known_language_ids` → `known_language`.
    key = key.replaceFirst(RegExp(r'_ids?$'), '');
    for (final step in values) {
      if (_fields[step]!.contains(key)) return step;
    }
    return null;
  }

  /// The earliest step among [apiKeys] (server field errors, AI import
  /// hints …); null when none of them belongs to a step.
  static ProfileFormStep? firstFor(Iterable<String> apiKeys) {
    ProfileFormStep? first;
    for (final key in apiKeys) {
      final step = forField(key);
      if (step != null && (first == null || step.index < first.index)) first = step;
    }
    return first;
  }

  /// Every step that owns at least one of [apiKeys], in step order.
  static List<ProfileFormStep> stepsFor(Iterable<String> apiKeys) {
    final found = <ProfileFormStep>{};
    for (final key in apiKeys) {
      final step = forField(key);
      if (step != null) found.add(step);
    }
    return [for (final step in values) if (found.contains(step)) step];
  }
}

/// "Show this profile to" (SPEC §9.18 E).
enum AudienceMode {
  /// The profile's own community only — the default.
  own,

  /// Its own community plus the ones picked.
  selected,

  /// Every community.
  all,
}

/// What the Privacy card edits (SPEC §9.18 D / E): the details switched off
/// ("only after approval") and who the profile is shown to. Immutable — every
/// change returns a new value, so the form can keep it in its state.
class ProfilePrivacy {
  const ProfilePrivacy({
    this.hidden = const {},
    this.mode = AudienceMode.own,
    this.communityIds = const {},
  });

  /// Privacy keys switched OFF by hand. `subcaste` also counts as hidden
  /// while `community` is — see [isHidden].
  final Set<String> hidden;
  final AudienceMode mode;

  /// Additional communities picked for [AudienceMode.selected]. Kept while
  /// another mode is chosen, so switching back does not lose the picks.
  final Set<int> communityIds;

  /// The community's key, and the key that follows it.
  static const communityKey = 'community';
  static const subcasteKey = 'subcaste';

  /// From what the server sent back to the owner side: `hidden_fields`,
  /// `audience_all`, `audience_communities[].id`.
  factory ProfilePrivacy.fromServer({
    List<String>? hiddenFields,
    bool audienceAll = false,
    Iterable<int> audienceCommunityIds = const [],
  }) {
    final ids = audienceCommunityIds.toSet();
    return ProfilePrivacy(
      hidden: {...?hiddenFields},
      mode: audienceAll
          ? AudienceMode.all
          : ids.isEmpty
              ? AudienceMode.own
              : AudienceMode.selected,
      communityIds: ids,
    );
  }

  /// A hidden community hides the subcaste with it (SPEC §9.18 D table).
  bool isHidden(String key) =>
      hidden.contains(key) || (key == subcasteKey && hidden.contains(communityKey));

  /// The switch position: ON = shown to everyone.
  bool isShown(String key) => !isHidden(key);

  /// The subcaste switch is off and disabled while the community is hidden.
  bool isLocked(String key) => key == subcasteKey && hidden.contains(communityKey);

  /// Flips one switch. A locked switch does not move.
  ProfilePrivacy withShown(String key, bool shown) {
    if (isLocked(key)) return this;
    final next = {...hidden};
    shown ? next.remove(key) : next.add(key);
    return ProfilePrivacy(hidden: next, mode: mode, communityIds: communityIds);
  }

  ProfilePrivacy withMode(AudienceMode mode) =>
      ProfilePrivacy(hidden: hidden, mode: mode, communityIds: communityIds);

  ProfilePrivacy withCommunity(int id, bool selected) {
    final next = {...communityIds};
    selected ? next.add(id) : next.remove(id);
    return ProfilePrivacy(hidden: hidden, mode: mode, communityIds: next);
  }

  /// `hidden_fields` to send: the switched-off keys the server knows
  /// ([knownKeys], in that order) — `subcaste` included whenever `community`
  /// is. Keys the server never offered are dropped, so an outdated key can
  /// not fail the save.
  List<String> hiddenKeys(Iterable<String> knownKeys) =>
      [for (final key in knownKeys) if (isHidden(key)) key];

  /// `audience_all` to send.
  bool get audienceAll => mode == AudienceMode.all;

  /// `audience_community_ids` to send: the picks in [AudienceMode.selected]
  /// (never the profile's own community — it is always part of the audience),
  /// nothing in the other two modes.
  List<int> audienceIds({int? ownCommunityId}) {
    if (mode != AudienceMode.selected) return const [];
    return communityIds.where((id) => id != ownCommunityId).toList()..sort();
  }

  /// The three keys as real JSON values — the body of `PATCH /profiles/:id`.
  Map<String, dynamic> toJsonFields(Iterable<String> knownKeys, {int? ownCommunityId}) => {
        'hidden_fields': hiddenKeys(knownKeys),
        'audience_all': audienceAll,
        'audience_community_ids': audienceIds(ownCommunityId: ownCommunityId),
      };

  /// The same as strings for the multipart `POST /profiles`: JSON array
  /// strings and `true` / `false`.
  Map<String, String> toMultipartFields(Iterable<String> knownKeys, {int? ownCommunityId}) => {
        'hidden_fields': jsonEncode(hiddenKeys(knownKeys)),
        'audience_all': '$audienceAll',
        'audience_community_ids': jsonEncode(audienceIds(ownCommunityId: ownCommunityId)),
      };

  /// How many details are switched off among [knownKeys] — for a summary line.
  int hiddenCount(Iterable<String> knownKeys) => hiddenKeys(knownKeys).length;
}
