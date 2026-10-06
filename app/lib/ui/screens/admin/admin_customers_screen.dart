import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/agent.dart';
import '../../../models/customer.dart';
import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../clients/client_detail_screen.dart';
import '../clients/client_widgets.dart';

/// Every Gandharva customer across all agents (SPEC §9.5 admin): filter by
/// status, search, activate / suspend / reject, and move one to another agent.
class AdminCustomersScreen extends StatefulWidget {
  const AdminCustomersScreen({super.key, this.initialStatus});

  final String? initialStatus;

  @override
  State<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends State<AdminCustomersScreen> {
  static const _statuses = ['guest', 'pending', 'active', 'suspended', 'rejected'];

  late String? _status = widget.initialStatus;
  final _search = TextEditingController();
  List<Customer> _items = [];
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
    try {
      final items = await context.read<AdminService>().customers(
        status: _status,
        q: _search.text.trim(),
      );
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Customer c, Future<Customer> Function() action, String done) async {
    setState(() => _busyId = c.id);
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        final i = _items.indexWhere((x) => x.id == c.id);
        if (i >= 0) _items[i] = updated;
      });
      context.read<AuthState>().refreshNotifications();
      showSnack(context, done);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _confirmThen(
    Customer c, {
    required String title,
    required String body,
    required String confirmLabel,
    required Future<Customer> Function() action,
    required String done,
  }) async {
    final ok = await confirmAction(
      context,
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      destructive: true,
    );
    if (ok) await _act(c, action, done);
  }

  Future<void> _reassign(Customer c) async {
    final agent = await showDialog<Agent>(
      context: context,
      builder: (_) => _PickAgentDialog(customer: c),
    );
    if (agent == null || !mounted) return;
    await _act(
      c,
      () => context.read<AdminService>().reassignCustomer(c.id, agent.id),
      '${S.customerMoved} ${agent.fullName}',
    );
  }

  Future<void> _open(Customer c) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ClientDetailScreen(customerId: c.id)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.customers)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              onChanged: (v) {
                if (v.isEmpty) _load();
              },
              decoration: InputDecoration(
                hintText: S.searchClients,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
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
                for (final s in _statuses) ...[
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
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) return ErrorState(message: _error!, onRetry: _load);
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.14),
            const EmptyState(icon: Icons.people_alt_outlined, title: S.noCustomers),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _row(_items[i]),
      ),
    );
  }

  Widget _row(Customer c) {
    final theme = Theme.of(context);
    final busy = _busyId == c.id;
    final admin = context.read<AdminService>();
    final change = c.pendingAgentChange;

    return InkWell(
      onTap: () => _open(c),
      child: Padding(
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
                        c.fullName,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '+91 ${c.phone} · ${formatDate(c.createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(
                  label: c.statusLabel,
                  color: clientStatusColor(c.status, theme.colorScheme),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.support_agent_rounded, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${S.agentLabel}: ${c.agent?.label ?? S.noAgentYet}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (c.profile != null)
                  StatusChip(
                    label: '${S.profilePrefix}${c.profile!.fullName}',
                    color: AppColors.navy,
                    icon: Icons.badge_outlined,
                  )
                else
                  StatusChip(
                    label: S.noProfileYet,
                    color: theme.colorScheme.outline,
                    icon: Icons.person_off_outlined,
                  ),
                if (c.allProfiles.length > 1)
                  StatusChip(
                    label: S.profilesCount(c.allProfiles.length),
                    color: AppColors.navyLight,
                    icon: Icons.people_outline_rounded,
                  ),
                if (c.hasUnpaidProfile)
                  StatusChip(
                    label: S.feePending,
                    color: AppColors.warning,
                    icon: Icons.currency_rupee_rounded,
                  ),
                SourceChip(source: c.source),
                if (c.interestsCount > 0)
                  StatusChip(
                    label: interestsCountLabel(c.interestsCount),
                    color: AppColors.goldDark,
                    icon: Icons.favorite_outline_rounded,
                  ),
                if (change != null)
                  StatusChip(
                    label: '${S.wantsToMoveTo} ${change.toAgent.fullName}',
                    color: AppColors.warning,
                    icon: Icons.swap_horiz_rounded,
                  ),
              ],
            ),
            // Admin activate starts from pending / rejected / suspended; a
            // guest first needs an agent (reassign → pending, SPEC §9.12).
            if (c.isGuest) ...[
              const SizedBox(height: 10),
              Text(
                S.guestReassignNote,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ] else ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (!c.isActive)
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                        onPressed: busy
                            ? null
                            : () => _act(
                                c,
                                () => admin.activateCustomer(c.id),
                                '${c.fullName} activated',
                              ),
                        child: const Text(S.activate),
                      ),
                    ),
                  if (c.isActive)
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: busy
                            ? null
                            : () => _confirmThen(
                                c,
                                title: '${S.suspend} ${c.fullName}?',
                                body: S.suspendClientBody,
                                confirmLabel: S.suspend,
                                action: () => admin.suspendCustomer(c.id),
                                done: '${c.fullName} suspended',
                              ),
                        child: const Text(S.suspend),
                      ),
                    ),
                  if (c.isPending) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          foregroundColor: theme.colorScheme.error,
                        ),
                        onPressed: busy
                            ? null
                            : () => _confirmThen(
                                c,
                                title: '${S.reject} ${c.fullName}?',
                                body: '${c.fullName} ${S.rejectClientBody}',
                                confirmLabel: S.reject,
                                action: () => admin.rejectCustomer(c.id),
                                done: '${c.fullName} rejected',
                              ),
                        child: const Text(S.reject),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: busy ? null : () => _reassign(c),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text(S.reassignAgent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable list of active agents; pops the chosen [Agent].
class _PickAgentDialog extends StatefulWidget {
  const _PickAgentDialog({required this.customer});

  final Customer customer;

  @override
  State<_PickAgentDialog> createState() => _PickAgentDialogState();
}

class _PickAgentDialogState extends State<_PickAgentDialog> {
  final _search = TextEditingController();
  List<Agent> _agents = [];
  bool _loading = true;
  String? _error;

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
    try {
      final rows = await context.read<AdminService>().agents(status: 'active');
      if (mounted) {
        setState(
          () => _agents = rows
              .map((a) => a.agent)
              .where((a) => a.id != widget.customer.agentId)
              .toList(),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Agent> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _agents;
    return _agents
        .where(
          (a) =>
              a.fullName.toLowerCase().contains(q) ||
              (a.agencyName ?? '').toLowerCase().contains(q) ||
              a.phone.contains(q) ||
              (a.city ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agents = _filtered;
    return AlertDialog(
      title: const Text(S.reassignAgent),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.customer.fullName} — ${S.reassignAgentBody}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: S.searchAgents,
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ErrorState(message: _error!, onRetry: _load)
                  : agents.isEmpty
                  ? const EmptyState(icon: Icons.badge_outlined, title: S.noActiveAgents)
                  : ListView.separated(
                      itemCount: agents.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = agents[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.support_agent_rounded),
                          title: Text(a.fullName),
                          subtitle: Text(
                            [
                              a.agencyName,
                              a.city,
                              '+91 ${a.phone}',
                            ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                          ),
                          onTap: () => Navigator.pop(context, a),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel))],
    );
  }
}
