import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../../state/interests_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/notification_bell.dart';
import '../browse/profile_detail_screen.dart';
import '../get_started/get_started_screen.dart';

/// Interested: my interests newest first with a status chip each — Waiting /
/// Details shared · N days / Declined / Withdrawn / Expired — Withdraw while
/// pending, tap → the profile (SPEC §9.11 Gandharva 4). Rows say which of my
/// profiles is interested ("for Priya"). Without full access the tab is a
/// locked state with *Get started* (SPEC §9.12). [HomeShell] mounts it.
class InterestsScreen extends StatefulWidget {
  const InterestsScreen({super.key});

  @override
  State<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends State<InterestsScreen> {
  int? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool force = false}) async {
    final customer = context.read<AuthState>().customer;
    if (customer != null) await context.read<InterestsState>().load(customer.id, force: force);
  }

  Future<void> _open(Interest interest) async {
    final id = interest.profile?.id;
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileId: id)),
    );
    // The detail screen already reloads this list after a change; a manual
    // refresh keeps days-left fresh anyway.
    if (mounted) _load(force: true);
  }

  Future<void> _withdraw(Interest interest) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.withdrawConfirmTitle),
        content: const Text(S.withdrawConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.withdraw)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyId = interest.id);
    try {
      await context.read<InterestsState>().withdraw(interest.id);
      if (mounted) showSnack(context, S.withdrawnSnack);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InterestsState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(S.interested),
        actions: const [NotificationBell(), SizedBox(width: 4)],
      ),
      body: _body(state),
    );
  }

  Widget _body(InterestsState state) {
    if (state.loading && !state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.locked) {
      return _scrollable(
        EmptyState(
          icon: Icons.lock_rounded,
          title: S.lockedInterestsTitle,
          message: S.lockedInterestsBody,
          actionLabel: S.getStarted,
          onAction: () => GetStartedScreen.open(context),
        ),
      );
    }
    if (state.blockedCode != null) {
      return _scrollable(
        EmptyState(
          icon: Icons.hourglass_top_rounded,
          title: S.pendingTitle,
          message: S.errAccountPending,
          actionLabel: S.checkAgain,
          onAction: () => _load(force: true),
        ),
      );
    }
    if (state.error != null && state.interests.isEmpty) {
      return ErrorState(message: state.error!, onRetry: () => _load(force: true));
    }
    if (state.isEmpty) {
      return _scrollable(
        const EmptyState(
          icon: Icons.favorite_rounded,
          title: S.noInterests,
          message: S.noInterestsHint,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: state.interests.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final interest = state.interests[i];
          return _InterestTile(
            interest: interest,
            busy: _busyId == interest.id,
            onTap: () => _open(interest),
            onWithdraw: interest.isPending ? () => _withdraw(interest) : null,
          );
        },
      ),
    );
  }

  Widget _scrollable(Widget child) => RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          children: [SizedBox(height: MediaQuery.sizeOf(context).height * 0.12), child],
        ),
      );
}

class _InterestTile extends StatelessWidget {
  const _InterestTile({
    required this.interest,
    required this.busy,
    required this.onTap,
    this.onWithdraw,
  });

  final Interest interest;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = context.read<ApiClient>();
    final s = interest.profile;
    final name = s?.fullName ?? '—';
    final line = [
      if (s?.age != null) '${s!.age} ${S.yearsShort}',
      if (s?.communityLine != null) s!.communityLine!,
    ].join(' · ');

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AuthedPhoto(
                      url: s?.absolutePhotoUrl,
                      api: api,
                      width: 72,
                      height: 88,
                      placeholderInitials: initialsOf(name),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.wine,
                          ),
                        ),
                        if (line.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(line, style: theme.textTheme.bodyMedium),
                        ],
                        if ((interest.fromProfile?.fullName ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            S.forProfile(interest.fromProfile!.fullName),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.goldDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (interest.createdAt != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            S.sentOn(formatDate(interest.createdAt)),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ],
                        const SizedBox(height: 8),
                        StatusChip(
                          label: S.interestChip(interest.status, interest.daysLeft),
                          color: StatusColors.forInterestStatus(interest.status, theme.colorScheme),
                          icon: switch (interest.status) {
                            'pending' => Icons.hourglass_top_rounded,
                            'accepted' => Icons.lock_open_rounded,
                            _ => Icons.info_outline_rounded,
                          },
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
              if (onWithdraw != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: busy ? null : onWithdraw,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.undo_rounded, size: 18),
                    label: const Text(S.withdraw),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
