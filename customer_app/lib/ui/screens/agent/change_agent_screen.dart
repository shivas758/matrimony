import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/agent_change.dart';
import '../../../models/customer.dart';
import '../../../services/agents_service.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// The agent directory (search, community chips, city filter), in two modes:
///
/// * Change agent (SPEC §9.11 Gandharva 6, active customers): an explanation
///   card; while a request is pending, the new agent with Cancel; otherwise
///   directory → confirm → request. Past requests are listed with status
///   chips. [MoreScreen] pushes it.
/// * [link] — Choose your agent (SPEC §9.12, guest / pending / rejected):
///   directory → confirm → POST /customer/agent {agent_id}; pops `true` once
///   linked. Get started pushes it.
class ChangeAgentScreen extends StatefulWidget {
  const ChangeAgentScreen({super.key, this.link = false});

  /// Link an agent directly instead of asking the current one to release me.
  final bool link;

  @override
  State<ChangeAgentScreen> createState() => _ChangeAgentScreenState();
}

class _ChangeAgentScreenState extends State<ChangeAgentScreen> {
  final _search = TextEditingController();
  final _city = TextEditingController();
  Timer? _debounce;
  int? _communityId;

  List<AgentCard> _agents = [];
  List<AgentChangeRequest> _requests = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MastersState>().load();
      _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = context.read<AgentsService>();
      final results = await Future.wait([
        service.directory(q: _search.text, communityId: _communityId, city: _city.text),
        // Change requests exist only for active customers.
        if (!widget.link) service.myChangeRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _agents = results[0] as List<AgentCard>;
        _requests = widget.link ? const [] : results[1] as List<AgentChangeRequest>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Typing in the search / city boxes re-queries after a short pause.
  void _onFilterChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  AgentChangeRequest? get _pending {
    for (final r in _requests) {
      if (r.isPending) return r;
    }
    return null;
  }

  /// Link mode: confirm, link, re-read the account and go back.
  Future<void> _confirmLink(AgentCard agent) async {
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
    if (ok != true || !mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final customer = await context.read<AgentsService>().linkAgent(agentId: agent.id);
      if (!mounted) return;
      context.read<AuthState>().setCustomer(customer);
      showSnack(context, S.agentLinkedSnack);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(AgentCard agent) async {
    if (widget.link) return _confirmLink(agent);
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.moveTo(agent.fullName)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.moveToBody(agent.fullName)),
            const SizedBox(height: 16),
            TextField(
              controller: note,
              maxLength: 500,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: S.changeNoteHint),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.sendRequest)),
        ],
      ),
    );
    final noteText = note.text.trim();
    note.dispose();
    if (ok != true || !mounted) return;
    await _run(() async {
      await context.read<AgentsService>().requestChange(agent.id, note: noteText);
      if (mounted) showSnack(context, S.requestSent);
    });
  }

  Future<void> _cancel(AgentChangeRequest request) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.cancelRequest),
        content: const Text(S.cancelRequestBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.close)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.cancelRequest)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await context.read<AgentsService>().cancelChange(request.id);
      if (mounted) showSnack(context, S.requestCancelled);
    });
  }

  /// Runs a request, then re-reads the account (More shows the pending
  /// change) and this screen.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      try {
        await context.read<AuthState>().refreshCustomer();
      } on ApiException {
        // Best effort — the list below reloads either way.
      }
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final masters = context.watch<MastersState>().data;
    final auth = context.watch<AuthState>();
    final current = auth.agent;
    final pending = _pending;
    final past = _requests.where((r) => !r.isPending).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.link ? S.chooseYourAgent : S.changeAgent)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            widget.link
                ? const NoticeCard(
                    icon: Icons.support_agent_rounded,
                    title: S.chooseYourAgent,
                    body: S.chooseAgentExplain,
                  )
                : const NoticeCard(
                    icon: Icons.swap_horiz_rounded,
                    title: S.changeAgent,
                    body: S.changeAgentExplain,
                  ),
            const SizedBox(height: 16),
            if (_loading && _agents.isEmpty && _requests.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _agents.isEmpty)
              ErrorState(message: _error!, onRetry: _load)
            else if (pending != null) ...[
              NoticeCard(
                icon: Icons.hourglass_top_rounded,
                title: S.changeAgentPendingTitle,
                body: S.changeAgentPendingBody,
                tint: AppColors.warning,
                action: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _cancel(pending),
                  icon: _busy ? const ButtonSpinner(color: AppColors.wine) : const Icon(Icons.close_rounded),
                  label: const Text(S.cancelRequest),
                ),
                child: AgentRow(agent: pending.toAgent, label: S.newAgent),
              ),
            ] else ...[
              if (current != null) ...[
                SurfaceCard(child: AgentRow(agent: current, label: S.currentAgentChip)),
                const SizedBox(height: 16),
              ],
              const SectionHeader(S.agentDirectory),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: S.searchAgents,
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (_) => _onFilterChanged(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: S.cityFilterHint,
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                onChanged: (_) => _onFilterChanged(),
              ),
              if (masters.communities.isNotEmpty) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text(S.allCommunities),
                        selected: _communityId == null,
                        onSelected: (_) {
                          setState(() => _communityId = null);
                          _load();
                        },
                      ),
                      for (final c in masters.communities) ...[
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text(c.name),
                          selected: _communityId == c.id,
                          onSelected: (_) {
                            setState(() => _communityId = c.id);
                            _load();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_agents.where((a) => !a.isCurrent).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: EmptyState(icon: Icons.person_search_rounded, title: S.noAgents, message: S.noAgentsHint),
                )
              else
                for (final agent in _agents.where((a) => !a.isCurrent)) ...[
                  _DirectoryCard(agent: agent, onTap: _busy ? null : () => _confirm(agent)),
                  const SizedBox(height: 10),
                ],
            ],
            if (past.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeader(S.pastRequests),
              for (final r in past) ...[
                SurfaceCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              S.requestLine(r.fromAgent.fullName, r.toAgent.fullName),
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatDate(r.decidedAt ?? r.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                            ),
                          ],
                        ),
                      ),
                      StatusChip(
                        label: S.requestStatusLabel(r.status),
                        color: StatusColors.forRequestStatus(r.status, theme.colorScheme),
                      ),
                    ],
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
}

/// A directory entry: name, agency, city, communities, phone. Tap → confirm.
class _DirectoryCard extends StatelessWidget {
  const _DirectoryCard({required this.agent, required this.onTap});

  final AgentCard agent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: AgentRow(agent: agent)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
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
            ],
          ),
        ),
      ),
    );
  }
}
