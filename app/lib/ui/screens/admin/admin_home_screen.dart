import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../strings.dart';
import '../../widgets/common.dart';
import 'admin_agents_screen.dart';
import 'admin_community_requests_screen.dart';
import 'admin_customers_screen.dart';
import 'admin_logs_screen.dart';
import 'admin_masters_screen.dart';
import 'admin_password_resets_screen.dart';

/// Admin dashboard (SPEC §5 screen 9).
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  AdminStats? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await context.read<AdminService>().stats();
      if (mounted) setState(() => _stats = stats);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return Scaffold(
      appBar: AppBar(title: const Text(S.admin)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_loading && s == null)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_error != null && s == null)
              ErrorState(message: _error!, onRetry: _load)
            else if (s != null) ...[
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.65,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _StatCard(
                    label: 'Active agents',
                    value: '${s.activeAgents}',
                    icon: Icons.badge_outlined,
                  ),
                  _StatCard(
                    label: 'Awaiting approval',
                    value: '${s.pendingAgents}',
                    icon: Icons.hourglass_top_rounded,
                    highlight: s.pendingAgents > 0,
                  ),
                  _StatCard(
                    label: 'Active profiles',
                    value: '${s.activeProfiles}',
                    icon: Icons.people_outline_rounded,
                  ),
                  _StatCard(
                    label: 'Shares (7 days)',
                    value: '${s.sharesLast7Days}',
                    icon: Icons.share_outlined,
                  ),
                  _StatCard(
                    label: 'Profiles on hold',
                    value: '${s.onHoldProfiles}',
                    icon: Icons.pause_circle_outline_rounded,
                  ),
                  _StatCard(
                    label: 'Hold requests waiting',
                    value: '${s.pendingHoldRequests}',
                    icon: Icons.hourglass_top_rounded,
                    highlight: s.pendingHoldRequests > 0,
                  ),
                  _StatCard(
                    label: 'Customers waiting',
                    value: '${s.pendingCustomers}',
                    icon: Icons.person_add_alt_1_outlined,
                    highlight: s.pendingCustomers > 0,
                  ),
                  _StatCard(
                    label: 'Active customers',
                    value: '${s.activeCustomers}',
                    icon: Icons.people_alt_outlined,
                  ),
                  _StatCard(
                    label: S.guestCustomers,
                    value: '${s.guestCustomers}',
                    icon: Icons.person_outline_rounded,
                  ),
                  _StatCard(
                    label: S.paidRegistrations,
                    value: '${s.paidRegistrations}',
                    icon: Icons.currency_rupee_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            const SectionHeader('Manage'),
            _NavTile(
              icon: Icons.how_to_reg_rounded,
              title: S.pendingAgents,
              badge: s?.pendingAgents ?? 0,
              onTap: () => _open(const AdminAgentsScreen(initialStatus: 'pending')),
            ),
            _NavTile(
              icon: Icons.groups_2_outlined,
              title: S.allAgents,
              onTap: () => _open(const AdminAgentsScreen()),
            ),
            _NavTile(
              icon: Icons.people_alt_outlined,
              title: S.customers,
              subtitle: S.customersSubtitle,
              badge: s?.pendingCustomers ?? 0,
              onTap: () => _open(const AdminCustomersScreen()),
            ),
            _NavTile(
              icon: Icons.playlist_add_check_rounded,
              title: S.communityRequests,
              badge: s?.pendingCommunityRequests ?? 0,
              onTap: () => _open(const AdminCommunityRequestsScreen()),
            ),
            _NavTile(
              icon: Icons.lock_reset_rounded,
              title: S.passwordResets,
              subtitle: 'Agents who forgot their password',
              badge: s?.pendingPasswordResets ?? 0,
              onTap: () => _open(const AdminPasswordResetsScreen()),
            ),
            _NavTile(
              icon: Icons.list_alt_rounded,
              title: S.masterTables,
              subtitle: 'Communities, education, professions, complexions, NRI countries, star lists',
              onTap: () => _open(const AdminMastersScreen()),
            ),
            const SizedBox(height: 16),
            const SectionHeader(S.logs),
            _NavTile(
              icon: Icons.share_outlined,
              title: S.shareLogs,
              onTap: () => _open(const AdminLogsScreen(initialTab: 0)),
            ),
            _NavTile(
              icon: Icons.lock_open_rounded,
              title: S.contactLogs,
              badge: s?.pendingContactRequests ?? 0,
              onTap: () => _open(const AdminLogsScreen(initialTab: 1)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: highlight ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Badge(
          isLabelVisible: badge > 0,
          label: Text('$badge'),
          child: const Icon(Icons.chevron_right_rounded),
        ),
        onTap: onTap,
      );
}
