import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/master_data.dart';
import '../../../models/privacy_settings.dart';
import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Privacy settings of my profile (SPEC §9.18 D / E / G).
///
/// * **Always shown** — main photo, age, gender: locked-on switches.
/// * One switch per entry of the masters' `privacy_fields`, grouped Personal /
///   Professional / Horoscope: ON = "Shown to everyone", OFF = "Only after
///   approval". Hiding the community hides the subcaste with it.
/// * **Show my profile to** — my community only · selected communities
///   (multi-select; my own is always in) · all communities.
///
/// Save → `PATCH /customer/my-profiles/:id {hidden_fields, audience_all,
/// audience_community_ids}` and pops the updated [Profile]. Leaving with
/// unsaved changes asks first. The switches ↔ request mapping is
/// [PrivacySettings]. Opened from My profile, and once automatically right
/// after a profile is created ([afterCreate]: a "registered" note, *Skip for
/// now*, and the button continues even when nothing was changed).
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, required this.profile, this.afterCreate = false});

  /// My own profile, as an own-profile route returned it.
  final Profile profile;

  /// Shown right after the profile was registered.
  final bool afterCreate;

  /// Opens the screen; the future gives the updated profile, or null when
  /// nothing was saved.
  static Future<Profile?> open(BuildContext context, Profile profile) => Navigator.of(context).push<Profile>(
        MaterialPageRoute(builder: (_) => PrivacyScreen(profile: profile)),
      );

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  /// What the server has, and what the switches say now.
  late final PrivacySettings _saved = PrivacySettings.fromProfile(widget.profile);
  late PrivacySettings _settings = _saved;

  bool _busy = false;
  String? _error;

  int? get _ownCommunityId => widget.profile.community?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MastersState>().load();
    });
  }

  bool _dirty(List<PrivacyField> fields) => !_settings.sameAs(_saved, fields, ownCommunityId: _ownCommunityId);

  void _set(PrivacySettings next) => setState(() {
        _settings = next;
        _error = null;
      });

  Future<void> _leave(List<PrivacyField> fields) async {
    if (_busy) return;
    if (_dirty(fields) && !await confirmDiscard(context)) return;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save(List<PrivacyField> fields) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await context.read<ProfileService>().updatePrivacy(
            widget.profile.id,
            _settings.toJson(fields, ownCommunityId: _ownCommunityId),
          );
      if (!mounted) return;
      // After a registration the caller says "Profile saved" itself.
      if (!widget.afterCreate) showSnack(context, S.privacySaved);
      Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 403: the account may not change this right now — the server says why.
      setState(() => _error = e.status == 403 && e.message.isNotEmpty ? e.message : friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mastersState = context.watch<MastersState>();
    final masters = mastersState.data;
    final fields = masters.privacyFields;
    final dirty = _dirty(fields);

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(fields);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(S.privacyTitle),
          leading: BackButton(onPressed: _busy ? null : () => _leave(fields)),
          actions: [
            if (widget.afterCreate)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text(S.skipForNow),
                ),
              ),
          ],
        ),
        body: fields.isEmpty ? _unavailable(mastersState) : _body(masters, fields),
        bottomNavigationBar: fields.isEmpty
            ? null
            : Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.rule)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          ErrorBanner(message: _error!),
                          const SizedBox(height: 10),
                        ],
                        FilledButton(
                          // Right after registering, the button also just moves on.
                          onPressed: _busy
                              ? null
                              : dirty
                                  ? () => _save(fields)
                                  : widget.afterCreate
                                      ? () => Navigator.of(context).pop()
                                      : null,
                          child: _busy
                              ? const ButtonSpinner()
                              : Text(
                                  !widget.afterCreate
                                      ? S.save
                                      : dirty
                                          ? S.saveAndContinue
                                          : S.continueLabel,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// The masters are still loading, or the server has no toggles (older than
  /// v2.8 — the entry point is hidden then, so this is only a safety net).
  Widget _unavailable(MastersState mastersState) {
    if (mastersState.loading) return const Center(child: CircularProgressIndicator());
    return EmptyState(
      icon: Icons.shield_outlined,
      title: S.privacyTitle,
      message: mastersState.error ?? S.privacyUnavailable,
      actionLabel: S.retry,
      onAction: () => context.read<MastersState>().load(force: true),
    );
  }

  Widget _body(MasterData masters, List<PrivacyField> fields) {
    final sections = <(String, List<PrivacyField>)>[
      for (final section in PrivacyField.sections) (S.privacySectionTitle(section), masters.privacyFieldsIn(section)),
      (S.privacyOtherSection, masters.privacyFieldsElsewhere),
    ].where((s) => s.$2.isNotEmpty).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // What this screen is for — after a registration, first that it worked.
        if (widget.afterCreate) ...[
          const NoticeCard(
            icon: Icons.check_circle_outline_rounded,
            title: S.privacyAfterCreateTitle,
            body: S.privacyAfterCreateBody,
            tint: AppColors.success,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text(
              S.privacyIntro,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ),
        ] else
          const NoticeCard(
            icon: Icons.shield_outlined,
            title: S.privacyHeadline,
            body: S.privacyIntro,
          ),
        const SizedBox(height: 16),

        // ---- always shown
        if (masters.privacyAlwaysVisible.isNotEmpty) ...[
          const SectionHeader(S.privacyAlwaysShown),
          _Group(
            children: [
              for (final label in masters.privacyAlwaysVisible)
                _ToggleRow.locked(label: label, caption: S.privacyShown),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // ---- the toggles, section by section
        for (final (title, items) in sections) ...[
          SectionHeader(title),
          _Group(
            children: [
              for (final field in items)
                _ToggleRow(
                  label: field.label,
                  hint: field.hint,
                  value: _settings.isShown(field.key),
                  caption: !_settings.canToggle(field.key)
                      ? S.privacyHiddenWithCommunity
                      : _settings.isShown(field.key)
                          ? S.privacyShown
                          : S.privacyHidden,
                  onChanged: _busy || !_settings.canToggle(field.key)
                      ? null
                      : (shown) => _set(_settings.setShown(field.key, shown)),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        const LockNote(text: S.privacySearchNote, icon: Icons.search_off_rounded),
        const SizedBox(height: 20),

        // ---- who sees the profile
        const SectionHeader(S.audienceTitle),
        _AudienceCard(
          settings: _settings,
          ownCommunity: widget.profile.community,
          communities: masters.communities,
          enabled: !_busy,
          onMode: (mode) => _set(_settings.withAudience(mode)),
          onToggleCommunity: (id) => _set(_settings.toggleCommunity(id, ownCommunityId: _ownCommunityId)),
        ),
      ],
    );
  }
}

/// A white card whose rows can be tapped: the rows' ripples are drawn on a
/// transparent [Material] inside the card (they would be hidden behind its
/// white background otherwise) and clipped to its rounded corners.
class _TapCard extends StatelessWidget {
  const _TapCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      );
}

/// A white card holding rows separated by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _TapCard(
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              children[i],
            ],
          ],
        ),
      );
}

/// One detail with its switch: the label, an optional hint, and what the
/// switch position means in words.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.caption,
    required this.onChanged,
    this.hint,
  }) : locked = false;

  /// A detail that is always shown: the switch is on and cannot be moved.
  const _ToggleRow.locked({required this.label, required this.caption})
      : value = true,
        onChanged = null,
        hint = null,
        locked = true;

  final String label;
  final String? hint;
  final bool value;
  final String caption;
  final ValueChanged<bool>? onChanged;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final captionColor = locked || onChanged == null
        ? muted
        : value
            ? AppColors.success
            : AppColors.wineLight;
    return SwitchListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
      value: value,
      onChanged: onChanged,
      // A lock in the thumb of a switch that cannot be moved.
      thumbIcon: locked ? const WidgetStatePropertyAll(Icon(Icons.lock_rounded, color: AppColors.wine)) : null,
      title: Text(label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint != null) Text(hint!, style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.3)),
          Text(
            caption,
            style: theme.textTheme.bodySmall?.copyWith(color: captionColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// "Show my profile to": three choices, and the community chips under
/// *Selected communities*.
class _AudienceCard extends StatelessWidget {
  const _AudienceCard({
    required this.settings,
    required this.ownCommunity,
    required this.communities,
    required this.enabled,
    required this.onMode,
    required this.onToggleCommunity,
  });

  final PrivacySettings settings;
  final MasterItem? ownCommunity;
  final List<MasterItem> communities;
  final bool enabled;
  final ValueChanged<AudienceMode> onMode;
  final ValueChanged<int> onToggleCommunity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final others = communities.where((c) => c.id != ownCommunity?.id).toList();

    Widget option(AudienceMode mode, String title, String subtitle) => RadioListTile<AudienceMode>(
          value: mode,
          enabled: enabled,
          contentPadding: const EdgeInsets.fromLTRB(6, 2, 16, 2),
          title: Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.3)),
        );

    return _TapCard(
      child: RadioGroup<AudienceMode>(
        groupValue: settings.audience,
        onChanged: (mode) {
          if (enabled && mode != null) onMode(mode);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            option(AudienceMode.ownCommunity, S.audienceOwn, S.audienceOwnHint(ownCommunity?.name)),
            const Divider(height: 1, indent: 16, endIndent: 16),
            option(AudienceMode.selected, S.audienceSelected, S.audienceSelectedHint),
            if (settings.audience == AudienceMode.selected)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      others.isEmpty ? S.audienceNoOthers : S.audiencePickHint,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        // My own community: always in, cannot be removed.
                        if (ownCommunity != null)
                          Chip(
                            avatar: const Icon(Icons.lock_rounded, size: 16, color: AppColors.wine),
                            label: Text(ownCommunity!.name),
                            backgroundColor: AppColors.goldLight,
                            side: const BorderSide(color: AppColors.gold),
                            visualDensity: VisualDensity.compact,
                          ),
                        for (final c in others)
                          FilterChip(
                            label: Text(c.name),
                            selected: settings.communityIds.contains(c.id),
                            onSelected: enabled ? (_) => onToggleCommunity(c.id) : null,
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            option(AudienceMode.all, S.audienceAll, S.audienceAllHint),
          ],
        ),
      ),
    );
  }
}
