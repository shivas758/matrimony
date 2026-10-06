import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Share and contact audit trails (CLAUDE.md rule 5).
class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

  List<ShareLogEntry> _shares = [];
  List<ContactLogEntry> _contacts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = context.read<AdminService>();
      final results = await Future.wait([service.shareLogs(), service.contactLogs()]);
      if (mounted) {
        setState(() {
          _shares = results[0] as List<ShareLogEntry>;
          _contacts = results[1] as List<ContactLogEntry>;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(S.logs),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: S.shareLogs), Tab(text: S.contactLogs)],
        ),
      ),
      body: _loading && _shares.isEmpty && _contacts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    RefreshIndicator(
                      onRefresh: _load,
                      child: _shares.isEmpty
                          ? _emptyList(const EmptyState(
                              icon: Icons.share_outlined, title: 'No shares logged yet'))
                          : ListView.separated(
                              itemCount: _shares.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final s = _shares[i];
                                return ListTile(
                                  leading: Icon(switch (s.method) {
                                    'download' => Icons.download_rounded,
                                    'link' => Icons.link_rounded,
                                    _ => Icons.chat_rounded,
                                  }),
                                  title: Text(s.profileName),
                                  subtitle: Text(
                                    '${s.agentName}'
                                    '${(s.agencyName ?? '').isNotEmpty ? ' · ${s.agencyName}' : ''}'
                                    '\n${formatDateTime(s.sharedAt)}',
                                  ),
                                  isThreeLine: true,
                                  trailing: StatusChip(
                                    label: s.method,
                                    color: theme.colorScheme.primary,
                                  ),
                                );
                              },
                            ),
                    ),
                    RefreshIndicator(
                      onRefresh: _load,
                      child: _contacts.isEmpty
                          ? _emptyList(const EmptyState(
                              icon: Icons.lock_open_rounded, title: 'No contact requests yet'))
                          : ListView.separated(
                              itemCount: _contacts.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final c = _contacts[i];
                                return ListTile(
                                  title: Text(c.profileName),
                                  subtitle: Text(
                                    '${c.requesterName} asked '
                                    '${c.uploaderName != null ? '${c.uploaderName} ' : ''}'
                                    '· ${formatDateTime(c.requestedAt)}'
                                    '${c.decidedByName != null ? '\nDecided by ${c.decidedByName}' : ''}'
                                    '${c.expiresAt != null ? ' · expires ${formatDate(c.expiresAt)}' : ''}',
                                  ),
                                  isThreeLine: c.decidedByName != null,
                                  trailing: StatusChip(
                                    label: c.status,
                                    color:
                                        StatusColors.forRequestStatus(c.status, theme.colorScheme),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  /// Keeps pull-to-refresh working on an empty list.
  Widget _emptyList(Widget child) => ListView(
        children: [SizedBox(height: MediaQuery.sizeOf(context).height * 0.2), child],
      );
}
