import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'temp_password_dialogs.dart';

/// "Forgot password?" requests (SPEC §5 screen 9). The admin sees the name and
/// phone, checks it is really that agent (a quick call), then approves by
/// choosing a temporary password the agent must replace on first login.
class AdminPasswordResetsScreen extends StatefulWidget {
  const AdminPasswordResetsScreen({super.key});

  @override
  State<AdminPasswordResetsScreen> createState() => _AdminPasswordResetsScreenState();
}

class _AdminPasswordResetsScreenState extends State<AdminPasswordResetsScreen> {
  List<PasswordResetRequest> _items = [];
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
      final items = await context.read<AdminService>().passwordResets();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(PasswordResetRequest r) async {
    final password = await promptTemporaryPassword(context, agentName: r.agentName);
    if (password == null || !mounted) return;
    setState(() => _busyId = r.id);
    try {
      await context.read<AdminService>().approvePasswordReset(r.id, password);
      if (!mounted) return;
      context.read<AuthState>().refreshNotifications();
      await showTemporaryPasswordIssued(
        context,
        agentName: r.agentName,
        phone: r.agentPhone,
        password: password,
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(PasswordResetRequest r) async {
    setState(() => _busyId = r.id);
    try {
      await context.read<AdminService>().rejectPasswordReset(r.id);
      if (mounted) {
        showSnack(context, 'Rejected');
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
      appBar: AppBar(title: const Text(S.passwordResets)),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? ErrorState(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.lock_reset_rounded,
                      title: S.noPasswordResets,
                      message: 'Agents tap "Forgot password?" on the login screen to ask for one. '
                          'You can also reset any agent from the agent list.',
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
                                        r.agentName,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    StatusChip(
                                      label: r.status,
                                      color: StatusColors.forRequestStatus(r.status, theme.colorScheme),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    '+91 ${r.agentPhone}',
                                    if ((r.agencyName ?? '').isNotEmpty) r.agencyName!,
                                    if (r.agentStatus != null && r.agentStatus != 'active')
                                      'account ${r.agentStatus}',
                                  ].join(' · '),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: theme.colorScheme.outline),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  r.isPending
                                      ? 'Asked ${formatDateTime(r.requestedAt)}'
                                      : '${r.status[0].toUpperCase()}${r.status.substring(1)} '
                                          '${formatDateTime(r.decidedAt)}'
                                          '${r.decidedByName != null ? ' by ${r.decidedByName}' : ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                if (r.isPending) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                                          onPressed: busy ? null : () => _reject(r),
                                          child: const Text(S.reject),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        flex: 2,
                                        child: FilledButton.icon(
                                          style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                                          onPressed: busy ? null : () => _approve(r),
                                          icon: const Icon(Icons.key_rounded, size: 18),
                                          label: const Text('Set temporary password'),
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
