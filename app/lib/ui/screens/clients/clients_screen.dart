import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/agent_change.dart';
import '../../../models/customer.dart';
import '../../../models/delete_request.dart';
import '../../../models/interest.dart';
import '../../../services/api_client.dart';
import '../../../services/clients_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/home_nav.dart';
import '../../../state/notification_routes.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'client_detail_screen.dart';
import 'client_widgets.dart';
import '../notifications_screen.dart';

/// Clients · Interests · Transfers (SPEC §9.11). The app-bar action opens the
/// registration-form link sheet (SPEC §9.3-B).
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  late final HomeNav _nav = context.read<HomeNav>();

  @override
  void initState() {
    super.initState();
    _nav.addListener(_onNav);
    // A push tapped before this screen existed may already be waiting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onNav();
    });
  }

  /// A notification asked for one of my sub-tabs (SPEC §9.14).
  void _onNav() {
    if (_nav.tab != HomeTab.clients) return;
    final sub = _nav.takeSubTab(HomeTab.clients);
    if (sub != null && sub < _tabs.length) _tabs.animateTo(sub);
  }

  @override
  void dispose() {
    _nav.removeListener(_onNav);
    _tabs.dispose();
    super.dispose();
  }

  void _showRegistrationSheet() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _RegistrationLinkSheet(),
      );

  Widget _tab(String label, int count) => Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Badge(label: Text('$count')),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final n = context.watch<AuthState>().notifications;
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.clients),
        actions: [
          IconButton(
            tooltip: S.registrationForm,
            icon: const Icon(Icons.post_add_rounded),
            onPressed: _showRegistrationSheet,
          ),
          const NotificationBell(),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            _tab(S.clients, n.pendingClients),
            _tab(S.interests, n.interestsInbox),
            _tab(S.transfers, n.agentChangeInbox),
            _tab(S.deletesTab, n.deleteRequestsInbox),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ClientsTab(),
          _InterestsTab(),
          _TransfersTab(),
          _DeletesTab(),
        ],
      ),
    );
  }
}

// ================================================================ Clients

class _ClientsTab extends StatefulWidget {
  const _ClientsTab();

  @override
  State<_ClientsTab> createState() => _ClientsTabState();
}

class _ClientsTabState extends State<_ClientsTab> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  List<Customer> _items = [];
  bool _loading = true;
  String? _error;
  int? _busyId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context.read<ClientsService>().list(q: _search.text.trim());
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Customer c, String action) async {
    setState(() => _busyId = c.id);
    try {
      final service = context.read<ClientsService>();
      final updated = switch (action) {
        'approve' => await service.approve(c.id),
        'reject' => await service.reject(c.id),
        'suspend' => await service.suspend(c.id),
        _ => await service.activate(c.id),
      };
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((x) => x.id == c.id);
        if (i >= 0) _items[i] = updated;
      });
      context.read<AuthState>().refreshNotifications();
      showSnack(context, switch (action) {
        'approve' => S.clientApproved,
        'reject' => S.clientRejected,
        'suspend' => S.clientSuspended,
        _ => S.clientActivated,
      });
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _confirmReject(Customer c) async {
    final ok = await confirmAction(
      context,
      title: '${S.reject} ${c.fullName}?',
      body: '${c.fullName} ${S.rejectClientBody}',
      confirmLabel: S.reject,
      destructive: true,
    );
    if (ok) await _act(c, 'reject');
  }

  Future<void> _open(Customer c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClientDetailScreen(customerId: c.id)),
    );
    // Status may have changed on the detail screen.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final searching = _search.text.trim().isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            onChanged: (v) {
              if (v.isEmpty) _load();
            },
            decoration: InputDecoration(
              hintText: S.searchClients,
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: searching
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        _load();
                      },
                    )
                  : null,
            ),
          ),
        ),
        Expanded(child: _body(theme, searching)),
      ],
    );
  }

  Widget _body(ThemeData theme, bool searching) {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return ErrorState(message: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.14),
            EmptyState(
              icon: Icons.people_alt_outlined,
              title: searching ? S.noClientMatches : S.noClients,
              message: searching ? null : S.noClientsHint,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _ClientTile(
          client: _items[i],
          busy: _busyId == _items[i].id,
          onTap: () => _open(_items[i]),
          onApprove: () => _act(_items[i], 'approve'),
          onReject: () => _confirmReject(_items[i]),
        ),
      ),
    );
  }
}

