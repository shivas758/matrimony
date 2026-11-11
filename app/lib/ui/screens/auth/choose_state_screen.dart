import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/agent.dart';
import '../../../models/master_data.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/agent_code_card.dart';
import '../../widgets/common.dart';
import 'login_screen.dart';

/// Shown instead of Home to an active agent who has no agent code yet — an
/// account from before v2.8 (SPEC §9.18 B). They choose their State once;
/// the server issues the permanent code (`POST /my/state`) and the screen
/// shows it before letting them in. Nothing else to do here except log out.
class ChooseStateScreen extends StatefulWidget {
  const ChooseStateScreen({super.key});

  @override
  State<ChooseStateScreen> createState() => _ChooseStateScreenState();
}

class _ChooseStateScreenState extends State<ChooseStateScreen> {
  int? _stateId;
  bool _busy = false;
  String? _error;

  /// Set once the code is issued — the result card replaces the form.
  Agent? _issued;

  @override
  void initState() {
    super.initState();
    // The states come with the public masters; refresh them in case the cache
    // predates the server upgrade.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final masters = context.read<MastersState>();
      masters.load(force: masters.isLoaded && masters.data.states.isEmpty);
    });
  }

  Future<void> _submit(StateItem state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.confirmStateTitle(state.name)),
        content: Text(S.confirmStateBody(state.code, state.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.confirm)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final agent = await context.read<AuthState>().chooseState(state.id);
      if (!mounted) return;
      if (agent.hasAgentCode) {
        setState(() => _issued = agent);
      } else {
        // Should not happen — let the root decide again from the fresh agent.
        context.read<AuthState>().updateAgent(agent);
      }
    } on ApiException catch (e) {
      // invalid_state (deactivated meanwhile) and network errors: the
      // server's message says it; the list is reloaded for the next try.
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.code == 'invalid_state') context.read<MastersState>().load(force: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Hands the agent (now with a code) to the app — the root swaps to Home.
  void _continue() {
    final agent = _issued;
    if (agent == null) return;
    showSnack(context, S.agentCodeIssued(agent.agentCode ?? ''));
    context.read<AuthState>().updateAgent(agent);
  }

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AuthState>().agent;

    return Scaffold(
      appBar: AppBar(
        title: Text(agent?.fullName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: S.logout,
            icon: const Icon(Icons.logout_rounded),
            onPressed: _busy ? null : () => context.read<AuthState>().logout(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _issued != null ? _result(_issued!) : _form(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    final theme = Theme.of(context);
    final masters = context.watch<MastersState>();
    final states = masters.data.activeStates;
    final selected = masters.data.stateById(_stateId);
    final loading = masters.loading && states.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.map_rounded, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          S.chooseStateTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          S.chooseStateBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 28),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (states.isEmpty) ...[
          ErrorBanner(message: masters.error ?? S.statesNotLoaded),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.read<MastersState>().load(force: true),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(S.retry),
          ),
        ] else ...[
          StateDropdown(
            states: states,
            value: _stateId,
            enabled: !_busy,
            onChanged: (v) => setState(() {
              _stateId = v;
              _error = null;
            }),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy || selected == null ? null : () => _submit(selected),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text(S.continueLabel),
          ),
        ],
      ],
    );
  }

  Widget _result(Agent agent) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.verified_rounded, size: 56, color: AppColors.success),
        const SizedBox(height: 16),
        Text(
          S.agentCodeIssued(agent.agentCode ?? ''),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          S.agentCodeIssuedBody,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 24),
        AgentCodeCard(code: agent.agentCode ?? '', stateName: agent.state?.name, note: S.tapToCopy),
        const SizedBox(height: 24),
        FilledButton(onPressed: _continue, child: const Text(S.continueLabel)),
      ],
    );
  }
}

/// The State dropdown of the signup form and the "Choose your State" screen:
/// "KA — Karnataka" rows, with the note that the choice is permanent.
class StateDropdown extends StatelessWidget {
  const StateDropdown({
    super.key,
    required this.states,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.validator,
  });

  final List<StateItem> states;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool enabled;
  final FormFieldValidator<int>? validator;

  @override
  Widget build(BuildContext context) {
    // Guard against an id that is not in the list (deactivated meanwhile).
    final safeValue = states.any((s) => s.id == value) ? value : null;
    return DropdownButtonFormField<int>(
      initialValue: safeValue,
      isExpanded: true,
      menuMaxHeight: 420,
      decoration: const InputDecoration(
        labelText: S.state,
        prefixIcon: Icon(Icons.map_outlined),
        helperText: S.stateHelper,
        helperMaxLines: 2,
      ),
      items: [
        for (final s in states)
          DropdownMenuItem(
            value: s.id,
            // Long names ("Dadra and Nagar Haveli and Daman and Diu") must
            // not push the row past the field.
            child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      validator: validator,
      onChanged: enabled ? onChanged : null,
    );
  }
}
