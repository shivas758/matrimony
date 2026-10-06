import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/contact_request.dart';
import '../../../models/hold_request.dart';
import '../../../services/api_client.dart';
import '../../../services/contact_service.dart';
import '../../../services/hold_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/home_nav.dart';
import '../../../state/notification_routes.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../profiles/profile_detail_screen.dart';
import '../notifications_screen.dart';

/// Inbox (decide) and Sent (track) tabs — SPEC §5 screen 7. Each tab lists
/// hold requests first (they block a profile for everyone) and contact
/// requests below.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

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
    if (_nav.tab != HomeTab.requests) return;
    final sub = _nav.takeSubTab(HomeTab.requests);
    if (sub != null && sub < _tabs.length) _tabs.animateTo(sub);
  }

  @override
  void dispose() {
    _nav.removeListener(_onNav);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text(S.requests),
          actions: const [NotificationBell()],
          bottom: TabBar(
            controller: _tabs,
            tabs: const [Tab(text: S.inbox), Tab(text: S.sent)],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: const [
            _RequestList(box: RequestBox.inbox),
            _RequestList(box: RequestBox.sent),
          ],
        ),
      );
}

class _RequestList extends StatefulWidget {
  const _RequestList({required this.box});

  final RequestBox box;

  @override
  State<_RequestList> createState() => _RequestListState();
}

class _RequestListState extends State<_RequestList> with AutomaticKeepAliveClientMixin {
  List<ContactRequest> _items = [];
  List<HoldRequest> _holds = [];
  bool _loading = true;
  String? _error;
  int? _busyId;
  int? _busyHoldId;

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
      final contacts = context.read<ContactService>().list(widget.box);
      final holds = context.read<HoldService>().list(widget.box);
      final results = await Future.wait([contacts, holds]);
      if (mounted) {
        setState(() {
          _items = results[0] as List<ContactRequest>;
          _holds = results[1] as List<HoldRequest>;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(ContactRequest r, String action) async {
    setState(() => _busyId = r.id);
    try {
      final service = context.read<ContactService>();
      final updated = switch (action) {
        'approve' => await service.approve(r.id),
        'reject' => await service.reject(r.id),
        _ => await service.revoke(r.id),
      };
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((x) => x.id == r.id);
        if (i >= 0) _items[i] = updated;
      });
      context.read<AuthState>().refreshNotifications();
      showSnack(context, switch (action) {
        'approve' => 'Approved — access valid for ${updated.daysLeft ?? 15} days',
        'reject' => 'Request rejected',
        _ => 'Access revoked',
      });
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _confirmRevoke(ContactRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.revoke),
        content: Text(
          '${r.requesterName ?? 'This agent'} will immediately lose access to the contact '
          'details for ${r.profileName}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.revoke)),
        ],
      ),
    );
    if (ok == true) await _decide(r, 'revoke');
  }

