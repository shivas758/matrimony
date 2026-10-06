import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/home_tab.dart';
import '../../state/notifications_state.dart';
import '../screens/notifications/notifications_screen.dart';
import '../strings.dart';

/// The app-bar bell (SPEC §9.15): action items + unseen updates as a badge;
/// tap → Notifications. Tolerates a missing [NotificationsState] /
/// [HomeTab] (a screen shown outside the home shell).
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotificationsState?>();
    if (state == null) return const SizedBox.shrink();
    final count = state.badgeCount;
    return IconButton(
      tooltip: S.notifications,
      onPressed: () => NotificationsScreen.open(context, tabs: context.read<HomeTab?>()),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(count > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
      ),
    );
  }
}