class _ClientTile extends StatelessWidget {
  const _ClientTile({
    required this.client,
    required this.busy,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
  });

  final Customer client;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = client;
    final greyed = c.isSuspended || c.isRejected;
    final change = c.pendingAgentChange;

    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: greyed ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(name: c.fullName),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '+91 ${c.phone} · ${formatDate(c.createdAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    label: c.statusLabel,
                    color: clientStatusColor(c.status, theme.colorScheme),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (c.profile != null)
                    StatusChip(
                      label: '${S.profilePrefix}${c.profile!.fullName}',
                      color: AppColors.navy,
                      icon: Icons.badge_outlined,
                    )
                  else
                    StatusChip(
                      label: S.noProfileYet,
                      color: theme.colorScheme.outline,
                      icon: Icons.person_off_outlined,
                    ),
                  if (c.allProfiles.length > 1)
                    StatusChip(
                      label: S.profilesCount(c.allProfiles.length),
                      color: AppColors.navyLight,
                      icon: Icons.people_outline_rounded,
                    ),
                  if (c.hasUnpaidProfile)
                    StatusChip(
                      label: S.feePending,
                      color: AppColors.warning,
                      icon: Icons.currency_rupee_rounded,
                    ),
                  SourceChip(source: c.source),
                  if (c.interestsCount > 0)
                    StatusChip(
                      label: interestsCountLabel(c.interestsCount),
                      color: AppColors.goldDark,
                      icon: Icons.favorite_outline_rounded,
                    ),
                  if (c.hasDeleteRequest)
                    StatusChip(
                      label: S.deleteRequestChip,
                      color: theme.colorScheme.error,
                      icon: Icons.delete_outline_rounded,
                    ),
                  if (change != null)
                    StatusChip(
                      label: '${S.wantsToMoveTo} ${change.toAgent.fullName}',
                      color: AppColors.warning,
                      icon: Icons.swap_horiz_rounded,
                    ),
                ],
              ),
              if (c.isPending) ...[
                const SizedBox(height: 12),
                DecisionRow(busy: busy, onReject: onReject, onApprove: onApprove),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  static const double size = 44;

  final String name;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.navyTint,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        alignment: Alignment.center,
        child: Text(
          initialsOf(name),
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
            fontVariations: const [FontVariation('wght', 600)],
            color: AppColors.navy,
          ),
        ),
      );
}

// ================================================================ Interests

class _InterestsTab extends StatefulWidget {
  const _InterestsTab();

  @override
  State<_InterestsTab> createState() => _InterestsTabState();
}

class _InterestsTabState extends State<_InterestsTab> with AutomaticKeepAliveClientMixin {
  List<Interest> _items = [];
  bool _loading = true;
  String? _error;
  int? _busyId;

