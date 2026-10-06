import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class AdminCommunityRequestsScreen extends StatefulWidget {
  const AdminCommunityRequestsScreen({super.key});

  @override
  State<AdminCommunityRequestsScreen> createState() => _AdminCommunityRequestsScreenState();
}

class _AdminCommunityRequestsScreenState extends State<AdminCommunityRequestsScreen> {
  List<CommunityRequest> _items = [];
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
      final items = await context.read<AdminService>().communityRequests();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(CommunityRequest r, bool approve) async {
    setState(() => _busyId = r.id);
    try {
      await context.read<AdminService>().decideCommunityRequest(r.id, approve: approve);
      if (mounted) {
        showSnack(context, approve ? 'Approved' : 'Rejected');
        context.read<AuthState>().refreshNotifications();
        await _load();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(S.communityRequests)),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? ErrorState(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.playlist_add_check_rounded,
                      title: 'No community requests',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _items[i];
                          final busy = _busyId == r.id;
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.agentName ?? 'Agent',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    StatusChip(
                                      label: r.status,
                                      color: StatusColors.forRequestStatus(
                                          r.status == 'pending' ? 'pending' : r.status,
                                          theme.colorScheme),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (r.agentPhone != null) '+91 ${r.agentPhone}',
                                    r.agencyName,
                                  ].whereType<String>().join(' · '),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: theme.colorScheme.outline),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(Icons.groups_rounded, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Wants access to ${r.communityName}',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                                if (r.isPending) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          style:
                                              OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                                          onPressed: busy ? null : () => _decide(r, false),
                                          child: const Text(S.reject),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton(
                                          style:
                                              FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                                          onPressed: busy ? null : () => _decide(r, true),
                                          child: const Text(S.approve),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
