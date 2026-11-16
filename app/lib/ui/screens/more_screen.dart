import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../state/auth_state.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/approval_banner.dart';
import '../widgets/common.dart';
import '../widgets/delete_account.dart';
import 'admin/admin_home_screen.dart';
import 'gift_codes_screen.dart';
import 'profiles/my_uploads_screen.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final agent = auth.agent;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('More'), actions: const [NotificationBell()]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // Agent header on the brand gradient.
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.goldPale,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initialsOf(agent?.fullName ?? ''),
                    style: const TextStyle(
                      fontFamily: AppTheme.displayFont,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      fontVariations: [FontVariation('wght', 600)],
                      color: AppColors.navyDeep,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent?.fullName ?? '',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if ((agent?.agencyName ?? '').isNotEmpty)
                        Text(
                          agent!.agencyName!,
                          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.goldLight),
                        ),
                      Text(
                        '+91 ${agent?.phone ?? ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      // The permanent agent code (SPEC §9.18 B) — tap to copy.
                      if (agent != null && agent.hasAgentCode) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                S.agentCode,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            AgentCodeChip(code: agent.agentCode!, copyable: true),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (agent?.isAdmin ?? false)
                  const StatusChip(label: 'Admin', color: AppColors.gold, solid: true),
              ],
            ),
          ),
          // SPEC §9.23 F: below 10 live clients — what that means, and the codes.
          const ApprovalBanner(margin: EdgeInsets.only(top: 16)),
          const SizedBox(height: 16),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Item(
                  icon: Icons.folder_shared_outlined,
                  title: S.myUploads,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyUploadsScreen()),
                  ),
                ),
                // SPEC §9.23 B: free codes for families (not on an older server).
                if (agent != null && agent.knowsGiftCodes) ...[
                  const Divider(height: 1, indent: 56),
                  _Item(
                    icon: Icons.card_giftcard_rounded,
                    title: S.giftCodes,
                    subtitle: agent.giftCodes == null
                        ? null
                        : S.unusedCount(agent.giftCodes!.unused),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const GiftCodesScreen()),
                    ),
                  ),
                ],
                if (agent?.isAdmin ?? false) ...[
                  const Divider(height: 1, indent: 56),
                  _Item(
                    icon: Icons.admin_panel_settings_outlined,
                    title: S.admin,
                    subtitle: auth.notifications.adminPending > 0
                        ? [
                            if (auth.notifications.pendingAgents > 0)
                              '${auth.notifications.pendingAgents} agents awaiting approval',
                            if (auth.notifications.pendingPasswordResets > 0)
                              '${auth.notifications.pendingPasswordResets} password resets',
                            if (auth.notifications.paymentsToVerify > 0)
                              S.paymentsToVerifyCount(auth.notifications.paymentsToVerify),
                            if (auth.notifications.deletionRequests > 0)
                              S.deletionRequestsCount(auth.notifications.deletionRequests),
                            if (auth.notifications.reportsOpen > 0)
                              S.reportsCount(auth.notifications.reportsOpen),
                          ].join(' · ')
                        : null,
                    badge: auth.notifications.adminPending,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
                    ),
                  ),
                ],
                const Divider(height: 1, indent: 56),
                _Item(
                  icon: Icons.settings_outlined,
                  title: S.settings,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _Item(
                  icon: Icons.person_remove_outlined,
                  title: S.deleteMyAccount,
                  subtitle: S.deleteMyAccountSubtitle,
                  onTap: () => confirmDeleteAccount(context),
                ),
                const Divider(height: 1, indent: 56),
                _logout(context, theme),
              ],
            ),
          ),
          const SizedBox(height: 36),
          const Center(child: AppLogo(size: 64, shadow: false)),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${AppConfig.appName} · v${AppConfig.appVersion}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  /// Logout, after a confirmation.
  Widget _logout(BuildContext context, ThemeData theme) => _Item(
        icon: Icons.logout_rounded,
        title: S.logout,
        color: theme.colorScheme.error,
        onTap: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text(S.logout),
              content: const Text('You will need your mobile number and password to log in again.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true), child: const Text(S.logout)),
              ],
            ),
          );
          if (ok == true && context.mounted) context.read<AuthState>().logout();
        },
      );
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badge = 0,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int badge;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color ?? AppColors.navyLight),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Badge(
          isLabelVisible: badge > 0,
          label: Text('$badge'),
          child: Icon(Icons.chevron_right_rounded, color: color ?? AppColors.muted),
        ),
        onTap: onTap,
      );
}