  @override
  bool get wantKeepAlive => true;

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
      final items = await context.read<ClientsService>().interests(box: InterestBox.received);
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Interest it, String action) async {
    setState(() => _busyId = it.id);
    try {
      final service = context.read<ClientsService>();
      final updated = switch (action) {
        'accept' => await service.acceptInterest(it.id),
        'decline' => await service.declineInterest(it.id),
        _ => await service.revokeInterest(it.id),
      };
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((x) => x.id == it.id);
        if (i >= 0) _items[i] = updated;
      });
      context.read<AuthState>().refreshNotifications();
      showSnack(context, switch (action) {
        'accept' => S.interestAccepted,
        'decline' => S.interestDeclined,
        _ => S.interestRevoked,
      });
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _confirmRevoke(Interest it) async {
    final ok = await confirmAction(
      context,
      title: S.revoke,
      body: S.revokeInterestBody,
      confirmLabel: S.revokeShort,
      destructive: true,
    );
    if (ok) await _act(it, 'revoke');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return ErrorState(message: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
            const EmptyState(
              icon: Icons.favorite_outline_rounded,
              title: S.noInterests,
              message: S.noInterestsHint,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => InterestCard(
          interest: _items[i],
          busy: _busyId == _items[i].id,
          onAccept: () => _act(_items[i], 'accept'),
          onDecline: () => _act(_items[i], 'decline'),
          onRevoke: () => _confirmRevoke(_items[i]),
        ),
      ),
    );
  }
}

/// One interest as the target profile's uploader sees it: who is asking,
/// their agent's contact, the profile, and the decision buttons. Also used
/// on the client detail screen (there `targetAgent` is the other party).
class InterestCard extends StatelessWidget {
  const InterestCard({
    super.key,
    required this.interest,
    required this.busy,
    this.onAccept,
    this.onDecline,
    this.onRevoke,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  });

  final Interest interest;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onRevoke;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final it = interest;
    final profile = it.profile;
    final customerProfile = it.customerProfile;
    final otherAgent = it.otherAgent;
    final showAgent = otherAgent != null && (it.isPending || it.isAccepted);
    final canAct = it.canDecide && onAccept != null && onDecline != null;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Priya is interested in"
          Row(
            children: [
              const Icon(Icons.favorite_rounded, size: 18, color: AppColors.goldDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: it.customer.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: ' ${S.isInterestedIn}',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                formatDate(it.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (profile != null)
            SurfaceCard(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: ProfileSummaryTile(profile: profile),
            ),
          if ((it.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            NoteBox(it.note!),
          ],
          // The interested customer's own profile is visible to the uploader
          // while the interest is live (SPEC §9.4 visibility side-effect).
          if (customerProfile != null && it.customerAgent != null) ...[
            const SizedBox(height: 8),
            ProfileSummaryTile(
              profile: customerProfile,
              label: S.theirProfile,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            ),
          ] else if (customerProfile != null) ...[
            // The client's own agent: which of their profiles is interested
            // (SPEC §9.12 — a customer can have up to 5).
            const SizedBox(height: 8),
            ProfileSummaryTile(
              profile: customerProfile,
              label: S.onBehalfOf,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            ),
          ],
          if (showAgent) ...[
            const SizedBox(height: 8),
            ContactLine(
              caption: it.customerAgent != null ? S.theirAgent : S.uploadedBy,
              name: otherAgent.fullName,
              subtitle: otherAgent.agencyName,
              phone: otherAgent.phone,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              StatusChip(
                label: it.statusLabel,
                color: clientStatusColor(it.status, theme.colorScheme),
                icon: it.isAccepted ? Icons.lock_open_rounded : null,
              ),
              const Spacer(),
              if (it.isAccepted && it.canDecide && onRevoke != null)
                TextButton.icon(
                  onPressed: busy ? null : onRevoke,
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text(S.revokeShort),
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                ),
            ],
          ),
          if (it.isPending && canAct) ...[
            const SizedBox(height: 8),
            DecisionRow(
              busy: busy,
              onReject: onDecline!,
              onApprove: onAccept!,
              rejectLabel: S.decline,
              approveLabel: S.accept,
            ),
          ],
        ],
      ),
    );
  }
}

// ================================================================ Transfers

class _TransfersTab extends StatefulWidget {
  const _TransfersTab();

  @override
  State<_TransfersTab> createState() => _TransfersTabState();
}

class _TransfersTabState extends State<_TransfersTab> with AutomaticKeepAliveClientMixin {
  List<AgentChangeRequest> _outgoing = [];
  List<AgentChangeRequest> _incoming = [];
  bool _loading = true;
  String? _error;
  int? _busyId;

