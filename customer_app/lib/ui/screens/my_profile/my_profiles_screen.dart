import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/profile.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/notification_bell.dart';
import '../get_started/get_started_screen.dart';
import 'my_profile_screen.dart';
import 'profile_form_screen.dart';

/// The *My profile* tab (SPEC §9.12, one profile per account since §9.17).
/// No profile yet → the Get-started notice (until full access) and *Create
/// profile*, which needs a linked agent. One profile → [MyProfileScreen]
/// embedded right here (view, edit, photos, pay, delete); it is keyed on the
/// profile id, so deleting the profile — or the agent approving its deletion —
/// refreshes the account and brings the create button back. The profile list
/// is the account's own `profiles[]` from /customer/auth/me. [HomeShell]
/// mounts it.
class MyProfilesScreen extends StatelessWidget {
  const MyProfilesScreen({super.key});

  Future<void> _add(BuildContext context) async {
    context.read<MastersState>().load();
    final saved = await Navigator.of(context).push<Profile>(
      MaterialPageRoute(builder: (_) => const ProfileFormScreen(prefillName: true)),
    );
    if (saved == null || !context.mounted) return;
    showSnack(context, S.profileSaved);
    await context.read<AuthState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final customer = context.watch<AuthState>().customer;
    if (customer == null) return const Scaffold(body: SizedBox.shrink());
    if (customer.profiles.isNotEmpty) {
      final id = customer.profiles.first.id;
      return MyProfileScreen(key: ValueKey(id), profileId: id, embedded: true);
    }
    final theme = Theme.of(context);
    final linked = customer.agent != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(S.myProfile),
        actions: const [NotificationBell(), SizedBox(width: 8)],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<AuthState>().refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (!customer.hasFullAccess) ...[
              NoticeCard(
                icon: Icons.lock_open_rounded,
                title: S.getStartedTitle,
                body: linked ? S.getStartedIntro : S.addProfileNeedsAgent,
                tint: AppColors.goldDark,
                action: OutlinedButton(
                  onPressed: () => GetStartedScreen.open(context),
                  child: const Text(S.getStarted),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: EmptyState(
                icon: Icons.assignment_rounded,
                title: S.noProfilesYetTitle,
                message: S.noProfilesYetBody,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: linked && customer.canAddProfile ? () => _add(context) : null,
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
          ],
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
      ProfileVisibility.paymentPending => (S.chipPay(fee), AppColors.goldDark, Icons.lock_rounded),
      ProfileVisibility.awaitingApproval => (S.chipWaitingForAgent, AppColors.warning, Icons.hourglass_top_rounded),
      ProfileVisibility.live => (S.chipLive, AppColors.success, Icons.visibility_rounded),
      _ => (S.chipHidden, scheme.outline, Icons.visibility_off_outlined),
    };
    return StatusChip(label: label, color: color, icon: icon);
  }
}
