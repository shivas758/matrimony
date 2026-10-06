/// One Gandharva notification — GET /customer/notifications (SPEC §9.15).
/// Derived by the server from existing rows; there is no read state on the
/// server, the app keeps a per-device "last opened" timestamp.
class AppNotification {
  const AppNotification({
    required this.type,
    required this.group,
    required this.id,
    required this.title,
    this.body,
    this.at,
    this.profileId,
    this.myProfileId,
    this.interestId,
  });

  /// payment_due, interest_expiring (action); account_approved,
  /// account_rejected, interest_accepted / declined / revoked,
  /// payment_received, agent_change_approved / rejected,
  /// delete_request_approved / rejected (update). Unknown types are listed
  /// but not tappable.
  final String type;

  /// 'action' | 'update'
  final String group;
  final int id;
  final String title;
  final String? body;

  /// When it happened (for interest_expiring: when access ends — may be in
  /// the future).
  final DateTime? at;

  /// Someone else's profile (interest_*).
  final int? profileId;

  /// One of MY profiles (payment_due, payment_received, delete_request_*).
  final int? myProfileId;
  final int? interestId;

  bool get isAction => group == 'action';

  /// Stable key for lists.
  String get key => '$type:$id';

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        type: '${j['type'] ?? ''}',
        group: j['group'] == 'action' ? 'action' : 'update',
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: '${j['title'] ?? ''}',
        body: j['body'] as String?,
        at: j['at'] == null ? null : DateTime.tryParse('${j['at']}')?.toLocal(),
        profileId: (j['profile_id'] as num?)?.toInt(),
        myProfileId: (j['my_profile_id'] as num?)?.toInt(),
        interestId: (j['interest_id'] as num?)?.toInt(),
      );
}

/// The whole answer: `{action_count, items}`.
class NotificationFeed {
  const NotificationFeed({this.actionCount = 0, this.items = const []});

  final int actionCount;
  final List<AppNotification> items;

  static const empty = NotificationFeed();

  /// "Needs your action", in server order.
  List<AppNotification> get actions => items.where((n) => n.isAction).toList();

  /// "Updates", in server order (newest first).
  List<AppNotification> get updates => items.where((n) => !n.isAction).toList();

  /// An update the customer has not seen: newer than the last time the
  /// screen was opened (everything is new before the first opening).
  static bool isNew(AppNotification n, DateTime? lastOpened) {
    if (n.isAction) return false;
    if (lastOpened == null) return true;
    final at = n.at;
    return at != null && at.isAfter(lastOpened);
  }

  /// The bell: every action item + unseen updates (SPEC §9.15).
  int badgeCount(DateTime? lastOpened) =>
      actionCount + updates.where((n) => isNew(n, lastOpened)).length;

  factory NotificationFeed.fromJson(Map<String, dynamic> j) {
    final items = (j['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AppNotification.fromJson)
        .toList();
    return NotificationFeed(
      actionCount: (j['action_count'] as num?)?.toInt() ?? items.where((n) => n.isAction).length,
      items: items,
    );
  }
}

/// Where tapping a notification goes (SPEC §9.15 table).
enum NotificationDestination {
  /// One of my profiles → MyProfileScreen([NotificationRoute.id]).
  ownProfile,

  /// Someone else's profile → ProfileDetailScreen([NotificationRoute.id]).
  profileDetail,
  myProfilesTab,
  moreTab,
  getStarted,

  /// Unknown type / missing id: listed, not tappable.
  none,
}

class NotificationRoute {
  const NotificationRoute(this.destination, [this.id]);

  final NotificationDestination destination;
  final int? id;

  bool get tappable => destination != NotificationDestination.none;

  static const none = NotificationRoute(NotificationDestination.none);

  @override
  bool operator ==(Object other) =>
      other is NotificationRoute && other.destination == destination && other.id == id;

  @override
  int get hashCode => Object.hash(destination, id);

  @override
  String toString() => 'NotificationRoute($destination, $id)';
}

/// The routing decision, kept pure so it is testable.
NotificationRoute routeFor(AppNotification n) {
  NotificationRoute ownOr(NotificationRoute fallback) => n.myProfileId != null
      ? NotificationRoute(NotificationDestination.ownProfile, n.myProfileId)
      : fallback;
  const myProfiles = NotificationRoute(NotificationDestination.myProfilesTab);

  switch (n.type) {
    case 'payment_due':
      return ownOr(myProfiles);
    case 'interest_expiring':
    case 'interest_accepted':
    case 'interest_declined':
    case 'interest_revoked':
      return n.profileId == null
          ? NotificationRoute.none
          : NotificationRoute(NotificationDestination.profileDetail, n.profileId);
    case 'account_approved':
    case 'delete_request_approved':
      return myProfiles;
    case 'account_rejected':
      return const NotificationRoute(NotificationDestination.getStarted);
    case 'payment_received':
    case 'delete_request_rejected':
      return ownOr(myProfiles);
    case 'agent_change_approved':
    case 'agent_change_rejected':
      return const NotificationRoute(NotificationDestination.moreTab);
    default:
      return NotificationRoute.none;
  }
}
