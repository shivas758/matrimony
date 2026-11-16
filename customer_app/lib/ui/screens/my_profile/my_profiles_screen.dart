import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/payment.dart';
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
/// profile* — open to guests too: the agent and the fee come when it is
/// published (SPEC §9.23 C). One profile → [MyProfileScreen]
/// embedded right here (view, edit, photos, pay, delete); it is keyed on the
/// profile id, so deleting the profile — or the agent approving its deletion —
/// refreshes the account and brings the create button back. The profile list
/// is the account's own `profiles[]` from /customer/auth/me. [HomeShell]
/// mounts it.
class MyProfilesScreen extends StatelessWidget {
  const MyProfilesScreen({super.key});

  Future<void> _add(BuildContext context) async {
    context.read<MastersState>().load();
    // The four-step form, then the privacy settings once (SPEC §9.18 G).
    final saved = await ProfileFormScreen.create(context, prefillName: true);
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
                body: S.getStartedIntro,
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
              onPressed: customer.canAddProfile ? () => _add(context) : null,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text(S.addProfile),
            ),
          ],
        ),
      ),
    );
  }
}

/// The state chip of one of my profiles (SPEC §9.12); an unpaid profile's UPI
/// fee being verified / not verified wins over "Pay ₹150" (SPEC §9.20 B).
class VisibilityChip extends StatelessWidget {
  const VisibilityChip({super.key, required this.visibility, this.fee, this.payment, this.payable = true});

  final ProfileVisibility? visibility;
  final num? fee;
  final ProfilePayment? payment;

  /// False in the Play build with no in-app payment: "Fee not paid" instead
  /// of "Pay ₹150" (SPEC §9.20 G).
  final bool payable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final upi = payment;
    if (upi != null && upi.isSubmitted) {
      return const StatusChip(
        label: S.chipVerifyingPayment,
        color: AppColors.warning,
        icon: Icons.hourglass_top_rounded,
      );
    }
    if (upi != null && upi.isRejected) {
      return StatusChip(label: S.chipPaymentNotVerified, color: scheme.error, icon: Icons.error_outline_rounded);
    }
    final (label, color, icon) = switch (visibility) {
      ProfileVisibility.paymentPending =>
        (payable ? S.chipPay(fee) : S.chipFeeNotPaid, AppColors.goldDark, Icons.lock_rounded),
      ProfileVisibility.awaitingApproval => (S.chipWaitingForAgent, AppColors.warning, Icons.hourglass_top_rounded),
      ProfileVisibility.live => (S.chipLive, AppColors.success, Icons.visibility_rounded),
      _ => (S.chipHidden, scheme.outline, Icons.visibility_off_outlined),
    };
    return StatusChip(label: label, color: color, icon: icon);
  }
}
