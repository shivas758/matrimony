import 'package:flutter/material.dart';

import '../../models/master_data.dart';
import '../../state/profile_form_logic.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';

/// The Privacy card at the end of the profile form (SPEC §9.18 D / E / G):
/// what is always shown, a switch per detail the family may keep for after
/// approval (grouped Personal / Professional / Horoscope, served by the API),
/// and who the profile is shown to. Stateless — the form owns the
/// [ProfilePrivacy] value and gets every change through [onChanged].
class PrivacyCard extends StatelessWidget {
  const PrivacyCard({
    super.key,
    required this.fields,
    required this.alwaysVisible,
    required this.privacy,
    required this.onChanged,
    required this.communities,
    this.ownCommunityId,
    this.enabled = true,
  });

  /// `privacy_fields` from GET /masters, in display order.
  final List<PrivacyField> fields;

  /// `privacy_always_visible` from GET /masters ("Main photo", "Age", "Gender").
  final List<String> alwaysVisible;
  final ProfilePrivacy privacy;
  final ValueChanged<ProfilePrivacy> onChanged;

  /// Every community of the masters; the profile's own is left out of the picker.
  final List<MasterItem> communities;
  final int? ownCommunityId;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = <String>[
      ...PrivacyField.sections.where((s) => fields.any((f) => f.section == s)),
      ...{for (final f in fields) f.section}.where((s) => !PrivacyField.sections.contains(s)),
    ];
    final others = communities.where((c) => c.id != ownCommunityId).toList();

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 20, color: AppColors.goldDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.privacy,
                  style: theme.textTheme.titleMedium?.copyWith(color: AppColors.navy),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            S.privacyBody,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (alwaysVisible.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.visibility_outlined, size: 16, color: AppColors.success),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: '${S.alwaysShown}: ',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: alwaysVisible.join(', ')),
                        ],
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          for (final section in sections) ...[
            const SizedBox(height: 14),
            _SectionLabel(PrivacyField.sectionLabel(section)),
            for (final field in fields.where((f) => f.section == section))
              _PrivacySwitch(
                key: ValueKey('privacy-${field.key}'),
                field: field,
                shown: privacy.isShown(field.key),
                locked: privacy.isLocked(field.key),
                enabled: enabled,
                onChanged: (shown) => onChanged(privacy.withShown(field.key, shown)),
              ),
          ],
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 12, 4, 10),
            child: Divider(height: 1),
          ),
          Text(
            S.showProfileTo,
            style: theme.textTheme.titleSmall?.copyWith(color: AppColors.navy),
          ),
          const SizedBox(height: 4),
          _AudienceOption(
            key: const ValueKey('audience-own'),
            title: S.audienceOwn,
            subtitle: S.audienceOwnHint,
            selected: privacy.mode == AudienceMode.own,
            onTap: enabled ? () => onChanged(privacy.withMode(AudienceMode.own)) : null,
          ),
          _AudienceOption(
            key: const ValueKey('audience-selected'),
            title: S.audienceSelected,
            subtitle: S.audienceSelectedHint,
            selected: privacy.mode == AudienceMode.selected,
            onTap: enabled ? () => onChanged(privacy.withMode(AudienceMode.selected)) : null,
          ),
          if (privacy.mode == AudienceMode.selected)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 2, 4, 8),
              child: others.isEmpty
                  ? Text(
                      S.audienceNoOthers,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.audiencePick,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final c in others)
                              FilterChip(
                                label: Text(c.name),
                                selected: privacy.communityIds.contains(c.id),
                                visualDensity: VisualDensity.compact,
                                onSelected: enabled
                                    ? (on) => onChanged(privacy.withCommunity(c.id, on))
                                    : null,
                              ),
                          ],
                        ),
                      ],
                    ),
            ),
          _AudienceOption(
            key: const ValueKey('audience-all'),
            title: S.audienceAll,
            subtitle: S.audienceAllHint,
            selected: privacy.mode == AudienceMode.all,
            onTap: enabled ? () => onChanged(privacy.withMode(AudienceMode.all)) : null,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.goldDark,
              letterSpacing: 1.0,
              fontWeight: FontWeight.w700,
            ),
      );
}

/// One detail: label, what the switch position means, the switch.
/// ON = shown to everyone, OFF = only after approval.
class _PrivacySwitch extends StatelessWidget {
  const _PrivacySwitch({
    super.key,
    required this.field,
    required this.shown,
    required this.locked,
    required this.enabled,
    required this.onChanged,
  });

  final PrivacyField field;
  final bool shown;

  /// Off and not switchable — the subcaste while the community is hidden.
  final bool locked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = locked
        ? S.hiddenWithCommunity
        : shown
            ? S.shownToEveryone
            : S.onlyAfterApproval;
    final statusColor = shown ? AppColors.success : AppColors.goldDark;

    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled && !locked ? () => onChanged(!shown) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: locked ? theme.colorScheme.outline : null,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(
                          shown ? Icons.visibility_outlined : Icons.lock_outline_rounded,
                          size: 13,
                          color: statusColor,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            status,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (field.hint != null)
                      Text(
                        field.hint!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: shown,
                onChanged: enabled && !locked ? onChanged : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the three "Show this profile to" choices — a radio row.
class _AudienceOption extends StatelessWidget {
  const _AudienceOption({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      enabled: onTap != null,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected ? AppColors.navy : AppColors.muted,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle,
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
