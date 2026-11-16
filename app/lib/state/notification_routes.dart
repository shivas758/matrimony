import '../models/notifications.dart';
import '../ui/strings.dart';

/// The two groups of the Notifications screen (SPEC §9.14).
enum NotificationGroup { action, update }

/// Bottom-nav tabs of the home shell, in order.
enum HomeTab { profiles, requests, clients, shortlists, more }

/// Sub-tabs the notifications can land on.
class HomeSubTabs {
  static const requestsInbox = 0;
  static const clientsList = 0;
  static const clientsInterests = 1;
  static const clientsTransfers = 2;
  static const clientsDeletes = 3;
}

/// Where tapping a notification goes (SPEC §9.14 table). Pure data so the
/// routing decision is testable without widgets.
sealed class NotificationTarget {
  const NotificationTarget();
}

/// Switch the home shell to [tab] (and its [subTab], when it has tabs).
class TabTarget extends NotificationTarget {
  const TabTarget(this.tab, [this.subTab]);
  final HomeTab tab;
  final int? subTab;

  @override
  bool operator ==(Object other) => other is TabTarget && other.tab == tab && other.subTab == subTab;
  @override
  int get hashCode => Object.hash(tab, subTab);
}

class ProfileTarget extends NotificationTarget {
  const ProfileTarget(this.profileId);
  final int profileId;

  @override
  bool operator ==(Object other) => other is ProfileTarget && other.profileId == profileId;
  @override
  int get hashCode => profileId.hashCode;
}

class ClientTarget extends NotificationTarget {
  const ClientTarget(this.customerId);
  final int customerId;

  @override
  bool operator ==(Object other) => other is ClientTarget && other.customerId == customerId;
  @override
  int get hashCode => customerId.hashCode;
}

/// My communities (Settings).
class SettingsTarget extends NotificationTarget {
  const SettingsTarget();
  @override
  bool operator ==(Object other) => other is SettingsTarget;
  @override
  int get hashCode => 1;
}

/// My gift codes (SPEC §9.23 B) — a family used one of them.
class GiftCodesTarget extends NotificationTarget {
  const GiftCodesTarget();
  @override
  bool operator ==(Object other) => other is GiftCodesTarget;
  @override
  int get hashCode => 7;
}

/// Admin → Agents, filtered to pending.
class AdminPendingAgentsTarget extends NotificationTarget {
  const AdminPendingAgentsTarget();
  @override
  bool operator ==(Object other) => other is AdminPendingAgentsTarget;
  @override
  int get hashCode => 2;
}

/// Admin → Password resets.
class AdminPasswordResetsTarget extends NotificationTarget {
  const AdminPasswordResetsTarget();
  @override
  bool operator ==(Object other) => other is AdminPasswordResetsTarget;
  @override
  int get hashCode => 3;
}

/// Admin → Payments to verify (SPEC §9.20 D).
class AdminPaymentsTarget extends NotificationTarget {
  const AdminPaymentsTarget();
  @override
  bool operator ==(Object other) => other is AdminPaymentsTarget;
  @override
  int get hashCode => 4;
}

/// Admin → Reports (SPEC §9.22 A).
class AdminReportsTarget extends NotificationTarget {
  const AdminReportsTarget();
  @override
  bool operator ==(Object other) => other is AdminReportsTarget;
  @override
  int get hashCode => 6;
}

/// Admin → Account deletion requests (SPEC §9.20 F).
class AdminDeletionRequestsTarget extends NotificationTarget {
  const AdminDeletionRequestsTarget();
  @override
  bool operator ==(Object other) => other is AdminDeletionRequestsTarget;
  @override
  int get hashCode => 5;
}

const _actionTypes = {
  'contact_request_received',
  'hold_request_received',
  'client_pending',
  'interest_received',
  'agent_change_requested',
  'profile_delete_requested',
};

const _adminActionTypes = {
  'agent_pending',
  'password_reset_requested',
  'payment_to_verify',
  'deletion_requested',
  'report_received',
};

/// "Needs your action" or "Updates" — unknown types are updates.
NotificationGroup notificationGroup(String type, {required bool isAdmin}) =>
    _actionTypes.contains(type) || (isAdmin && _adminActionTypes.contains(type))
        ? NotificationGroup.action
        : NotificationGroup.update;

/// Where the item opens, or null when it is not tappable (unknown type,
/// missing id, or an admin-only target for a non-admin).
NotificationTarget? notificationTarget(NotificationItem item, {required bool isAdmin}) {
  final profileId = item.profileId;
  final customerId = item.customerId;
  return switch (item.type) {
    'contact_request_received' ||
    'hold_request_received' =>
      const TabTarget(HomeTab.requests, HomeSubTabs.requestsInbox),
    'contact_request_decided' ||
    'hold_request_decided' =>
      profileId == null ? null : ProfileTarget(profileId),
    // My communities: the decision, or my fee payment the admin rejected
    // (SPEC §9.20 C) — submit a corrected UTR there.
    'community_request_decided' || 'payment_rejected' => const SettingsTarget(),
    'agent_pending' => isAdmin ? const AdminPendingAgentsTarget() : null,
    'password_reset_requested' => isAdmin ? const AdminPasswordResetsTarget() : null,
    'payment_to_verify' => isAdmin ? const AdminPaymentsTarget() : null,
    'deletion_requested' => isAdmin ? const AdminDeletionRequestsTarget() : null,
    'report_received' => isAdmin ? const AdminReportsTarget() : null,
    'client_pending' ||
    'interest_decided' ||
    'agent_change_decided' ||
    'profile_delete_requested' =>
      customerId == null ? null : ClientTarget(customerId),
    'interest_received' => const TabTarget(HomeTab.clients, HomeSubTabs.clientsInterests),
    // SPEC §9.23 A / B (informational): approved → the now wider Profiles
    // tab; a family used my code → Gift codes.
    'agent_approved' => const TabTarget(HomeTab.profiles),
    'gift_code_used' => const GiftCodesTarget(),
    'agent_change_requested' => const TabTarget(HomeTab.clients, HomeSubTabs.clientsTransfers),
    _ => null,
  };
}

/// "Just now", "5 min ago", "3 h ago", "Yesterday", "4 days ago", then the
/// date ("12 Sep 2026").
String relativeTime(DateTime? at, DateTime now) {
  if (at == null) return '';
  final diff = now.difference(at);
  if (diff.isNegative || diff.inMinutes < 1) return S.justNow;
  if (diff.inMinutes < 60) return S.minutesAgo(diff.inMinutes);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days == 0) return S.hoursAgo(diff.inHours);
  if (days == 1) return S.yesterday;
  if (days < 7) return S.daysAgo(days);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${at.day} ${months[at.month - 1]} ${at.year}';
}
