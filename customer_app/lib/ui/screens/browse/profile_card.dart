import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// One row of the Browse list: photo on the left, then name, age (DOB) and
/// height, community · subcaste, education, profession, and an "Interested"
/// chip once I have marked it (SPEC §9.11 Gandharva 3). Only public fields —
/// list rows never carry the on-request block.
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.onTap,
    this.interested = false,
  });

  final Profile profile;
  final VoidCallback onTap;
  final bool interested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = context.read<ApiClient>();
    final p = profile;
    final ageHeight = [
      if (p.ageDobLine != null) p.ageDobLine!,
      if (p.heightShort != null) p.heightShort!,
    ].join(' · ');

    return Card(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 168,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 124,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AuthedPhoto(
                      url: p.primaryPhotoUrl,
                      api: api,
                      placeholderInitials: initialsOf(p.fullName),
                    ),
                    if (p.isNri)
                      const Positioned(
                        top: 8,
                        left: 8,
                        child: StatusChip(
                          label: S.nri,
                          color: Color(0xFF00695C),
                          icon: Icons.flight_takeoff_rounded,
                          solid: true,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              p.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.maroon,
                              ),
                            ),
                          ),
                          if (interested) ...[
                            const SizedBox(width: 6),
                            const StatusChip(
                              label: S.interestedChip,
                              color: AppColors.roseDark,
                              icon: Icons.favorite_rounded,
                            ),
                          ],
                        ],
                      ),
                      if (ageHeight.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          ageHeight,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.roseDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _Line(icon: Icons.groups_rounded, text: p.communityLine ?? '—', bold: true),
                      const SizedBox(height: 4),
                      _Line(icon: Icons.school_outlined, text: p.education?.name ?? '—'),
                      const SizedBox(height: 4),
                      _Line(icon: Icons.work_outline_rounded, text: p.profession?.name ?? '—'),
                      const Spacer(),
                      // Public location: NRI country / work country (SPEC §9.8).
                      if (p.placeLine != null)
                        _Line(icon: Icons.place_outlined, text: p.placeLine!, muted: true),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.bold = false, this.muted = false});

  final IconData icon;
  final String text;
  final bool bold;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.roseDark),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
              color: muted ? theme.colorScheme.outline : AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// A guest-mode teaser card (SPEC §9.12): ONLY photo, age, job, caste and
/// package, with a lock — no name. Tapping it opens Get started.
class GuestProfileCard extends StatelessWidget {
  const GuestProfileCard({super.key, required this.profile, required this.onTap});

  final Profile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = context.read<ApiClient>();
    final p = profile;
    final title = [
      p.gender.isEmpty ? null : p.genderLabel,
      if (p.age != null) '${p.age} ${S.yearsShort}',
    ].whereType<String>().join(' · ');

    return Card(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 116,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AuthedPhoto(url: p.primaryPhotoUrl, api: api),
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: StatusChip(
                        label: S.lockedProfile,
                        color: AppColors.maroon,
                        icon: Icons.lock_rounded,
                        solid: true,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title.isEmpty ? '—' : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.maroon,
                              ),
                            ),
                          ),
                          const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.roseDark),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _Line(icon: Icons.groups_rounded, text: p.communityLine ?? '—', bold: true),
                      const SizedBox(height: 4),
                      _Line(icon: Icons.work_outline_rounded, text: p.jobLabel ?? '—'),
                      const SizedBox(height: 4),
                      _Line(icon: Icons.payments_outlined, text: p.incomeText ?? '—'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