  @override
  bool get wantKeepAlive => true;

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
      final service = context.read<ClientsService>();
      final results = await Future.wait([
        service.agentChangeRequests(box: TransferBox.outgoing),
        service.agentChangeRequests(box: TransferBox.incoming),
      ]);
      if (mounted) {
        // Admins get every request in both boxes — show each one once.
        final seen = results[0].map((r) => r.id).toSet();
        setState(() {
          _outgoing = results[0];
          _incoming = results[1].where((r) => !seen.contains(r.id)).toList();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(AgentChangeRequest r, String action) async {
    setState(() => _busyId = r.id);
    try {
      final service = context.read<ClientsService>();
      final updated = action == 'approve'
          ? await service.approveAgentChange(r.id)
          : await service.rejectAgentChange(r.id);
      if (!mounted) return;
      setState(() {
        final i = _outgoing.indexWhere((x) => x.id == r.id);
        if (i >= 0) _outgoing[i] = updated;
      });
      context.read<AuthState>().refreshNotifications();
      showSnack(context, action == 'approve' ? S.transferApproved : S.transferRejected);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _confirmApprove(AgentChangeRequest r) async {
    final ok = await confirmAction(
      context,
      title: '${r.customer.fullName} → ${r.toAgent.fullName}',
      body: S.approveTransferBody,
      confirmLabel: S.approve,
    );
    if (ok) await _act(r, 'approve');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final empty = _outgoing.isEmpty && _incoming.isEmpty;
    if (_loading && empty) return const Center(child: CircularProgressIndicator());
    if (_error != null && empty) return ErrorState(message: _error!, onRetry: _load);
    if (empty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
            const EmptyState(
              icon: Icons.swap_horiz_rounded,
              title: S.noTransfers,
              message: S.noTransfersHint,
            ),
          ],
        ),
      );
    }

    final rows = <Widget>[
      if (_outgoing.isNotEmpty) ...[
        GroupHeader(S.needsYourDecision, count: _outgoing.where((r) => r.isPending).length),
        for (final r in _outgoing)
          TransferTile(
            request: r,
            busy: _busyId == r.id,
            onApprove: () => _confirmApprove(r),
            onReject: () => _act(r, 'reject'),
          ),
      ],
      if (_incoming.isNotEmpty) ...[
        GroupHeader(S.movingToYou),
        for (final r in _incoming) TransferTile(request: r, busy: false),
      ],
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: rows.length,
        separatorBuilder: (_, i) =>
            rows[i + 1] is GroupHeader ? const SizedBox.shrink() : const Divider(height: 1),
        itemBuilder: (_, i) => rows[i],
      ),
    );
  }
}

// ================================================================ Deletes

/// Pending requests to delete a paid profile (SPEC §9.13) across my clients
/// (admin: all), so the agent does not have to open every client.
class _DeletesTab extends StatefulWidget {
  const _DeletesTab();

  @override
  State<_DeletesTab> createState() => _DeletesTabState();
}

class _DeletesTabState extends State<_DeletesTab> with AutomaticKeepAliveClientMixin {
  List<ProfileDeleteRequest> _items = [];
  bool _loading = true;
  String? _error;
  int? _busyId;

  @override
  bool get wantKeepAlive => true;

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
      final items = await context.read<ClientsService>().deleteRequests();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(ProfileDeleteRequest r, String action) async {
    setState(() => _busyId = r.id);
    final changed = await decideDeleteRequest(context, r, action);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (changed) _load();
  }

  Future<void> _openClient(ProfileDeleteRequest r) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ClientDetailScreen(customerId: r.customer.id)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return ErrorState(message: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.16),
            const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: S.noDeleteRequests,
              message: S.noDeleteRequestsHint,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _items[i];
          return DeleteRequestTile(
            request: r,
            busy: _busyId == r.id,
            onApprove: () => _decide(r, 'approve'),
            onReject: () => _decide(r, 'reject'),
            onOpenClient: () => _openClient(r),
          );
        },
      ),
    );
  }
}

