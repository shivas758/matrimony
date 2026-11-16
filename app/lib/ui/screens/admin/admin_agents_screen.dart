import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/agent.dart';
import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/searchable_lists.dart';
import '../clients/client_widgets.dart' show confirmAction;
import 'temp_password_dialogs.dart';

class AdminAgentsScreen extends StatefulWidget {
  const AdminAgentsScreen({super.key, this.initialStatus, this.initialApproved});

  final String? initialStatus;

  /// SPEC §9.23 A: true = approved agents only, false = not approved yet.
  final bool? initialApproved;

  @override
  State<AdminAgentsScreen> createState() => _AdminAgentsScreenState();
}

class _AdminAgentsScreenState extends State<AdminAgentsScreen> {
  late String? _status = widget.initialStatus;
  late bool? _approved = widget.initialApproved;
  final _search = TextEditingController();
  int _requests = 0;
  List<AdminAgent> _agents = [];
  bool _loading = true;
  String? _error;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final request = ++_requests;
    try {
      // The server's `q` matches name, phone, agency and the agent code
      // (SPEC §9.18 B).
      final agents = await context
          .read<AdminService>()
          .agents(status: _status, q: _search.text.trim(), approved: _approved);
      // A slower, older answer must not replace a newer search.
      if (mounted && request == _requests) setState(() => _agents = agents);
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

    // Checkboxes + Done, with a search field once the list is long (SPEC §9.23 E).
    final result = await showMultiPickerSheet(
      context,
      title: '${a.agent.fullName} — communities',
      options: masterOptions(masters.communities),
      selected: selected,
    );

    if (result == null || !mounted) return;
    if (result.isEmpty) {
      showSnack(context, S.selectOneCommunity, error: true);
      return;
    }
    await _act(
      a,
      () => context.read<AdminService>().setAgentCommunities(a.agent.id, result.toList()),
      'Communities updated',
    );
  }

  /// SPEC §9.23 A: approve before 10 live clients. `409 already_approved`
  /// (approved meanwhile) shows the server's message; the list reloads.
  Future<void> _approve(AdminAgent a) async {
    final agent = a.agent;
    final ok = await confirmAction(
      context,
      title: S.approveAgentTitle(agent.fullName),
      body: S.approveAgentBody(agent.approvalClients),
      confirmLabel: S.approveNow,
    );
    if (!ok || !mounted) return;
    await _act(
      a,
      () => context.read<AdminService>().approveAgent(agent.id),
      S.agentApproved(agent.fullName),
    );
  }

