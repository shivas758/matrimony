import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/agent.dart';
import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../widgets/common.dart';
import 'temp_password_dialogs.dart';

class AdminAgentsScreen extends StatefulWidget {
  const AdminAgentsScreen({super.key, this.initialStatus});

  final String? initialStatus;

  @override
  State<AdminAgentsScreen> createState() => _AdminAgentsScreenState();
}

class _AdminAgentsScreenState extends State<AdminAgentsScreen> {
  late String? _status = widget.initialStatus;
  List<AdminAgent> _agents = [];
  bool _loading = true;
  String? _error;
  int? _busyId;

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
      final agents = await context.read<AdminService>().agents(status: _status);
      if (mounted) setState(() => _agents = agents);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(AdminAgent a, Future<void> Function() action, String done) async {
    setState(() => _busyId = a.agent.id);
    try {
      await action();
      if (mounted) {
        showSnack(context, done);
        context.read<AuthState>().refreshNotifications();
        await _load();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _editCommunities(AdminAgent a) async {
    final masters = context.read<MastersState>().data;
    final selected = {...a.agent.communities.map((c) => c.id)};

    final result = await showDialog<Set<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text('${a.agent.fullName} — communities'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in masters.communities)
                  CheckboxListTile(
                    dense: true,
                    value: selected.contains(c.id),
                    title: Text(c.name),
                    onChanged: (on) => setInner(() {
                      on == true ? selected.add(c.id) : selected.remove(c.id);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.cancel)),
            FilledButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(ctx, selected),
              child: const Text(S.save),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;
    await _act(
      a,
      () => context.read<AdminService>().setAgentCommunities(a.agent.id, result.toList()),
      'Communities updated',
    );
  }

  /// Temporary password without a "Forgot password?" request — for agents who
  /// phoned the admin instead. Same forced change on their next login.
  Future<void> _resetPassword(AdminAgent a) async {
    final password = await promptTemporaryPassword(context, agentName: a.agent.fullName);
    if (password == null || !mounted) return;
    setState(() => _busyId = a.agent.id);
    try {
      await context.read<AdminService>().resetAgentPassword(a.agent.id, password);
      if (!mounted) return;
      context.read<AuthState>().refreshNotifications();
      await showTemporaryPasswordIssued(
        context,
        agentName: a.agent.fullName,
        phone: a.agent.phone,
        password: password,
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = context.watch<AuthState>().agent;

    return Scaffold(
      appBar: AppBar(title: Text(_status == 'pending' ? S.pendingAgents : S.allAgents)),
      body: Column(
        // Keeps the horizontal chip bar full-width instead of centred.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _status == null,
                  onSelected: (_) {
                    setState(() => _status = null);
                    _load();
                  },
                ),
                for (final s in ['pending', 'active', 'suspended']) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(s[0].toUpperCase() + s.substring(1)),
                    selected: _status == s,
                    onSelected: (_) {
                      setState(() => _status = s);
                      _load();
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading && _agents.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _agents.isEmpty
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _agents.isEmpty
                        ? const EmptyState(
                            icon: Icons.badge_outlined,
                            title: 'No agents in this list',
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: _agents.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final a = _agents[i];
                                final agent = a.agent;
                                final busy = _busyId == agent.id;
                                final isMe = agent.id == me?.id;

                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  agent.fullName,
                                                  style: theme.textTheme.titleSmall
                                                      ?.copyWith(fontWeight: FontWeight.w700),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '+91 ${agent.phone}'
                                                  '${(agent.agencyName ?? '').isNotEmpty ? ' · ${agent.agencyName}' : ''}',
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                      color: theme.colorScheme.outline),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (agent.mustChangePassword) ...[
                                            const StatusChip(
                                              label: 'Temp password',
                                              color: Color(0xFF00695C),
                                              icon: Icons.key_rounded,
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          if (agent.isAdmin)
                                            const StatusChip(
                                                label: 'Admin', color: Color(0xFF6A1B9A)),
                                          const SizedBox(width: 6),
                                          StatusChip(
                                            label: agent.status.name,
                                            color: switch (agent.status) {
                                              AgentStatus.active => const Color(0xFF2E7D32),
                                              AgentStatus.pending => const Color(0xFFEF6C00),
                                              AgentStatus.suspended => theme.colorScheme.error,
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          for (final c in agent.communities)
                                            Chip(
                                              label: Text(c.name),
                                              visualDensity: VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
                                          ActionChip(
                                            avatar: const Icon(Icons.edit_rounded, size: 15),
                                            label: const Text('Edit'),
                                            visualDensity: VisualDensity.compact,
                                            onPressed: busy ? null : () => _editCommunities(a),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${a.profileCount} profiles uploaded · joined ${formatDate(agent.createdAt)}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: theme.colorScheme.outline),
                                      ),
                                      if (!isMe) ...[
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            if (agent.status != AgentStatus.active)
                                              Expanded(
                                                child: FilledButton(
                                                  style: FilledButton.styleFrom(
                                                      minimumSize: const Size(0, 42)),
                                                  onPressed: busy
                                                      ? null
                                                      : () => _act(
                                                            a,
                                                            () => context
                                                                .read<AdminService>()
                                                                .activateAgent(agent.id),
                                                            '${agent.fullName} activated',
                                                          ),
                                                  child: const Text(S.activate),
                                                ),
                                              ),
                                            if (agent.status == AgentStatus.active)
                                              Expanded(
                                                child: OutlinedButton(
                                                  style: OutlinedButton.styleFrom(
                                                    minimumSize: const Size(0, 42),
                                                    foregroundColor: theme.colorScheme.error,
                                                  ),
                                                  onPressed: busy
                                                      ? null
                                                      : () => _act(
                                                            a,
                                                            () => context
                                                                .read<AdminService>()
                                                                .suspendAgent(agent.id),
                                                            '${agent.fullName} suspended',
                                                          ),
                                                  child: const Text(S.suspend),
                                                ),
                                              ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(
                                                    minimumSize: const Size(0, 42)),
                                                onPressed: busy
                                                    ? null
                                                    : () => _act(
                                                          a,
                                                          () => context
                                                              .read<AdminService>()
                                                              .setRole(
                                                                agent.id,
                                                                agent.isAdmin ? 'agent' : 'admin',
                                                              ),
                                                          'Role updated',
                                                        ),
                                                child: Text(
                                                  agent.isAdmin ? S.makeAgent : S.makeAdmin,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 42)),
                                          onPressed: busy ? null : () => _resetPassword(a),
                                          icon: const Icon(Icons.key_rounded, size: 18),
                                          label: const Text(S.resetPassword),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
