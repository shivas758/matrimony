import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/agent_change.dart';
import '../../../models/customer.dart';
import '../../../models/delete_request.dart';
import '../../../models/interest.dart';
import '../../../services/api_client.dart';
import '../../../services/clients_service.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'client_widgets.dart';
import 'clients_screen.dart';

/// One client (SPEC §9.5 / §9.11): header with phone and status actions, the
/// profile (or "no profile yet"), their interests with the other agent's
/// contact, and any agent-change request. Admins open it from Customers too.
class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({super.key, required this.customerId});

  final int customerId;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  Customer? _client;
  bool _loading = true;
  bool _busy = false;
  int? _busyInterestId;
  int? _busyChangeId;
  int? _busyProfileId;
  int? _busyDeleteId;
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
      final client = await context.read<ClientsService>().detail(widget.customerId);
      if (mounted) setState(() => _client = client);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// approve | reject | suspend | activate — then reload, because the action
  /// response carries no interests / change requests.
  Future<void> _act(String action) async {
    final c = _client;
    if (c == null) return;
    setState(() => _busy = true);
    try {
      final service = context.read<ClientsService>();
      switch (action) {
        case 'approve':
          await service.approve(c.id);
        case 'reject':
          await service.reject(c.id);
        case 'suspend':
          await service.suspend(c.id);
        default:
          await service.activate(c.id);
      }
      if (!mounted) return;
      context.read<AuthState>().refreshNotifications();
      showSnack(context, switch (action) {
        'approve' => S.clientApproved,
        'reject' => S.clientRejected,
        'suspend' => S.clientSuspended,
        _ => S.clientActivated,
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReject() async {
    final c = _client;
    if (c == null) return;
    final ok = await confirmAction(
      context,
      title: '${S.reject} ${c.fullName}?',
      body: '${c.fullName} ${S.rejectClientBody}',
      confirmLabel: S.reject,
      destructive: true,
    );
    if (ok) await _act('reject');
  }

  Future<void> _confirmSuspend() async {
    final c = _client;
    if (c == null) return;
    final ok = await confirmAction(
      context,
      title: '${S.suspend} ${c.fullName}?',
      body: S.suspendClientBody,
      confirmLabel: S.suspend,
      destructive: true,
    );
    if (ok) await _act('suspend');
  }

  Future<void> _decideInterest(Interest it, String action) async {
    setState(() => _busyInterestId = it.id);
    try {
      final service = context.read<ClientsService>();
      switch (action) {
        case 'accept':
          await service.acceptInterest(it.id);
        case 'decline':
          await service.declineInterest(it.id);
        default:
          await service.revokeInterest(it.id);
      }
      if (!mounted) return;
      context.read<AuthState>().refreshNotifications();
      showSnack(context, switch (action) {
        'accept' => S.interestAccepted,
        'decline' => S.interestDeclined,
        _ => S.interestRevoked,
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyInterestId = null);
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
    if (ok) await _decideInterest(it, 'revoke');
  }

  Future<void> _decideChange(AgentChangeRequest r, String action) async {
    if (action == 'approve') {
      final ok = await confirmAction(
        context,
        title: '${r.customer.fullName} → ${r.toAgent.fullName}',
        body: S.approveTransferBody,
        confirmLabel: S.approve,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busyChangeId = r.id);
    try {
      final service = context.read<ClientsService>();
      if (action == 'approve') {
        await service.approveAgentChange(r.id);
      } else {
        await service.rejectAgentChange(r.id);
      }
      if (!mounted) return;
      context.read<AuthState>().refreshNotifications();
      showSnack(context, action == 'approve' ? S.transferApproved : S.transferRejected);
      if (action == 'approve') {
        // The client is no longer mine — back to the list.
        Navigator.of(context).pop();
        return;
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyChangeId = null);
    }
  }

  /// Fee received in cash (SPEC §9.13) — the response is the fresh row;
  /// reload anyway for the embedded interests / requests.
  Future<void> _markPaid(ProfileSummary p) async {
    final c = _client;
    if (c == null) return;
    final note = await askMarkPaid(context, p.fullName);
    if (note == null || !mounted) return;
    setState(() => _busyProfileId = p.id);
    try {
      await context.read<ClientsService>().markPaid(c.id, p.id, note: note);
      if (!mounted) return;
      showSnack(context, S.markedPaid);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _decideDelete(ProfileDeleteRequest r, String action) async {
    setState(() => _busyDeleteId = r.id);
    final changed = await decideDeleteRequest(context, r, action);
    if (!mounted) return;
    setState(() => _busyDeleteId = null);
    if (changed) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _client;
    return Scaffold(
      appBar: AppBar(title: Text(c?.fullName ?? S.clients)),
      body: _loading && c == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && c == null
              ? ErrorState(message: _error!, onRetry: _load)
              : c == null
                  ? const SizedBox.shrink()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          _header(c),
                          const SizedBox(height: 20),
                          SectionHeader(
                            c.allProfiles.length > 1 ? S.clientProfiles : S.clientProfile,
                            trailing: c.allProfiles.length > 1
                                ? StatusChip(
                                    label: '${c.allProfiles.length}',
                                    color: AppColors.goldDark,
                                  )
                                : null,
                          ),
                          _profilesCard(c),
                          const SizedBox(height: 20),
                          SectionHeader(
                            S.interests,
                            trailing: c.interests.isEmpty
                                ? null
                                : StatusChip(
                                    label: '${c.interests.length}',
                                    color: AppColors.goldDark,
                                  ),
                          ),
                          if (c.interests.isEmpty)
                            SurfaceCard(
                              child: Text(
                                S.noClientInterests,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
                              ),
                            )
                          else
                            for (final it in c.interests) ...[
                              SurfaceCard(
                                padding: EdgeInsets.zero,
                                child: InterestCard(
                                  interest: it,
                                  busy: _busyInterestId == it.id,
                                  onAccept: () => _decideInterest(it, 'accept'),
                                  onDecline: () => _decideInterest(it, 'decline'),
                                  onRevoke: () => _confirmRevoke(it),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          if (c.deleteRequests.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SectionHeader(
                              S.deleteRequests,
                              trailing: c.deleteRequests.any((r) => r.isPending)
                                  ? StatusChip(
                                      label: '${c.deleteRequests.where((r) => r.isPending).length}',
                                      color: AppColors.warning,
                                    )
                                  : null,
                            ),
                            for (final r in c.deleteRequests) ...[
                              SurfaceCard(
                                padding: EdgeInsets.zero,
                                child: DeleteRequestTile(
                                  request: r,
                                  busy: _busyDeleteId == r.id,
                                  onApprove: () => _decideDelete(r, 'approve'),
                                  onReject: () => _decideDelete(r, 'reject'),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                          if (c.agentChangeRequests.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const SectionHeader(S.agentChange),
                            for (final r in c.agentChangeRequests) ...[
                              SurfaceCard(
                                padding: EdgeInsets.zero,
                                child: TransferTile(
                                  request: r,
                                  busy: _busyChangeId == r.id,
                                  onApprove: () => _decideChange(r, 'approve'),
                                  onReject: () => _decideChange(r, 'reject'),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _header(Customer c) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  initialsOf(c.fullName),
                  style: const TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    fontVariations: [FontVariation('wght', 600)],
                    color: AppColors.goldLight,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.fullName,
                      style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '+91 ${c.phone}',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          tooltip: 'Copy',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: c.phone));
                            showSnack(context, 'Phone number copied');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusChip(
                label: c.statusLabel,
                color: clientStatusColor(c.status, theme.colorScheme),
              ),
              SourceChip(source: c.source),
              if (c.agent != null)
                StatusChip(
                  label: '${S.agentLabel}: ${c.agent!.label}',
                  color: AppColors.navyLight,
                  icon: Icons.support_agent_rounded,
                )
              else if (c.isGuest)
                StatusChip(
                  label: S.noAgentYet,
                  color: theme.colorScheme.outline,
                  icon: Icons.support_agent_rounded,
                ),
            ],
          ),
          const SizedBox(height: 8),
          DetailRow(label: S.clientSince, value: formatDate(c.createdAt)),
          if (c.approvedAt != null) DetailRow(label: S.approvedOn, value: formatDate(c.approvedAt)),
          if (c.lastLoginAt != null)
            DetailRow(label: S.lastLogin, value: formatDateTime(c.lastLoginAt)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    backgroundColor: AppColors.success.withValues(alpha: 0.14),
                    foregroundColor: AppColors.success,
                  ),
                  onPressed: () => callNumber(context, c.phone),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: const Text(S.call),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: () => whatsAppNumber(context, c.phone),
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: const Text(S.whatsApp),
                ),
              ),
            ],
          ),
          if (c.isPending) ...[
            // SPEC §9.12: approving is allowed, but nothing goes live unpaid.
            if (c.allProfilesUnpaid) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(S.unpaidApproveNote, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            DecisionRow(
              busy: _busy,
              onReject: _confirmReject,
              onApprove: () => _act('approve'),
            ),
          ],
          if (c.isActive) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.6)),
              ),
              onPressed: _busy ? null : _confirmSuspend,
              icon: const Icon(Icons.pause_circle_outline_rounded, size: 18),
              label: const Text(S.suspend),
            ),
          ],
          if (c.isSuspended) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : () => _act('activate'),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
              label: const Text(S.activate),
            ),
          ],
          if (c.isRejected) ...[
            const SizedBox(height: 10),
            Text(
              S.rejectedNote,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }

  /// Every profile of the client (SPEC §9.12, oldest first) with its fee
  /// state; tapping one opens the profile.
  Widget _profilesCard(Customer c) {
    final theme = Theme.of(context);
    final profiles = c.allProfiles;
    if (profiles.isEmpty) {
      return SurfaceCard(
        child: Row(
          children: [
            Icon(Icons.person_off_outlined, color: theme.colorScheme.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                S.noProfileYetBody,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: Column(
        children: [
          for (var i = 0; i < profiles.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _profileRow(profiles[i]),
          ],
        ],
      ),
    );
  }

  Widget _profileRow(ProfileSummary p) {
    final theme = Theme.of(context);
    final tile = ProfileSummaryTile(
      profile: p,
      padding: const EdgeInsets.symmetric(vertical: 6),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (p.paid != null)
                StatusChip(
                  label: p.paid! ? S.feePaid : S.feeNotPaid,
                  color: p.paid! ? AppColors.success : AppColors.warning,
                  icon: p.paid! ? Icons.check_circle_outline_rounded : Icons.currency_rupee_rounded,
                ),
              if (p.status != null) ...[
                const SizedBox(height: 4),
                StatusChip(
                  label: p.status == 'on_hold' ? S.onHold : p.status!,
                  color: StatusColors.forProfileStatus(p.status!, theme.colorScheme),
                ),
              ],
            ],
          ),
          Icon(Icons.chevron_right_rounded, color: theme.colorScheme.outline),
        ],
      ),
    );
    if (!p.isUnpaid && p.deleteRequestId == null) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.only(left: 64, bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (p.deleteRequestId != null)
                StatusChip(
                  label: S.wantsToDelete,
                  color: theme.colorScheme.error,
                  icon: Icons.delete_outline_rounded,
                ),
              if (p.isUnpaid)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _busyProfileId == p.id ? null : () => _markPaid(p),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text(S.markPaidCash),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
