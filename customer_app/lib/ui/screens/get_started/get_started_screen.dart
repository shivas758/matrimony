import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../config.dart';
import '../../../models/customer.dart';
import '../../../models/profile.dart';
import '../../../services/agents_service.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../agent/change_agent_screen.dart';
import '../my_profile/profile_form_screen.dart';
import '../payment/checkout_screen.dart';

/// Get started (SPEC §9.12): the checklist from guest to full access —
/// 1 Choose your agent · 2 Register a profile · 3 Pay the fee · 4 Agent
/// approval. Done steps are ticked; only the next open step's button is
/// primary. Reached from the Browse banner and locked cards, the Interested
/// tab, My profiles, More and a locked profile detail. Re-reads the account
/// on open, after every action and every [AppConfig.statusPollInterval].
class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GetStartedScreen()));

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen> {
  final _agentPhone = TextEditingController();
  Timer? _poll;
  bool _busy = false;
  String? _linkError;

  /// Pending / rejected customers may switch agent: "Change" reopens step 1.
  bool _editingAgent = false;

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
    _agentPhone.dispose();
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

  Future<void> _linkByPhone() async {
    final phone = _agentPhone.text.trim();
    if (phone.length != 10) {
      setState(() => _linkError = S.agentPhoneInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _linkError = null);
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final customer = await context.read<AgentsService>().linkAgent(agentPhone: phone);
      if (!mounted) return;
      context.read<AuthState>().setCustomer(customer);
      _agentPhone.clear();
      setState(() => _editingAgent = false);
      showSnack(context, S.agentLinkedSnack);
    } on ApiException catch (e) {
      if (mounted) setState(() => _linkError = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromDirectory() async {
    final linked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ChangeAgentScreen(link: true)),
    );
    if (linked == true && mounted) {
      setState(() {
        _editingAgent = false;
        _linkError = null;
      });
    }
  }

  // ------------------------------------------------------------ steps 2–4

  Future<void> _register(Customer customer) async {
    final saved = await Navigator.of(context).push<Profile>(
      MaterialPageRoute(builder: (_) => ProfileFormScreen(prefillName: customer.profiles.isEmpty)),
    );
    if (saved == null || !mounted) return;
    showSnack(context, S.profileSaved);
    await context.read<AuthState>().refresh();
  }

  Future<void> _pay(ProfileSummary profile) async {
    await CheckoutScreen.open(context, profileId: profile.id, profileName: profile.fullName);
    if (mounted) await context.read<AuthState>().refresh();
  }

  Future<void> _checkAgain() => _run(() => context.read<AuthState>().refreshCustomer());

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final customer = context.watch<AuthState>().customer;
    if (customer == null) return const Scaffold(body: SizedBox.shrink());
    final u = customer.unlock;
    final done = [u.agentLinked, u.profileRegistered, u.paid, u.approved];
    final next = done.indexOf(false); // -1 when everything is done
    final unpaid = customer.firstUnpaid;
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
            else
              NoticeCard(
                icon: Icons.lock_open_rounded,
                title: S.getStartedTitle,
                body: S.getStartedIntro,
                tint: AppColors.roseDark,
              ),
            const SizedBox(height: 16),

            // ---- 1 Choose your agent
            _StepCard(
              number: 1,
              title: S.step1Title,
              done: done[0],
              child: _agentStep(customer, primary: next == 0 || _editingAgent),
            ),
            const SizedBox(height: 12),

            // ---- 2 Register a profile
            _StepCard(
              number: 2,
              title: S.step2Title,
              done: done[1],
              child: done[1]
                  ? _Line(S.profilesRegistered(customer.profiles.length))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Line(u.agentLinked ? S.step2Body : S.needAgentFirst),
                        const SizedBox(height: 12),
                        _StepButton(
                          label: S.step2Title,
                          icon: Icons.edit_note_rounded,
                          primary: next == 1,
                          onPressed: u.agentLinked && !_busy && customer.canAddProfile
                              ? () => _register(customer)
                              : null,
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),

            // ---- 3 Pay the fee
            _StepCard(
              number: 3,
              title: S.step3Title(customer.profileFeeInr),
              done: done[2],
              child: done[2]
                  ? const _Line(S.allPaid)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Line(u.profileRegistered ? S.step3Body(customer.profileFeeInr) : S.needProfileFirst),
                        const SizedBox(height: 12),
                        _StepButton(
                          label: S.payFee(customer.profileFeeInr),
                          icon: Icons.lock_rounded,
                          primary: next == 2,
                          onPressed: unpaid != null && !_busy ? () => _pay(unpaid) : null,
                        ),
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
        const _Line(S.step1Body),
        const SizedBox(height: 12),
        TextField(
          controller: _agentPhone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onSubmitted: (_) => _linkByPhone(),
          decoration: InputDecoration(
            labelText: S.agentPhone,
            helperText: S.agentPhoneHelper,
            prefixIcon: const Icon(Icons.support_agent_rounded),
            prefixText: '+91 ',
            errorText: _linkError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 12),
        _StepButton(
          label: S.agentPhoneLink,
          icon: Icons.link_rounded,
          primary: primary,
          busy: _busy,
          onPressed: _busy ? null : _linkByPhone,
        ),
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
                onPressed: () => setState(() {
                  _editingAgent = false;
                  _linkError = null;
                }),
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
                  color: done ? AppColors.success : AppColors.roseLight,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                    : Text(
                        '$number',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.maroon),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: done ? AppColors.success : AppColors.maroon,
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
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: busy ? const ButtonSpinner() : Icon(icon),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: busy ? const ButtonSpinner(color: AppColors.maroon) : Icon(icon),
      label: Text(label),
    );
  }
}
