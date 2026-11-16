import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config.dart';
import '../../../models/customer.dart';
import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/payment_service.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../agent/change_agent_screen.dart';
import '../my_profile/profile_form_screen.dart';
import '../payment/checkout_screen.dart';
import '../publish/agent_link_field.dart';
import '../publish/gift_code_form.dart';
import '../publish/publish_screen.dart';

/// Get started (SPEC §9.12; the order since v3.4.0 — §9.23 C / F): the
/// checklist from guest to full access — 1 **Create your profile** (open to
/// guests: no agent needed to fill it in) · 2 **Choose your agent** (by their
/// mobile number OR their agent code, SPEC §9.18 B, or from the directory) ·
/// 3 **Pay ₹150 or use a gift code** · 4 **Agent approval**. Done steps are
/// ticked; only the next open step's button is primary. Once the profile
/// exists and is not live, the top card offers *Publish my profile*
/// ([PublishScreen]: recommended agents, gift code, payment and approval in
/// one place). Reached from the Browse banner and locked cards, the
/// Interested tab, My profile, More and a locked profile detail. Re-reads the
/// account on open, after every action and every
/// [AppConfig.statusPollInterval].
class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GetStartedScreen()));

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen> {
  Timer? _poll;
  bool _busy = false;

  /// Pending / rejected customers may switch agent: "Change" reopens step 2.
  bool _editingAgent = false;

  /// Step 3's gift-code field is open.
  bool _giftOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AuthState>().refresh());
    _poll = Timer.periodic(AppConfig.statusPollInterval, (_) {
      final c = context.read<AuthState>().customer;
      if (c != null && !c.hasFullAccess) context.read<AuthState>().refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------ step 1

  Future<void> _register(Customer customer) async {
    // The four-step form, then the privacy settings once (SPEC §9.18 G).
    final saved = await ProfileFormScreen.create(context, prefillName: customer.profiles.isEmpty);
    if (saved == null || !mounted) return;
    showSnack(context, S.profileSaved);
    await context.read<AuthState>().refresh();
  }

  // ------------------------------------------------------------ step 2

  void _linked() {
    if (mounted) setState(() => _editingAgent = false);
  }

  Future<void> _pickFromDirectory() async {
    final linked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChangeAgentScreen(link: true)),
    );
    if (!mounted) return;
    if (linked == true) _linked();
    await context.read<AuthState>().refresh();
  }

  // ------------------------------------------------------------ steps 3–4

  Future<void> _pay(ProfileSummary profile) async {
    await CheckoutScreen.open(context, profileId: profile.id, profileName: profile.fullName);
    if (mounted) await context.read<AuthState>().refresh();
  }

  Future<void> _publish(ProfileSummary profile) async {
    await PublishScreen.open(context, profileId: profile.id);
    if (mounted) await context.read<AuthState>().refresh();
  }

  Future<void> _checkAgain() => _run(() => context.read<AuthState>().refreshCustomer());

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final customer = context.watch<AuthState>().customer;
    if (customer == null) return const Scaffold(body: SizedBox.shrink());
    final u = customer.unlock;
    final done = [u.profileRegistered, u.agentLinked, u.paid, u.approved];
    final next = done.indexOf(false); // -1 when everything is done
    final mine = customer.profiles.isEmpty ? null : customer.profiles.first;
    final unpaid = customer.firstUnpaid;
    // The Play build offers no UPI / Razorpay: no Pay button, no UPI states (SPEC §9.20 G).
    final payable = Provider.of<PaymentService>(context, listen: false).offersPayment(customer.paymentProvider);
    // A UPI fee being verified / not verified (SPEC §9.20 B).
    final upi = payable ? unpaid?.payment : null;
    final upiSubmitted = upi?.isSubmitted == true;
    final upiRejected = upi?.isRejected == true;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(S.getStarted)),
      body: RefreshIndicator(
        onRefresh: () => context.read<AuthState>().refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (customer.hasFullAccess)
              NoticeCard(
                icon: Icons.celebration_rounded,
                title: S.allSetTitle,
                body: S.allSetBody,
                tint: AppColors.success,
                action: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(S.startBrowsing),
                ),
              )
            else if (mine != null && mine.needsPublishing)
              // The profile is filled in: agent, fee and approval in one place.
              NoticeCard(
                icon: Icons.rocket_launch_outlined,
                title: S.publishReadyTitle,
                body: payable ? S.publishReadyBody(customer.profileFeeInr) : S.publishReadyBodyNoPayment,
                tint: AppColors.goldDark,
                action: FilledButton.icon(
                  onPressed: _busy ? null : () => _publish(mine),
                  icon: const Icon(Icons.publish_rounded),
                  label: const Text(S.publishMyProfile),
                ),
              )
            else
              const NoticeCard(
                icon: Icons.lock_open_rounded,
                title: S.getStartedTitle,
                body: S.getStartedIntro,
                tint: AppColors.goldDark,
              ),
            const SizedBox(height: 16),

            // ---- 1 Create your profile (no agent needed)
            _StepCard(
              number: 1,
              title: S.step1Title,
              done: done[0],
              child: done[0]
                  ? const _Line(S.profileRegistered)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Line(S.step1Body),
                        const SizedBox(height: 12),
                        _StepButton(
                          label: S.step1Title,
                          icon: Icons.edit_note_rounded,
                          primary: next == 0,
                          onPressed: !_busy && customer.canAddProfile ? () => _register(customer) : null,
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),

            // ---- 2 Choose your agent
            _StepCard(
              number: 2,
              title: S.step2Title,
              done: done[1],
              child: _agentStep(customer, primary: next == 1 || _editingAgent),
            ),
            const SizedBox(height: 12),

            // ---- 3 Pay the fee — or use a gift code
            _StepCard(
              number: 3,
              title: payable ? S.step3Title(customer.profileFeeInr) : S.step3TitleNoPayment,
              done: done[2],
              child: done[2]
                  ? const _Line(S.allPaid)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Line(!u.profileRegistered
                            ? S.needProfileFirst
                            : !u.agentLinked
                                ? S.needAgentFirst
                                : !payable
                                    ? S.paymentUnavailable
                                    : upiSubmitted
                                        ? S.step3UnderReview
                                        : upiRejected
                                            ? S.upiNotVerified(upi!.rejectReason)
                                            : S.step3Body(customer.profileFeeInr)),
                        // Paying needs the agent (SPEC §9.23 C: 403 agent_required).
                        if (payable && u.agentLinked) ...[
                          const SizedBox(height: 12),
                          _StepButton(
                            label: upiSubmitted
                                ? S.viewPaymentStatus
                                : upiRejected
                                    ? S.fixPayment
                                    : S.payFee(customer.profileFeeInr),
                            icon: upiSubmitted ? Icons.hourglass_top_rounded : Icons.lock_rounded,
                            primary: next == 2,
                            onPressed: unpaid != null && !_busy ? () => _pay(unpaid) : null,
                          ),
                        ],
                        // A gift code works with or without an agent — it links its own.
                        if (unpaid != null && !upiSubmitted) ...[
                          const SizedBox(height: 8),
                          if (_giftOpen)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: GiftCodeForm(
                                profileId: unpaid.id,
                                primary: !payable || !u.agentLinked,
                                onRedeemed: (_) {
                                  if (mounted) setState(() => _giftOpen = false);
                                },
                              ),
                            )
                          else
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => setState(() => _giftOpen = true),
                                icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                                label: const Text(S.useGiftCode),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 12),

            // ---- 4 Agent approval
            _StepCard(
              number: 4,
              title: S.step4Title,
              done: done[3],
              child: done[3]
                  ? const _Line(S.step4Done)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Line(
                          customer.isRejected
                              ? S.step4Rejected
                              : customer.agent == null
                                  ? S.step4WaitingNoAgent
                                  : S.step4Waiting(customer.agent!.fullName),
                        ),
                        if (customer.agent != null) ...[
                          const SizedBox(height: 12),
                          AgentRow(agent: customer.agent!),
                        ],
                        if (u.agentLinked) ...[
                          const SizedBox(height: 12),
                          _StepButton(
                            label: S.checkAgain,
                            icon: Icons.refresh_rounded,
                            primary: false,
                            onPressed: _busy ? null : _checkAgain,
                          ),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 20),
            Text(
              S.signupNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _agentStep(Customer customer, {required bool primary}) {
    final agent = customer.agent;
    if (agent != null && !_editingAgent) {
      return Row(
        children: [
          Expanded(child: AgentRow(agent: agent)),
          // Pending / rejected customers may pick someone else; active ones
          // use Change agent on the More tab (SPEC §9.6).
          if (customer.canLinkAgent) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _editingAgent = true),
              child: const Text(S.change),
            ),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Line(S.step2Body),
        const SizedBox(height: 14),
        AgentLinkField(primary: primary, onLinked: _linked),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _pickFromDirectory,
              icon: const Icon(Icons.person_search_rounded, size: 18),
              label: const Text(S.pickFromDirectory),
            ),
            if (_editingAgent)
              TextButton(
                onPressed: () => setState(() => _editingAgent = false),
                child: const Text(S.cancel),
              ),
          ],
        ),
      ],
    );
  }
}

/// One numbered step with a tick once done.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.number, required this.title, required this.done, required this.child});

  final int number;
  final String title;
  final bool done;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      borderColor: done ? AppColors.success.withValues(alpha: 0.35) : null,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: done ? AppColors.success : AppColors.goldLight,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                    : Text(
                        '$number',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.wine),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: done ? AppColors.success : AppColors.wine,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
    );
  }
}

/// Filled for the next open step, outlined otherwise.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));
    }
    return OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));
  }
}
