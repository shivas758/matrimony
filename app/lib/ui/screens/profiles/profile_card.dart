import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Grid card used on the profile list and my-uploads screens: the photo with
/// the name over a dark scrim, then the short profile underneath.
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.profile, required this.onTap, this.showStatus = false});

  final Profile profile;
  final VoidCallback onTap;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = context.read<ApiClient>();
    // Short profile: age with the DOB in brackets, height in feet/inches (SPEC §5 screen 3).
    final subtitle = [
      if (profile.ageDobLine != null) profile.ageDobLine!,
      if (profile.heightShort != null) profile.heightShort!,
    ].join(' · ');
    final place = profile.placeLine;
    final communityHidden = profile.isMasked('community');
    final genderColor = profile.isBride ? const Color(0xFFC2185B) : const Color(0xFF1565C0);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 0.92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AuthedPhoto(
                    url: profile.primaryPhotoUrl,
                    api: api,
                    placeholderInitials: initialsOf(profile.fullName),
                  ),
                  // Scrim so the name stays legible on any photo.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xD9021E4A)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: StatusChip(label: profile.genderLabel, color: genderColor, solid: true),
                  ),
                  // My uploads show every status; the main list only flags a hold
                  // (the holder is the one agent who still sees a held profile).
                  if ((showStatus || profile.isOnHold) && profile.status != ProfileStatus.active)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: StatusChip(
                        label: profile.status.label,
                        color: StatusColors.forProfileStatus(profile.status.apiValue, theme.colorScheme),
                        solid: true,
                      ),
                    ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // The permanent ID (SPEC §9.18 C) — only on my own
                        // uploads (admins: every card); the server leaves the
                        // key out for everyone else. It sits on the photo so
                        // the text block below keeps its two lines.
                        if (profile.hasProfileCode)
                          Text(
                            S.idLabel(profile.profileCode!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        Text(
                          profile.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // A hidden name arrives as "Profile 1042" (SPEC §9.18 D).
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            fontStyle: profile.nameHidden ? FontStyle.italic : null,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.goldLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A community the family hides arrives as null (SPEC §9.18 D).
                  _Line(
                    icon: communityHidden ? Icons.lock_outline_rounded : Icons.groups_rounded,
                    text: profile.communityLine ?? (communityHidden ? S.hiddenByFamily : '—'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontStyle:
                          profile.communityLine == null && communityHidden ? FontStyle.italic : null,
                      color: profile.communityLine == null && communityHidden
                          ? theme.colorScheme.outline
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // NRI country / work country (SPEC §9.8) — never a protected
                  // field (native place, work place, place abroad). When there
                  // is no public location, the profession fills the line.
                  _Line(
                    icon: profile.isNri ? Icons.public_rounded : Icons.place_rounded,
                    text: place ?? (profile.profession?.name ?? '—'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    trailing: profile.isNri
                        ? const StatusChip(label: 'NRI', color: Color(0xFF00695C), icon: Icons.flight_takeoff_rounded)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.style, this.trailing});

  final IconData icon;
  final String text;
  final TextStyle? style;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 14, color: AppColors.gold),
          const SizedBox(width: 5),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ],
      );
}