  /// SPEC §9.23 B: 1–50 more gift codes for the agent.
  Future<void> _addGiftCodes(AdminAgent a) async {
    final count = await askGiftCodeCount(context, agentName: a.agent.fullName);
    if (count == null || !mounted) return;
    await _act(
      a,
      () => context.read<AdminService>().addGiftCodes(a.agent.id, count),
      S.giftCodesAdded(count, a.agent.fullName),
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
    final me = context.watch<AuthState>().agent;
    final searching = _search.text.trim().isNotEmpty;
    final title = _approved == false
        ? S.notApprovedAgents
        : _status == 'pending'
            ? S.pendingAgents
            : S.allAgents;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        // Keeps the horizontal chip bar full-width instead of centred.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              onChanged: (v) {
                // Clearing the box brings the full list back at once.
                if (v.isEmpty) _load();
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: S.searchAgentsAdmin,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: searching
                    ? IconButton(
                        tooltip: S.clearAll,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      )
                    : null,
              ),
            ),
          ),
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
                // SPEC §9.23 A: approved (10 live clients or by hand) or not.
                // Tapping the selected one again shows both.
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: AppColors.rule,
                ),
                for (final (value, label) in [(true, S.approved), (false, S.notApproved)]) ...[
                  FilterChip(
                    key: ValueKey('approved-filter-$value'),
                    label: Text(label),
                    selected: _approved == value,
                    onSelected: (on) {
                      setState(() => _approved = on ? value : null);
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
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
                        ? EmptyState(
                            icon: searching ? Icons.search_off_rounded : Icons.badge_outlined,
                            title: searching ? S.noAgentsFound : 'No agents in this list',
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
                                final service = context.read<AdminService>();
                                return AdminAgentRow(
                                  row: a,
                                  busy: _busyId == agent.id,
                                  isMe: agent.id == me?.id,
                                  onEditCommunities: () => _editCommunities(a),
                                  onActivate: () => _act(
                                    a,
                                    () => service.activateAgent(agent.id),
                                    '${agent.fullName} activated',
                                  ),
                                  onSuspend: () => _act(
                                    a,
                                    () => service.suspendAgent(agent.id),
                                    '${agent.fullName} suspended',
                                  ),
                                  onToggleRole: () => _act(
                                    a,
                                    () => service.setRole(
                                      agent.id,
                                      agent.isAdmin ? 'agent' : 'admin',
                                    ),
                                    'Role updated',
                                  ),
                                  onResetPassword: () => _resetPassword(a),
                                  onApprove: () => _approve(a),
                                  onAddGiftCodes: () => _addGiftCodes(a),
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

/// One agent on Admin → Agents: name, phone, agency, status pills, the
/// approval pill ("Approved" / "3/10 clients", SPEC §9.23 A), the agent code
/// and state, communities (edit), profiles / gift codes left / joined, and
/// the actions — activate or suspend, role, reset password, **Approve now**
/// (not approved yet) and **Add gift codes**. No actions on my own row.
class AdminAgentRow extends StatelessWidget {
  const AdminAgentRow({
    super.key,
    required this.row,
    required this.busy,
    required this.isMe,
    required this.onEditCommunities,
    required this.onActivate,
    required this.onSuspend,
    required this.onToggleRole,
    required this.onResetPassword,
    required this.onApprove,
    required this.onAddGiftCodes,
  });

  final AdminAgent row;
  final bool busy;
  final bool isMe;
  final VoidCallback onEditCommunities;
  final VoidCallback onActivate;
  final VoidCallback onSuspend;
  final VoidCallback onToggleRole;
  final VoidCallback onResetPassword;
  final VoidCallback onApprove;
  final VoidCallback onAddGiftCodes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agent = row.agent;
    final knowsCodes = row.giftCodesUnused != null;
    final meta = [
      '${row.profileCount} profiles uploaded',
      if (knowsCodes) S.giftCodesLeft(row.giftCodesUnused!),
      'joined ${formatDate(agent.createdAt)}',
    ].join(' · ');

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
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '+91 ${agent.phone}'
                      '${(agent.agencyName ?? '').isNotEmpty ? ' · ${agent.agencyName}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
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
              if (agent.isAdmin) const StatusChip(label: 'Admin', color: Color(0xFF6A1B9A)),
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
          // The permanent agent code and its state (SPEC §9.18 B); agents
          // from before v2.8 have none until they choose. Then the approval
          // pill (SPEC §9.23 A) — nothing against an older server.
          if (agent.hasAgentCode || agent.state != null || agent.knowsApproval) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (agent.hasAgentCode) ...[
                  AgentCodeChip(code: agent.agentCode!, copyable: true),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    agent.state?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
                if (agent.knowsApproval)
                  StatusChip(
                    key: ValueKey('approval-${agent.id}'),
                    label: agent.isApproved
                        ? S.approved
                        : S.clientsShort(agent.liveClientCount, agent.approvalClients),
                    color: agent.isApproved ? AppColors.success : AppColors.warning,
                    icon: agent.isApproved ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in agent.communities)
                Chip(
                  label: Text(c.name),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ActionChip(
                avatar: const Icon(Icons.edit_rounded, size: 15),
                label: const Text('Edit'),
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : onEditCommunities,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            meta,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          if (!isMe) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (agent.status != AgentStatus.active)
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                      onPressed: busy ? null : onActivate,
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
                      onPressed: busy ? null : onSuspend,
                      child: const Text(S.suspend),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: busy ? null : onToggleRole,
                    child: Text(agent.isAdmin ? S.makeAgent : S.makeAdmin),
                  ),
                ),
              ],
            ),
            // SPEC §9.23: approve by hand, give more gift codes.
            if (agent.knowsApproval) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (!agent.isApproved) ...[
                    Expanded(
                      child: FilledButton.icon(
                        key: ValueKey('approve-${agent.id}'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          backgroundColor: AppColors.success,
                        ),
                        onPressed: busy ? null : onApprove,
                        icon: const Icon(Icons.verified_rounded, size: 18),
                        label: const Text(S.approveNow),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      key: ValueKey('add-codes-${agent.id}'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                      onPressed: busy ? null : onAddGiftCodes,
                      icon: const Icon(Icons.card_giftcard_rounded, size: 18),
                      label: const Text(S.addGiftCodes),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: busy ? null : onResetPassword,
              icon: const Icon(Icons.key_rounded, size: 18),
              label: const Text(S.resetPassword),
            ),
          ],
        ],
      ),
    );
  }
}

/// "How many codes?" for Add gift codes (SPEC §9.23 B): a number from 1 to
/// 50, 10 by default. Null when cancelled.
Future<int?> askGiftCodeCount(BuildContext context, {required String agentName}) =>
    showDialog<int>(
      context: context,
      builder: (_) => _GiftCountDialog(agentName: agentName),
    );

/// Owns its text controller, so it lives exactly as long as the dialog
/// (including its closing animation).
class _GiftCountDialog extends StatefulWidget {
  const _GiftCountDialog({required this.agentName});

  final String agentName;

  @override
  State<_GiftCountDialog> createState() => _GiftCountDialogState();
}

class _GiftCountDialogState extends State<_GiftCountDialog> {
  final _controller = TextEditingController(text: '10');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static int? _parse(String? v) {
    final n = int.tryParse((v ?? '').trim());
    return n != null && n >= 1 && n <= 50 ? n : null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) Navigator.pop(context, _parse(_controller.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(S.addGiftCodesTitle(widget.agentName)),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(S.addGiftCodesBody),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('gift-count'),
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: const InputDecoration(labelText: S.giftCodesCountLabel),
                validator: (v) => _parse(v) == null ? S.giftCodesCountInvalid : null,
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
          FilledButton(onPressed: _submit, child: const Text(S.add)),
        ],
      );
}
