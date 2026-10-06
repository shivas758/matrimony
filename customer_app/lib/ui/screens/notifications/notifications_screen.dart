import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/notification.dart';
import '../../../state/home_tab.dart';
import '../../../state/notifications_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../browse/profile_detail_screen.dart';
import '../get_started/get_started_screen.dart';
import '../my_profile/my_profile_screen.dart';

/// Notifications (SPEC §9.15): "Needs your action" then "Updates", an icon
/// per type, relative time, a "new" dot on updates since the last visit,
/// pull to refresh, empty state. Opening it refreshes the feed and stores
/// the "last opened" time. Taps follow [routeFor]; unknown types are listed
/// but not tappable.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.tabs});

  /// The home shell's tab switcher (My profiles / More destinations).
  final HomeTab? tabs;

  static Future<void> open(BuildContext context, {HomeTab? tabs}) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NotificationsScreen(tabs: tabs)),
      );

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<NotificationsState>();
      state.markOpened();
      state.refresh();
    });
  }

  Future<void> _tap(AppNotification n) async {
    final route = routeFor(n);
    if (!route.tappable) return;
    final stayed = await openNotificationRoute(Navigator.of(context), route, tabs: widget.tabs, fromList: true);
    // Back from a profile / Get started: things may have changed.
    if (stayed && mounted) context.read<NotificationsState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotificationsState>();
    final feed = state.feed;
    final actions = feed.actions;
    final updates = feed.updates;
    final now = DateTime.now();

    Widget body;
    if (state.loading && !state.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.error != null && !state.loaded) {
      body = ErrorState(message: state.error!, onRetry: state.refresh);
    } else if (feed.items.isEmpty) {
      body = ListView(
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          const EmptyState(
            icon: Icons.notifications_none_rounded,
            title: S.noNotifications,
            message: S.noNotificationsHint,
          ),
        ],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (actions.isNotEmpty) ...[
            const SectionHeader(S.needsYourAction),
            for (final n in actions) ...[
              _NotificationTile(n: n, now: now, isNew: false, onTap: _tap),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
          ],
          if (updates.isNotEmpty) ...[
            const SectionHeader(S.updates),
            for (final n in updates) ...[
              _NotificationTile(n: n, now: now, isNew: state.isNew(n), onTap: _tap),
              const SizedBox(height: 8),
            ],
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text(S.notifications)),
      body: RefreshIndicator(onRefresh: state.refresh, child: body),
    );
  }
}

/// Opens a notification's target (SPEC §9.15 table) — shared by the list and
/// tapped pushes (SPEC §9.16). [fromList]: we are on the Notifications screen
/// (tab targets pop it); otherwise tab targets pop to the home shell. A null
/// / untappable route opens the Notifications screen. Returns true when the
/// caller stays on its screen underneath the pushed one.
Future<bool> openNotificationRoute(
  NavigatorState nav,
  NotificationRoute? route, {
  HomeTab? tabs,
  bool fromList = false,
}) async {
  void toTab(int tab) {
    tabs?.value = tab;
    if (fromList) {
      nav.pop();
    } else {
      nav.popUntil((r) => r.isFirst);
    }
  }

  switch (route?.destination) {
    case NotificationDestination.ownProfile:
      await nav.push(MaterialPageRoute(builder: (_) => MyProfileScreen(profileId: route!.id!)));
      return true;
    case NotificationDestination.profileDetail:
      await nav.push(MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileId: route!.id!)));
      return true;
    case NotificationDestination.getStarted:
      await nav.push(MaterialPageRoute(builder: (_) => const GetStartedScreen()));
      return true;
    case NotificationDestination.myProfilesTab:
      toTab(HomeTab.myProfiles);
      return false;
    case NotificationDestination.moreTab:
      toTab(HomeTab.more);
      return false;
    case NotificationDestination.none:
    case null:
      if (!fromList) await nav.push(MaterialPageRoute(builder: (_) => NotificationsScreen(tabs: tabs)));
      return false;
  }
}

/// (icon, colour) per type; unknown types get a neutral bell.
(IconData, Color) notificationLook(String type) => switch (type) {
      'payment_due' => (Icons.payments_outlined, AppColors.roseDark),
      'interest_expiring' => (Icons.timer_outlined, AppColors.warning),
      'account_approved' => (Icons.verified_rounded, AppColors.success),
      'account_rejected' => (Icons.block_rounded, const Color(0xFFC62828)),
      'interest_accepted' => (Icons.lock_open_rounded, AppColors.success),
      'interest_declined' => (Icons.do_not_disturb_on_outlined, const Color(0xFFC62828)),
      'interest_revoked' => (Icons.lock_outline_rounded, const Color(0xFFC62828)),
      'payment_received' => (Icons.receipt_long_rounded, AppColors.success),
      'agent_change_approved' => (Icons.swap_horiz_rounded, AppColors.success),
      'agent_change_rejected' => (Icons.swap_horiz_rounded, const Color(0xFFC62828)),
      'delete_request_approved' => (Icons.delete_outline_rounded, AppColors.success),
      'delete_request_rejected' => (Icons.delete_outline_rounded, const Color(0xFFC62828)),
      _ => (Icons.notifications_none_rounded, AppColors.muted),
    };

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.now, required this.isNew, required this.onTap});

  final AppNotification n;
  final DateTime now;
  final bool isNew;
  final ValueChanged<AppNotification> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = notificationLook(n.type);
    final route = routeFor(n);
    return Card(
      child: InkWell(
        onTap: route.tappable ? () => onTap(n) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 21, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            n.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: isNew || n.isAction ? FontWeight.w700 : FontWeight.w600,
                              color: AppColors.maroon,
                            ),
                          ),
                        ),
                        if (isNew)
                          Semantics(
                            label: S.newDot,
                            child: Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(left: 8, top: 5),
                              decoration: const BoxDecoration(color: AppColors.roseDark, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                    if ((n.body ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(n.body!, style: theme.textTheme.bodyMedium?.copyWith(height: 1.35)),
                    ],
                    if (n.at != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        S.relativeTime(n.at!, now),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ],
                ),
              ),
              if (route.tappable) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