/// One agent-change request. Outgoing ("Priya wants to move to Suresh, Om
/// Bureau") gets Approve / Reject while pending; incoming ("Priya joining you
/// from Lakshmi, Sri Bureau") is read-only. Shared with the client detail screen.
class TransferTile extends StatelessWidget {
  const TransferTile({
    super.key,
    required this.request,
    required this.busy,
    this.onApprove,
    this.onReject,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  });

  final AgentChangeRequest request;
  final bool busy;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    final incoming = r.isIncoming;
    final other = incoming ? r.fromAgent : r.toAgent;
    final verb = incoming
        ? S.joiningYouFrom
        : r.status == 'approved'
            ? S.movedTo
            : S.wantsToMoveTo;
    final decide = r.isPending && r.canDecide && onApprove != null && onReject != null;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                incoming ? Icons.login_rounded : Icons.logout_rounded,
                size: 20,
                color: incoming ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: r.customer.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: ' $verb ', style: TextStyle(color: theme.colorScheme.outline)),
                      TextSpan(
                        text: other.labelComma,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if ((r.customer.phone ?? '').isNotEmpty || other.city != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                [
                  if ((r.customer.phone ?? '').isNotEmpty) '+91 ${r.customer.phone}',
                  if ((other.city ?? '').isNotEmpty) other.city,
                  formatDate(r.createdAt),
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
          if ((r.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            NoteBox(r.note!),
          ],
          const SizedBox(height: 10),
          StatusChip(
            label: r.statusLabel,
            color: clientStatusColor(r.status, theme.colorScheme),
          ),
          if (decide) ...[
            const SizedBox(height: 10),
            DecisionRow(busy: busy, onReject: onReject!, onApprove: onApprove!),
          ],
        ],
      ),
    );
  }
}

// ================================================================ Registration link

/// The agent's permanent registration-form link: copy it, send it on WhatsApp,
/// or rotate it when it has leaked (SPEC §9.3-B).
class _RegistrationLinkSheet extends StatefulWidget {
  const _RegistrationLinkSheet();

  @override
  State<_RegistrationLinkSheet> createState() => _RegistrationLinkSheetState();
}

class _RegistrationLinkSheetState extends State<_RegistrationLinkSheet> {
  RegistrationLink? _link;
  bool _loading = true;
  bool _rotating = false;
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
      final link = await context.read<ClientsService>().registrationLink();
      if (mounted) setState(() => _link = link);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy() {
    final link = _link;
    if (link == null) return;
    Clipboard.setData(ClipboardData(text: link.url));
    showSnack(context, S.linkCopied);
  }

  Future<void> _share() async {
    final link = _link;
    if (link == null) return;
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(link.whatsappText)}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showSnack(context, S.somethingWrong, error: true);
    } on PlatformException {
      if (mounted) showSnack(context, S.somethingWrong, error: true);
    }
  }

  Future<void> _rotate() async {
    final ok = await confirmAction(
      context,
      title: S.rotateLink,
      body: S.rotateLinkBody,
      confirmLabel: S.rotateLink,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _rotating = true);
    try {
      final link = await context.read<ClientsService>().rotateRegistrationLink();
      if (!mounted) return;
      setState(() => _link = link);
      showSnack(context, S.linkRotated);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _link;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.post_add_rounded, color: AppColors.goldDark),
                const SizedBox(width: 10),
                Text(S.registrationForm, style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              S.registrationFormBody,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            if (_loading && link == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && link == null) ...[
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(S.retry),
              ),
            ] else if (link != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(
                  link.url,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.send_rounded, size: 20),
                label: const Text(S.shareWhatsApp),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy_rounded, size: 20),
                label: const Text(S.copyLink),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _rotating ? null : _rotate,
                  icon: const Icon(Icons.autorenew_rounded, size: 16),
                  label: const Text(S.rotateLink),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.outline,
                    textStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
