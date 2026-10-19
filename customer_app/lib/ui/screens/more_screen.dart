import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../models/customer.dart';
import '../../state/auth_state.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/common.dart';
import '../widgets/notification_bell.dart';
import 'agent/change_agent_screen.dart';
import 'get_started/get_started_screen.dart';

/// More: who I am, my agent (with Call) — or *Choose your agent* → Get
/// started while I have none —, Change agent (active accounts only), Logout,
/// version (SPEC §9.11 Gandharva 6 / §9.12).
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final customer = auth.customer;
    final agent = customer?.agent;
    final pendingChange = customer?.pendingAgentChange;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(S.more),
        actions: const [NotificationBell(), SizedBox(width: 4)],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await context.read<AuthState>().refreshCustomer();
          } on Exception {
            // Pull-to-refresh is best-effort; the screen keeps what it has.
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _CustomerHeader(customer: customer),
            const SizedBox(height: 16),
            if (agent != null) ...[
              _MyAgentCard(agent: agent),
              const SizedBox(height: 16),
            ] else ...[
              NoticeCard(
                icon: Icons.support_agent_rounded,
                title: S.chooseYourAgent,
                body: S.chooseYourAgentBody,
                tint: AppColors.goldDark,
                action: FilledButton(
                  onPressed: () => GetStartedScreen.open(context),
                  child: const Text(S.chooseYourAgent),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (customer != null && !customer.hasFullAccess) ...[
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.lock_open_rounded, color: AppColors.wineLight),
                  title: const Text(S.getStarted, style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(S.getStartedTitle),
                  trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  onTap: () => GetStartedScreen.open(context),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Pending / rejected customers switch agent from Get started;
            // the approval flow of SPEC §9.6 is for active accounts.
            if (customer != null && customer.isActive) ...[
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.swap_horiz_rounded, color: AppColors.wineLight),
                  title: const Text(S.changeAgent, style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    pendingChange == null
                        ? S.changeAgentHint
                        : S.changeAgentPending(pendingChange.toAgent.fullName),
                    style: pendingChange == null
                        ? null
                        : const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w500),
                  ),
                  trailing: pendingChange == null
                      ? const Icon(Icons.chevron_right_rounded, color: AppColors.muted)
                      : const StatusChip(label: S.statusPending, color: AppColors.warning),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChangeAgentScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
                title: Text(
                  S.logout,
                  style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.error),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: theme.colorScheme.error),
                onTap: () => _confirmLogout(context),
              ),
            ),
            const SizedBox(height: 36),
            const Center(child: AppLogo(size: 48, shadow: false)),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${AppConfig.appName} · ${S.version}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.logout),
        content: const Text(S.logoutConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.logout)),
        ],
      ),
    );
    if (ok == true && context.mounted) context.read<AuthState>().logout();
  }
}

/// Initials, name and phone on the brand gradient.
class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({required this.customer});

  final Customer? customer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
              color: AppColors.goldLight,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Text(
              initialsOf(customer?.fullName ?? ''),
              style: const TextStyle(
                fontFamily: AppTheme.displayFont,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                fontVariations: [FontVariation('wght', 600)],
                color: AppColors.wineDeep,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer?.fullName ?? '',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '+91 ${customer?.phone ?? ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          if (customer != null)
            StatusChip(
              label: switch (customer!.status) {
                CustomerStatus.guest => S.statusGuest,
                CustomerStatus.active => S.statusActive,
                CustomerStatus.pending => S.statusPending,
                CustomerStatus.rejected => S.statusRejected,
                CustomerStatus.suspended => S.statusSuspended,
              },
              color: customer!.isActive ? AppColors.gold : AppColors.warning,
              solid: true,
            ),
        ],
      ),
    );
  }
}

/// "My agent": name, agency, city, community chips, phone + Call.
class _MyAgentCard extends StatelessWidget {
  const _MyAgentCard({required this.agent});

  final AgentCard agent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = agent.phone;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(S.myAgent),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.goldLight, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text(
                  initialsOf(agent.fullName),
                  style: const TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontVariations: [FontVariation('wght', 600)],
                    color: AppColors.wineDeep,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(agent.fullName, style: theme.textTheme.titleMedium),
                    if ((agent.agencyName ?? '').isNotEmpty)
                      Text(agent.agencyName!, style: theme.textTheme.bodyMedium),
                    if ((agent.city ?? '').isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 15, color: AppColors.muted),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              agent.city!,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (agent.communities.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in agent.communities)
                  Chip(
                    label: Text(c.name),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.phone_rounded, size: 18, color: AppColors.wineLight),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '+91 $phone',
                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                CallButton(phone: phone),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
