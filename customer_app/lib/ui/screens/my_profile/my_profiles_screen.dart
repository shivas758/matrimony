import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/customer.dart';
import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/notification_bell.dart';
import '../get_started/get_started_screen.dart';
import '../payment/checkout_screen.dart';
import 'my_profile_screen.dart';
import 'profile_form_screen.dart';

/// My profiles (SPEC §9.12): up to `max_profiles` cards — photo, name, age,
/// community — each with its state chip (*Pay ₹150* / *Waiting for agent* /
/// *Live* / *Hidden*), and *Add profile*. The list is the account's own
/// `profiles[]` from /customer/auth/me, so it refreshes with the account.
/// Tap a card → [MyProfileScreen] for that profile. A pending deletion
/// request (SPEC §9.13) shows as a "Delete requested" chip; `/auth/me` does
/// not carry it, so the screen also reads GET /customer/my-profiles.
/// [HomeShell] mounts it.
class MyProfilesScreen extends StatefulWidget {
  const MyProfilesScreen({super.key});

  @override
  State<MyProfilesScreen> createState() => _MyProfilesScreenState();
}

class _MyProfilesScreenState extends State<MyProfilesScreen> {
  /// Ids of my profiles with a pending deletion request.
  Set<int> _deleteRequested = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDeleteRequests());
  }

  Future<void> _loadDeleteRequests() async {
    final customer = context.read<AuthState>().customer;
    if (customer == null || customer.profiles.isEmpty) {
      if (_deleteRequested.isNotEmpty) setState(() => _deleteRequested = const {});
      return;
    }
    try {
      final views = await context.read<ProfileService>().myProfiles();
      if (!mounted) return;
      setState(() => _deleteRequested = {
            for (final v in views)
              if (v.deleteRequest != null) v.id,
          });
    } on ApiException {
      // Best effort — the chips simply stay as they were.
    }
  }

  Future<void> _refresh() async {
    await context.read<AuthState>().refresh();
    if (mounted) await _loadDeleteRequests();
  }

  Future<void> _add(BuildContext context, Customer customer) async {
    context.read<MastersState>().load();
    final saved = await Navigator.of(context).push<Profile>(
      MaterialPageRoute(builder: (_) => ProfileFormScreen(prefillName: customer.profiles.isEmpty)),
    );
    if (saved == null || !context.mounted) return;
    showSnack(context, S.profileSaved);
    await context.read<AuthState>().refresh();
  }

  Future<void> _open(BuildContext context, ProfileSummary p) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MyProfileScreen(profileId: p.id)),
    );
    if (context.mounted) await _refresh();
  }

  Future<void> _pay(BuildContext context, ProfileSummary p) async {
    await CheckoutScreen.open(context, profileId: p.id, profileName: p.fullName);
    if (context.mounted) await context.read<AuthState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final customer = context.watch<AuthState>().customer;
    if (customer == null) return const Scaffold(body: SizedBox.shrink());
    final theme = Theme.of(context);
    final linked = customer.agent != null;
    final profiles = customer.profiles;

    return Scaffold(
      appBar: AppBar(
        title: const Text(S.myProfiles),
        actions: [
          const NotificationBell(),
          if (profiles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  S.profilesCount(profiles.length, customer.maxProfiles),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (!customer.hasFullAccess) ...[
              NoticeCard(
                icon: Icons.lock_open_rounded,
                title: S.getStartedTitle,
                body: linked ? S.getStartedIntro : S.addProfileNeedsAgent,
                tint: AppColors.roseDark,
                action: OutlinedButton(
                  onPressed: () => GetStartedScreen.open(context),
                  child: const Text(S.getStarted),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: EmptyState(
                  icon: Icons.assignment_rounded,
                  title: S.noProfilesYetTitle,
                  message: S.noProfilesYetBody(customer.maxProfiles),
                ),
              )
            else
              for (final p in profiles) ...[
                _OwnProfileCard(
                  profile: p,
                  deleteRequested: p.deleteRequestId != null || _deleteRequested.contains(p.id),
                  fee: customer.profileFeeInr,
                  onTap: () => _open(context, p),
                  onPay: () => _pay(context, p),
                ),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 8),
            if (customer.canAddProfile) ...[
              FilledButton.icon(
                onPressed: linked ? () => _add(context, customer) : null,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text(S.addProfile),
              ),
              if (!linked) ...[
                const SizedBox(height: 8),
                Text(
                  S.addProfileNeedsAgent,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ] else
              Text(
                S.maxProfilesReached(customer.maxProfiles),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
          ],
        ),
      ),
    );
  }
}

/// Photo, name, age · community, and the state chip (or the Pay button).
class _OwnProfileCard extends StatelessWidget {
  const _OwnProfileCard({
    required this.profile,
    required this.fee,
    required this.onTap,
    required this.onPay,
    this.deleteRequested = false,
  });

  final ProfileSummary profile;
  final bool deleteRequested;
  final num? fee;
  final VoidCallback onTap;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = context.read<ApiClient>();
    final p = profile;
    final line = [
      if (p.age != null) '${p.age} ${S.yearsShort}',
      if (p.communityLine != null) p.communityLine!,
    ].join(' · ');

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AuthedPhoto(
                  url: p.absolutePhotoUrl,
                  api: api,
                  width: 72,
                  height: 88,
                  placeholderInitials: initialsOf(p.fullName),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.maroon,
                      ),
                    ),
                    if (line.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(line, style: theme.textTheme.bodyMedium),
                    ],
                    const SizedBox(height: 8),
                    // Purely from the server's state — a cash payment recorded
                    // by the agent arrives as paid (SPEC §9.13).
                    if (!p.paid && (p.visibility == null || p.visibility == ProfileVisibility.paymentPending))
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: onPay,
                        icon: const Icon(Icons.lock_rounded, size: 16),
                        label: Text(S.chipPay(fee)),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          VisibilityChip(visibility: p.visibility, fee: fee),
                          if (deleteRequested)
                            StatusChip(
                              label: S.chipDeleteRequested,
                              color: theme.colorScheme.error,
                              icon: Icons.delete_outline_rounded,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The state chip of one of my profiles (SPEC §9.12).
class VisibilityChip extends StatelessWidget {
  const VisibilityChip({super.key, required this.visibility, this.fee});

  final ProfileVisibility? visibility;
  final num? fee;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = switch (visibility) {
      ProfileVisibility.paymentPending => (S.chipPay(fee), AppColors.roseDark, Icons.lock_rounded),
      ProfileVisibility.awaitingApproval => (S.chipWaitingForAgent, AppColors.warning, Icons.hourglass_top_rounded),
      ProfileVisibility.live => (S.chipLive, AppColors.success, Icons.visibility_rounded),
      _ => (S.chipHidden, scheme.outline, Icons.visibility_off_outlined),
    };
    return StatusChip(label: label, color: color, icon: icon);
  }
}
