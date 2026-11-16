import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config.dart';
import '../../../models/customer.dart';
import '../../../models/profile.dart';
import '../../../models/publish.dart';
import '../../../services/agents_service.dart';
import '../../../services/api_client.dart';
import '../../../services/payment_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/step_header.dart';
import '../agent/change_agent_screen.dart';
import '../my_profile/profile_form_screen.dart';
import '../payment/checkout_screen.dart';
import '../payment/upi_checkout.dart';
import 'agent_link_field.dart';
import 'gift_code_form.dart';

/// *Publish my profile* (SPEC §9.23 C / F) — the family filled in the
/// profile first; this is where the agent and the fee come in. A stepper
/// **Agent → Payment → Approval** ([PublishStep]):
///
/// * **Agent** (none yet, or *Change* while not active): "Have a gift code
///   from an agent?" (links and publishes at once), **Recommended for you**
///   (GET /customer/agents/recommended — name, agency, city, agent code,
///   communities, "N clients", Call, *Choose*), *Search all agents* (the
///   directory) and the agent's mobile number or code.
/// * **Payment**: the agent card, *Pay ₹150* (the usual checkout; UPI being
///   verified / not verified as on My profile) or *Use a gift code*.
/// * **Approval**: "Waiting for your agent's approval" with Call and *Check
///   again* (a gift code skips it).
/// * Then "Your profile is live".
///
/// Payment and approval may happen in either order. The account is re-read
/// on open, after every action and every [AppConfig.statusPollInterval].
/// Opened from My profile and Get started.
class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key, this.profileId});

  /// Which of my profiles (one per account) — the first when null.
  final int? profileId;

  static Future<void> open(BuildContext context, {int? profileId}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublishScreen(profileId: profileId)));

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  Timer? _poll;
  bool _busy = false;

  /// Pending / rejected customers may switch agent: *Change* reopens step 1.
  bool _editingAgent = false;

  /// *Use a gift code* opened on the payment step.
  bool _giftOnPay = false;

  RecommendedAgents? _recommended;
  bool _recLoading = false;
  String? _recError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthState>().refresh();
      if (_step(context.read<AuthState>().customer) == PublishStep.agent) _loadRecommended();
    });
    _poll = Timer.periodic(AppConfig.statusPollInterval, (_) {
      if (!mounted) return;
      final step = _step(context.read<AuthState>().customer);
      if (step != null && step != PublishStep.live) context.read<AuthState>().refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  ProfileSummary? _profileOf(Customer? c) {
    if (c == null || c.profiles.isEmpty) return null;
    final id = widget.profileId;
    return (id == null ? null : c.myProfile(id)) ?? c.profiles.first;
  }

  PublishStep? _step(Customer? c) {
    final profile = _profileOf(c);
    return c == null || profile == null ? null : PublishStep.of(c, profile);
  }

  Future<void> _loadRecommended() async {
    if (_recLoading) return;
    setState(() {
      _recLoading = true;
      _recError = null;
    });
    try {
      final r = await context.read<AgentsService>().recommended();
      if (mounted) setState(() => _recommended = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _recError = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _recLoading = false);
    }
  }

  /// Runs [action]; an [ApiException] becomes a snack ([message] words it).
  Future<void> _run(Future<void> Function() action, {String Function(ApiException)? message}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, (message ?? friendlyMessage)(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _linked() {
    if (mounted) {
      setState(() {
        _editingAgent = false;
        _giftOnPay = false;
      });
    }
  }

  // ------------------------------------------------------------ actions

  Future<void> _create() async {
    context.read<MastersState>().load();
    final saved = await ProfileFormScreen.create(context, prefillName: true);
    if (saved == null || !mounted) return;
    showSnack(context, S.profileSaved);
    await context.read<AuthState>().refresh();
    if (mounted) _loadRecommended();
  }

  /// A recommended agent: confirm → POST /customer/agent {agent_id}.
  Future<void> _choose(AgentCard agent) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.chooseAgentConfirm(agent.fullName)),
        content: Text(S.chooseAgentConfirmBody(agent.fullName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.choose)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final auth = context.read<AuthState>();
    final agents = context.read<AgentsService>();
    await _run(() async {
      final customer = await agents.linkAgent(agentId: agent.id);
      auth.setCustomer(customer);
      await auth.refresh();
      if (!mounted) return;
      showSnack(context, S.agentLinkedSnack);
      _linked();
    }, message: linkAgentMessage);
  }

  /// The whole directory (link mode); it pops `true` once linked.
  Future<void> _searchAll() async {
    final linked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChangeAgentScreen(link: true)),
    );
    if (!mounted) return;
    if (linked == true) _linked();
    await context.read<AuthState>().refresh();
  }

  Future<void> _pay(ProfileSummary profile) async {
    await CheckoutScreen.open(context, profileId: profile.id, profileName: profile.fullName);
    if (mounted) await context.read<AuthState>().refresh();
  }

  Future<void> _checkAgain() => _run(() => context.read<AuthState>().refreshCustomer());

  void _changeAgent() {
    setState(() => _editingAgent = true);
    if (_recommended == null) _loadRecommended();
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final customer = context.watch<AuthState>().customer;
    if (customer == null) return const Scaffold(body: SizedBox.shrink());
    final profile = _profileOf(customer);
    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(S.publishMyProfile)),
        body: EmptyState(
          icon: Icons.assignment_rounded,
          title: S.publishNeedsProfileTitle,
          message: S.publishNeedsProfileBody,
          actionLabel: S.step1Title,
          onAction: customer.canAddProfile ? _create : null,
        ),
      );
    }

    final step = PublishStep.of(customer, profile);
    final shown = _editingAgent && customer.canLinkAgent && step != PublishStep.live ? PublishStep.agent : step;
    final done = {
      if (customer.agent != null && shown != PublishStep.agent) 0,
      if (profile.paid) 1,
      if (customer.isActive) 2,
    };

    return Scaffold(
      appBar: AppBar(title: const Text(S.publishMyProfile)),
      body: Column(
        children: [
          if (shown != PublishStep.live)
            StepHeader(
              labels: const [S.publishStepAgent, S.publishStepPayment, S.publishStepApproval],
              current: shown.index,
              completed: done.difference({shown.index}),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => context.read<AuthState>().refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: switch (shown) {
                  PublishStep.agent => _agentStep(customer, profile),
                  PublishStep.payment => _paymentStep(customer, profile),
                  PublishStep.approval => _approvalStep(customer),
                  PublishStep.live => _liveStep(customer, profile),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 1 Agent

  List<Widget> _agentStep(Customer customer, ProfileSummary profile) {
    final theme = Theme.of(context);
    final rec = _recommended;
    final current = customer.agent;
    return [
      _Intro(S.publishAgentIntro),
      const SizedBox(height: 14),
      // A gift code links its agent and publishes at once (SPEC §9.23 B).
      _Panel(
        icon: Icons.card_giftcard_rounded,
        title: S.giftCodeQuestion,
        body: S.giftCodeQuestionBody,
        child: GiftCodeForm(profileId: profile.id, onRedeemed: (_) => _linked()),
      ),
      const SizedBox(height: 20),
      SectionHeader(S.recommendedTitle),
      Padding(
        padding: const EdgeInsets.only(left: 11, bottom: 10),
        child: Text(
          [S.recommendedBasedOn, ?rec?.basedOn?.label].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ),
      if (_recLoading && rec == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_recError != null && rec == null)
        _InlineError(message: _recError!, onRetry: _loadRecommended)
      else if (rec == null || rec.agents.isEmpty)
        _Intro(S.recommendedNone)
      else
        for (final agent in rec.agents) ...[
          _RecommendedCard(
            agent: agent,
            isCurrent: agent.isCurrent || agent.id == current?.id,
            onChoose: _busy ? null : () => _choose(agent),
          ),
          const SizedBox(height: 10),
        ],
      const SizedBox(height: 6),
      OutlinedButton.icon(
        onPressed: _busy ? null : _searchAll,
        icon: const Icon(Icons.person_search_rounded),
        label: const Text(S.searchAllAgents),
      ),
      const SizedBox(height: 20),
      SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: AgentLinkField(label: S.enterAgentNumberOrCode, primary: false, onLinked: _linked),
      ),
      if (_editingAgent) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _editingAgent = false),
          child: const Text(S.cancel),
        ),
      ],
    ];
  }

  // ---- 2 Payment

  List<Widget> _paymentStep(Customer customer, ProfileSummary profile) {
    final theme = Theme.of(context);
    final fee = customer.profileFeeInr;
    // The Play build offers no UPI / Razorpay (SPEC §9.20 G) — gift codes still work.
    final payable = Provider.of<PaymentService>(context, listen: false).offersPayment(customer.paymentProvider);
    final upi = payable ? profile.payment : null;
    final submitted = upi?.isSubmitted == true;
    final rejected = upi?.isRejected == true;
    final giftOpen = _giftOnPay || !payable;
    return [
      _AgentPanel(customer: customer, onChange: customer.canLinkAgent && !_busy ? _changeAgent : null),
      const SizedBox(height: 16),
      if (!payable)
        const NoticeCard(icon: Icons.schedule_rounded, title: S.paymentUnavailable, tint: AppColors.warning)
      else if (submitted)
        UpiUnderReviewCard(
          utr: upi!.utr,
          action: OutlinedButton.icon(
            onPressed: _busy ? null : () => _pay(profile),
            icon: const Icon(Icons.hourglass_top_rounded),
            label: const Text(S.viewPaymentStatus),
          ),
        )
      else if (rejected)
        NoticeCard(
          icon: Icons.error_outline_rounded,
          title: S.upiNotVerified(upi!.rejectReason),
          body: S.upiNotVerifiedBody,
          tint: theme.colorScheme.error,
          action: FilledButton.icon(
            onPressed: _busy ? null : () => _pay(profile),
            icon: const Icon(Icons.error_outline_rounded),
            label: const Text(S.fixPayment),
          ),
        )
      else
        NoticeCard(
          icon: Icons.lock_rounded,
          title: S.step3Title(fee),
          body: S.step3Body(fee),
          tint: AppColors.goldDark,
          action: FilledButton.icon(
            onPressed: _busy ? null : () => _pay(profile),
            icon: const Icon(Icons.lock_rounded),
            label: Text(S.payFee(fee)),
          ),
        ),
      // A UPI fee being verified cannot be swapped for a code.
      if (!submitted) ...[
        const SizedBox(height: 16),
        if (giftOpen)
          _Panel(
            icon: Icons.card_giftcard_rounded,
            title: S.useGiftCode,
            body: S.giftCodeOnPayBody,
            child: GiftCodeForm(profileId: profile.id, primary: !payable, onRedeemed: (_) => _linked()),
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _giftOnPay = true),
              icon: const Icon(Icons.card_giftcard_rounded, size: 18),
              label: const Text(S.useGiftCode),
            ),
          ),
      ],
    ];
  }

  // ---- 3 Approval

  List<Widget> _approvalStep(Customer customer) {
    final agent = customer.agent;
    final phone = agent?.phone;
    final rejected = customer.isRejected;
    return [
      _AgentPanel(customer: customer, onChange: customer.canLinkAgent && !_busy ? _changeAgent : null),
      const SizedBox(height: 16),
      NoticeCard(
        icon: rejected ? Icons.do_not_disturb_on_outlined : Icons.hourglass_top_rounded,
        title: rejected ? S.rejectedTitle : S.publishWaitingTitle,
        body: rejected
            ? S.step4Rejected
            : agent == null
                ? S.step4WaitingNoAgent
                : S.publishWaitingBody(agent.fullName),
        tint: rejected ? Theme.of(context).colorScheme.error : AppColors.warning,
        action: Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (phone != null && phone.isNotEmpty) CallButton(phone: phone),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: _busy ? null : _checkAgain,
              icon: _busy ? const ButtonSpinner(color: AppColors.wine) : const Icon(Icons.refresh_rounded),
              label: const Text(S.checkAgain),
            ),
          ],
        ),
      ),
    ];
  }

  // ---- live

  List<Widget> _liveStep(Customer customer, ProfileSummary profile) {
    final theme = Theme.of(context);
    // Paid and approved — unless the agent has hidden it for now.
    final live = profile.visibility == null || profile.visibility == ProfileVisibility.live;
    return [
      const SizedBox(height: 24),
      Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: (live ? AppColors.success : theme.colorScheme.outline).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            live ? Icons.celebration_rounded : Icons.visibility_off_outlined,
            size: 50,
            color: live ? AppColors.success : theme.colorScheme.outline,
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        live ? S.publishLiveTitle : S.visibilityTitle('hidden'),
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.wine),
      ),
      const SizedBox(height: 8),
      Text(
        live ? S.publishLiveBody : S.visibilityNote('hidden'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
      ),
      if (customer.agent != null) ...[
        const SizedBox(height: 20),
        SurfaceCard(child: AgentRow(agent: customer.agent!, label: S.yourAgent)),
      ],
      const SizedBox(height: 28),
      FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text(S.done)),
    ];
  }
}

