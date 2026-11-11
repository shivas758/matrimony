import 'master_data.dart';
import 'profile.dart';

/// Who a profile is shown to (SPEC §9.18 E). The profile's own community is
/// always part of the audience.
enum AudienceMode {
  /// Its own community only — the default.
  ownCommunity,

  /// Its own community plus the ones the customer picked.
  selected,

  /// Every community ("no caste preference").
  all,
}

/// The Privacy screen's state as plain data (SPEC §9.18 D / E): which details
/// are switched OFF and who the profile is shown to — with the mapping from a
/// profile to the switches and from the switches to the PATCH body, so it can
/// be tested without a screen.
///
/// Immutable: every change returns a new value.
class PrivacySettings {
  const PrivacySettings({
    this.hidden = const {},
    this.audience = AudienceMode.ownCommunity,
    this.communityIds = const {},
  });

  /// The keys the customer switched OFF themselves. `subcaste` is not added
  /// here when `community` goes off — see [isShown].
  final Set<String> hidden;

  final AudienceMode audience;

  /// The ADDITIONAL communities picked for [AudienceMode.selected] — never
  /// the profile's own community (it is implicit).
  final Set<int> communityIds;

  static const communityKey = 'community';
  static const subcasteKey = 'subcaste';

  /// What an own-profile object says (`hidden_fields`, `audience_all`,
  /// `audience_communities`).
  factory PrivacySettings.fromProfile(Profile profile) {
    final own = profile.community?.id;
    final ids = {
      for (final c in profile.audienceCommunities)
        if (c.id != own) c.id,
    };
    return PrivacySettings(
      hidden: {...profile.hiddenFields},
      audience: profile.audienceAll
          ? AudienceMode.all
          : ids.isEmpty
              ? AudienceMode.ownCommunity
              : AudienceMode.selected,
      communityIds: ids,
    );
  }

  /// The switch of [key] is ON ("Shown to everyone"). A hidden community
  /// hides the subcaste with it — a subcaste would give the community away.
  bool isShown(String key) => !hidden.contains(key) && !_forcedOff(key);

  /// The switch of [key] can be moved: the subcaste's is locked (off) while
  /// the community is hidden.
  bool canToggle(String key) => !_forcedOff(key);

  bool _forcedOff(String key) => key == subcasteKey && hidden.contains(communityKey);

  /// Moves the switch of [key]. Turning `community` off takes `subcaste` with
  /// it (see [isShown]); turning it on again gives the subcaste back the
  /// state it had before. A locked switch does not move.
  PrivacySettings setShown(String key, bool shown) {
    if (!canToggle(key) || isShown(key) == shown) return this;
    final next = {...hidden};
    shown ? next.remove(key) : next.add(key);
    return PrivacySettings(hidden: next, audience: audience, communityIds: communityIds);
  }

  PrivacySettings withAudience(AudienceMode mode) =>
      mode == audience ? this : PrivacySettings(hidden: hidden, audience: mode, communityIds: communityIds);

  /// Adds / removes an additional community. The profile's own community
  /// ([ownCommunityId]) is always in and cannot be toggled.
  PrivacySettings toggleCommunity(int id, {int? ownCommunityId}) {
    if (id == ownCommunityId) return this;
    final next = {...communityIds};
    next.contains(id) ? next.remove(id) : next.add(id);
    return PrivacySettings(hidden: hidden, audience: audience, communityIds: next);
  }

  /// `hidden_fields` for the PATCH: every toggle of [fields] that is OFF, in
  /// the masters' order (a hidden community brings `subcaste` along) — plus
  /// any hidden key these masters do not list, so a detail hidden elsewhere
  /// is never revealed just because this app could not show its switch.
  List<String> hiddenFields(Iterable<PrivacyField> fields) {
    final known = [for (final f in fields) f.key];
    return [
      for (final key in known)
        if (!isShown(key)) key,
      for (final key in hidden)
        if (!known.contains(key)) key,
    ];
  }

  /// How many details are kept back (what the summary line counts).
  int hiddenCount(Iterable<PrivacyField> fields) => hiddenFields(fields).length;

  /// `audience_community_ids` for the PATCH: the picks, only in
  /// [AudienceMode.selected], never the own community, sorted.
  List<int> audienceCommunityIds({int? ownCommunityId}) => audience != AudienceMode.selected
      ? const []
      : (communityIds.where((id) => id != ownCommunityId).toList()..sort());

  /// The body of `PATCH /customer/my-profiles/:id` (SPEC §9.18 G).
  Map<String, dynamic> toJson(Iterable<PrivacyField> fields, {int? ownCommunityId}) => {
        'hidden_fields': hiddenFields(fields),
        'audience_all': audience == AudienceMode.all,
        'audience_community_ids': audienceCommunityIds(ownCommunityId: ownCommunityId),
      };

  /// Whether saving [other] would send the same thing — what "unsaved
  /// changes" means on the Privacy screen.
  bool sameAs(PrivacySettings other, Iterable<PrivacyField> fields, {int? ownCommunityId}) {
    final a = toJson(fields, ownCommunityId: ownCommunityId);
    final b = other.toJson(fields, ownCommunityId: ownCommunityId);
    return a['audience_all'] == b['audience_all'] &&
        _sameItems(a['hidden_fields'] as List, b['hidden_fields'] as List) &&
        _sameItems(a['audience_community_ids'] as List, b['audience_community_ids'] as List);
  }

  static bool _sameItems(List a, List b) => a.length == b.length && a.toSet().containsAll(b);
}