  /// approve | reject | release | cancel on a hold request.
  Future<void> _decideHold(HoldRequest h, String action) async {
    setState(() => _busyHoldId = h.id);
    try {
      final service = context.read<HoldService>();
      final updated = switch (action) {
        'approve' => await service.approve(h.id),
        'reject' => await service.reject(h.id),
        'release' => await service.release(h.id),
        _ => await service.cancel(h.id),
      };
      if (!mounted) return;
      // Approving one hold turns the other pending ones down — reload the list.
      if (action == 'approve') {
        await _load();
      } else {
        setState(() {
          final i = _holds.indexWhere((x) => x.id == h.id);
          if (i >= 0) _holds[i] = updated;
        });
      }
      if (!mounted) return;
      context.read<AuthState>().refreshNotifications();
      showSnack(context, switch (action) {
        'approve' => 'On hold — hidden from other agents until released',
        'reject' => 'Hold request rejected',
        'release' => S.holdReleasedMsg,
        _ => 'Hold request cancelled',
      });
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyHoldId = null);
    }
  }

  Future<void> _confirmRelease(HoldRequest h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.releaseHold),
        content: Text('${h.profileName} becomes visible to other agents again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.releaseHold)),
        ],
      ),
    );
    if (ok == true) await _decideHold(h, 'release');
  }

  void _openProfile(int profileId) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileId: profileId)),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final api = context.read<ApiClient>();
    final theme = Theme.of(context);
    final isInbox = widget.box == RequestBox.inbox;

    if (_loading && _items.isEmpty && _holds.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty && _holds.isEmpty) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty && _holds.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
            EmptyState(
              icon: isInbox ? Icons.inbox_rounded : Icons.outbox_rounded,
              title: isInbox ? S.noInbox : S.noSent,
            ),
          ],
        ),
      );
    }

    // One flat list: [hold header, holds…, contact header, contacts…].
    final rows = <Widget>[
      if (_holds.isNotEmpty) ...[
        _GroupHeader(S.holdRequests, count: _holds.where((h) => h.isPending).length),
        for (final h in _holds) _holdTile(h, api, theme, isInbox),
      ],
      if (_items.isNotEmpty) ...[
        _GroupHeader(S.contactRequests, count: _items.where((r) => r.isPending).length),
        for (final r in _items) _contactTile(r, api, theme, isInbox),
      ],
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: rows.length,
        separatorBuilder: (_, i) =>
            rows[i + 1] is _GroupHeader ? const SizedBox.shrink() : const Divider(height: 1),
        itemBuilder: (_, i) => rows[i],
      ),
    );
  }

  Widget _profileHeader({
    required ApiClient api,
    required ThemeData theme,
    required String? photoUrl,
    required String name,
    required String subtitle,
    required String statusLabel,
    required String statusKey,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 52,
                height: 52,
                child: AuthedPhoto(url: photoUrl, api: api, placeholderInitials: initialsOf(name)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 6),
                  StatusChip(
                    label: statusLabel,
                    color: StatusColors.forRequestStatus(statusKey, theme.colorScheme),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _requesterLine(ThemeData theme, String? name, String? agency) => Row(
        children: [
          Icon(Icons.person_rounded, size: 15, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [name, agency].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      );

  Widget _note(ThemeData theme, String note) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('"$note"', style: theme.textTheme.bodySmall),
      );

  Widget _decisionRow({
    required bool busy,
    required VoidCallback onReject,
    required VoidCallback onApprove,
    String approveLabel = S.approve,
  }) =>
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: busy ? null : onReject,
              child: const Text(S.reject),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: busy ? null : onApprove,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(approveLabel),
            ),
          ),
        ],
      );

  Widget _holdTile(HoldRequest h, ApiClient api, ThemeData theme, bool isInbox) {
    final busy = _busyHoldId == h.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _profileHeader(
            api: api,
            theme: theme,
            photoUrl: h.photoAbsoluteUrl,
            name: h.profileName,
            subtitle: [h.genderLabel, h.profileCommunity].whereType<String>().join(' · '),
            statusLabel: h.statusLabel,
            statusKey: h.status,
            onTap: () => _openProfile(h.profileId),
          ),
          // Only the inbox reveals who is asking (CLAUDE.md rule 3).
          if (isInbox && h.requesterName != null) ...[
            const SizedBox(height: 10),
            _requesterLine(theme, h.requesterName, h.requesterAgency),
          ],
          if ((h.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            _note(theme, h.note!),
          ],
          if (isInbox && h.isPending) ...[
            const SizedBox(height: 12),
            _decisionRow(
              busy: busy,
              onReject: () => _decideHold(h, 'reject'),
              onApprove: () => _decideHold(h, 'approve'),
              approveLabel: S.putOnHold,
            ),
          ],
          // The holder, the uploader or an admin can release; the requester can
          // withdraw a pending ask.
          if (h.isApproved && (isInbox || h.isMine)) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : () => _confirmRelease(h),
                icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                label: const Text(S.releaseHold),
              ),
            ),
          ],
          if (!isInbox && h.isPending && h.isMine) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : () => _decideHold(h, 'cancel'),
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text(S.cancelHoldRequest),
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _contactTile(ContactRequest r, ApiClient api, ThemeData theme, bool isInbox) {
    final busy = _busyId == r.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _profileHeader(
            api: api,
            theme: theme,
            photoUrl: r.photoAbsoluteUrl,
            name: r.profileName,
            subtitle: [r.genderLabel, r.profileCommunity].whereType<String>().join(' · '),
            statusLabel: r.statusLabel,
            statusKey: r.status,
            onTap: () => _openProfile(r.profileId),
          ),
          // Only the inbox reveals who is asking — the sent box must never
          // expose the uploader's identity (CLAUDE.md rule 3).
          if (isInbox && r.requesterName != null) ...[
            const SizedBox(height: 10),
            _requesterLine(theme, r.requesterName, r.requesterAgency),
          ],
          if ((r.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            _note(theme, r.note!),
          ],
          if (isInbox && r.isPending) ...[
            const SizedBox(height: 12),
            _decisionRow(
              busy: busy,
              onReject: () => _decide(r, 'reject'),
              onApprove: () => _decide(r, 'approve'),
            ),
          ],
          if (isInbox && r.isApproved) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : () => _confirmRevoke(r),
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text(S.revoke),
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.title, {required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SectionHeader(
          title,
          trailing: count > 0
              ? StatusChip(label: '$count pending', color: const Color(0xFFEF6C00))
              : null,
        ),
      );
}
