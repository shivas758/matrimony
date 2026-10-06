class NotificationItem {
  const NotificationItem({
    required this.type,
    required this.title,
    required this.body,
    this.id,
    this.profileId,
    this.customerId,
    this.at,
  });

  final String type;
  final String title;
  final String body;

  /// The request / interest id, where the item type has one.
  final int? id;
  final int? profileId;

  /// Set on the SPEC §9.10 item types (client_pending, interest_*, agent_change_*)
  /// and profile_delete_requested (§9.13).
  final int? customerId;
  final DateTime? at;

  /// Items that open the client detail screen when tapped.
  bool get opensClient =>
      customerId != null &&
      (type == 'client_pending' ||
          type.startsWith('interest_') ||
          type.startsWith('agent_change_') ||
          type == 'profile_delete_requested');

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
        type: '${j['type']}',
        title: '${j['title']}',
        body: '${j['body']}',
        id: (j['id'] as num?)?.toInt(),
        profileId: (j['profile_id'] as num?)?.toInt(),
        customerId: (j['customer_id'] as num?)?.toInt(),
        at: DateTime.tryParse('${j['at']}')?.toLocal(),
      );
}

class NotificationFeed {
  const NotificationFeed({
    required this.badge,
    required this.items,
    required this.contactRequestsInbox,
    required this.pendingAgents,
    this.pendingPasswordResets = 0,
    this.holdRequestsInbox = 0,
    this.pendingClients = 0,
    this.interestsInbox = 0,
    this.agentChangeInbox = 0,
    this.deleteRequestsInbox = 0,
  });

  final int badge;
  final List<NotificationItem> items;
  final int contactRequestsInbox;
  final int pendingAgents;

  /// Hold requests waiting on my uploads (admin: on any upload).
  final int holdRequestsInbox;

  /// Everything the Requests tab needs a decision on.
  int get requestsBadge => contactRequestsInbox + holdRequestsInbox;

  /// Admins only: agents who tapped "Forgot password?" and are waiting.
  final int pendingPasswordResets;

  /// Everything an admin has to act on from the Admin screen.
  int get adminPending => pendingAgents + pendingPasswordResets;

  /// SPEC §9.10 — customers waiting for my approval, pending interests on my
  /// uploads, and my clients asking to move to another agent.
  final int pendingClients;
  final int interestsInbox;
  final int agentChangeInbox;

  /// SPEC §9.13 — my clients asking to delete a paid profile.
  final int deleteRequestsInbox;

  /// Badge on the Clients tab: everything there that needs my decision.
  int get clientsBadge =>
      pendingClients + interestsInbox + agentChangeInbox + deleteRequestsInbox;

  static const empty =
      NotificationFeed(badge: 0, items: [], contactRequestsInbox: 0, pendingAgents: 0);

  factory NotificationFeed.fromJson(Map<String, dynamic> j) {
    final counts = j['counts'] as Map<String, dynamic>? ?? const {};
    return NotificationFeed(
      badge: (j['badge'] as num?)?.toInt() ?? 0,
      items: (j['items'] as List? ?? [])
          .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      contactRequestsInbox: (counts['contact_requests_inbox'] as num?)?.toInt() ?? 0,
      pendingAgents: (counts['pending_agents'] as num?)?.toInt() ?? 0,
      pendingPasswordResets: (counts['pending_password_resets'] as num?)?.toInt() ?? 0,
      holdRequestsInbox: (counts['hold_requests_inbox'] as num?)?.toInt() ?? 0,
      pendingClients: (counts['pending_clients'] as num?)?.toInt() ?? 0,
      interestsInbox: (counts['interests_inbox'] as num?)?.toInt() ?? 0,
      agentChangeInbox: (counts['agent_change_inbox'] as num?)?.toInt() ?? 0,
      deleteRequestsInbox: (counts['delete_requests_inbox'] as num?)?.toInt() ?? 0,
    );
  }
}