/// A muted explanatory line.
class _Intro extends StatelessWidget {
  const _Intro(this.text);

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

/// A white card with an icon, a title, a line of text and a form under it.
class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.body, required this.child});

  final IconData icon;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppColors.goldLight, borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: Icon(icon, size: 19, color: AppColors.wine),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: AppColors.wine))),
            ],
          ),
          const SizedBox(height: 8),
          _Intro(body),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// My agent with *Change* while the account is not active yet.
class _AgentPanel extends StatelessWidget {
  const _AgentPanel({required this.customer, required this.onChange});

  final Customer customer;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final agent = customer.agent;
    if (agent == null) return const SizedBox.shrink();
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            S.yourAgent,
            trailing: customer.canLinkAgent
                ? TextButton(onPressed: onChange, child: const Text(S.change))
                : null,
          ),
          AgentRow(agent: agent),
        ],
      ),
    );
  }
}

/// A recommended agent: name, agency · city, agent code, "N clients", phone
/// with Call, the communities and *Choose*.
class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({required this.agent, required this.isCurrent, required this.onChoose});

  final AgentCard agent;
  final bool isCurrent;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentRow(agent: agent, label: isCurrent ? S.currentAgentChip : null),
          if (agent.communities.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in agent.communities)
                  Chip(
                    label: Text(c.name, style: theme.textTheme.labelMedium),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          if (!isCurrent) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onChoose,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text(S.choose),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A failed load with *Retry*, inside a list.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ErrorBanner(message: message),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(S.retry),
          ),
        ],
      );
}
