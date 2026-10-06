import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/notifications.dart';
import '../../state/auth_state.dart';
import '../../state/home_nav.dart';
import '../../state/notification_routes.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin/admin_agents_screen.dart';
import 'admin/admin_password_resets_screen.dart';
import 'clients/client_detail_screen.dart';
import 'profiles/profile_detail_screen.dart';
import 'settings_screen.dart';

/// The screen a notification opens, or null for a home-tab target.
Widget? screenForTarget(NotificationTarget target) => switch (target) {
      TabTarget() => null,
      ProfileTarget(:final profileId) => ProfileDetailScreen(profileId: profileId),
      ClientTarget(:final customerId) => ClientDetailScreen(customerId: customerId),
      SettingsTarget() => const SettingsScreen(),
      AdminPendingAgentsTarget() => const AdminAgentsScreen(initialStatus: 'pending'),
      AdminPasswordResetsTarget() => const AdminPasswordResetsScreen(),
    };

/// Opens [target] from anywhere (a tapped push, SPEC §9.16): home-tab
/// targets close whatever is on top and switch the tab; the rest push their
/// screen. No target → the Notifications screen.
void openNotificationTarget(NavigatorState nav, HomeNav home, NotificationTarget? target) {
  if (target is TabTarget) {
    nav.popUntil((r) => r.isFirst);
    home.go(target.tab, subTab: target.subTab);
    return;
  }
  final screen = target == null ? const NotificationsScreen() : screenForTarget(target)!;
  nav.push(MaterialPageRoute(builder: (_) => screen));
}

/// Bell with the "needs my action" count (`badge`) for the app bar of every
/// main tab (SPEC §9.14). Uses the feed AuthState already polls.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final badge = context.select<AuthState, int>((a) => a.badge);
    return IconButton(
      tooltip: S.notifications,
      icon: Badge(
        isLabelVisible: badge > 0,
        label: Text(badge > 99 ? '99+' : '$badge'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
      onPressed: () async {
        // The screen pops with a tab target; everything else it opens itself.
        final target = await Navigator.of(context).push<TabTarget>(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
        if (target != null && context.mounted) {
          context.read<HomeNav>().go(target.tab, subTab: target.subTab);
          context.read<AuthState>().refreshNotifications();
        }
      },
    );
  }
}

/// Every notification, "Needs your action" first, then "Updates"; a dot on
/// items newer than my last visit (a per-device timestamp).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _lastOpenedKey = 'notifications_last_opened';

  /// Items after this are "new". Null = never opened (everything is new).
  DateTime? _lastOpened;
  bool _refreshing = true;

  @override
  void initState() {
    super.initState();
    _markOpened();
    _refresh();
  }

  /// Remembers the previous visit for the dots, then stores "now". Local
  /// storage is a convenience — any failure just means no dots.
  Future<void> _markOpened() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getInt(_lastOpenedKey);
      if (mounted && prev != null) {
        setState(() => _lastOpened = DateTime.fromMillisecondsSinceEpoch(prev));
      }
      await prefs.setInt(_lastOpenedKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Ignore.
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await context.read<AuthState>().refreshNotifications();
    if (mounted) setState(() => _refreshing = false);
  }

  bool _isNew(NotificationItem it) {
    final at = it.at;
    if (at == null) return false;
    return _lastOpened == null || at.isAfter(_lastOpened!);
  }

  Future<void> _open(NotificationTarget target) async {
    final nav = Navigator.of(context);
    final screen = screenForTarget(target);
    if (screen == null) {
      nav.pop(target);
      return;
    }
    await nav.push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final isAdmin = auth.isAdmin;
    final items = [...auth.notifications.items]
      ..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    final action = items
        .where((i) => notificationGroup(i.type, isAdmin: isAdmin) == NotificationGroup.action)
        .toList();
    final updates = items
        .where((i) => notificationGroup(i.type, isAdmin: isAdmin) == NotificationGroup.update)
        .toList();
    final now = DateTime.now();

    Widget row(NotificationItem it) {
      final target = notificationTarget(it, isAdmin: isAdmin);
      return _NotificationTile(
        item: it,
        time: relativeTime(it.at, now),
        isNew: _isNew(it),
        onTap: target == null ? null : () => _open(target),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text(S.notifications)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: items.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                  if (_refreshing)
                    const Center(child: CircularProgressIndicator())
                  else
                    const EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: S.noNotifications,
                      message: S.noNotificationsHint,
                    ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (action.isNotEmpty) ...[
                    _GroupTitle(S.needsYourAction, count: action.length),
                    for (final it in action) row(it),
                  ],
                  if (updates.isNotEmpty) ...[
                    const _GroupTitle(S.updates),
                    for (final it in updates) row(it),
                  ],
                ],
              ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title, {this.count = 0});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: SectionHeader(
          title,
          trailing: count > 0 ? StatusChip(label: '$count', color: AppColors.warning) : null,
        ),
      );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.time,
    required this.isNew,
    this.onTap,
  });

  final NotificationItem item;
  final String time;
  final bool isNew;
  final VoidCallback? onTap;

  static IconData iconFor(String type) => switch (type) {
        'contact_request_received' || 'contact_request_decided' => Icons.lock_open_rounded,
        'hold_request_received' || 'hold_request_decided' => Icons.pause_circle_outline_rounded,
        'community_request_decided' => Icons.groups_rounded,
        'agent_pending' => Icons.badge_outlined,
        'password_reset_requested' => Icons.key_rounded,
        'client_pending' => Icons.person_add_alt_1_outlined,
        'interest_received' || 'interest_decided' => Icons.favorite_outline_rounded,
        'agent_change_requested' || 'agent_change_decided' => Icons.swap_horiz_rounded,
        'profile_delete_requested' => Icons.delete_outline_rounded,
        _ => Icons.notifications_none_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.navyTint,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(iconFor(item.type), size: 20, color: AppColors.navy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: isNew ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                      if (isNew) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(item.body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.outline)
            else
              const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }
}
