import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/deletion_request.dart';
import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../../services/link_launcher.dart';
import '../../../state/auth_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/reason_dialog.dart';
import '../clients/client_widgets.dart' show confirmAction;

/// Account deletion requests from the public /delete-account page
/// (SPEC §9.20 F). Anyone can type a number there, so the admin confirms
/// with the person first, then deletes the account (customer) or scrubs and
/// suspends it (agent), or rejects the request with a note.
class AdminDeletionRequestsScreen extends StatefulWidget {
  const AdminDeletionRequestsScreen({super.key, this.initialStatus = 'pending'});

  /// `pending`, `done`, `rejected` or `all`.
  final String initialStatus;

  @override
  State<AdminDeletionRequestsScreen> createState() => _AdminDeletionRequestsScreenState();
}

class _AdminDeletionRequestsScreenState extends State<AdminDeletionRequestsScreen> {
  static const _filters = [
    ('pending', S.filterPending),
    ('done', S.filterDone),
    ('rejected', S.filterRejected),
    ('all', S.filterAll),
  ];

  late String _status = widget.initialStatus;
  List<DeletionRequest> _items = [];
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
    final status = _status;
    try {
      final items = await context.read<AdminService>().deletionRequests(status: status);
      if (mounted && status == _status) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setFilter(String status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _items = [];
    });
    _load();
  }

  Future<void> _call(DeletionRequest r) async {
    final ok = await context.read<LinkLauncher>().launch(Uri.parse('tel:+91${r.phone}'));
    if (!ok && mounted) showSnack(context, S.cannotCall, error: true);
  }

  Future<void> _complete(DeletionRequest r) async {
    final ok = await confirmAction(
      context,
      title: S.deleteAccountTitle,
      body: S.deleteAccountConfirmBody(r.phone),
      confirmLabel: S.deleteAccount,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busyId = r.id);
    try {
      final decision = await context.read<AdminService>().completeDeletion(r.id);
      if (!mounted) return;
      showSnack(context, decision.note ?? S.accountDeleted);
      context.read<AuthState>().refreshNotifications();
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'agent_has_data') {
        // Their profiles / clients must move to another agent first.
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.folder_shared_outlined),
            title: const Text(S.agentHasDataTitle),
            content: Text(e.message),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.ok))],
          ),
        );
      } else {
        showSnack(context, e.message, error: true);
        if (e.code == 'already_decided') _load();
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _reject(DeletionRequest r) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const ReasonDialog(
        title: S.rejectDeletionTitle,
        body: S.rejectDeletionBody,
        label: S.noteLabel,
        hint: S.rejectDeletionHint,
      ),
    );
    if (note == null || !mounted) return;
    setState(() => _busyId = r.id);
    try {
      await context.read<AdminService>().rejectDeletion(r.id, note);
      if (!mounted) return;
      showSnack(context, S.deletionRejected);
      context.read<AuthState>().refreshNotifications();
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, error: true);
      if (e.code == 'already_decided') _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.deletionRequests)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                for (final (value, label) in _filters) ...[
                  ChoiceChip(
                    label: Text(label),
                    selected: _status == value,
                    onSelected: (_) => _setFilter(value),
                  ),
                  const SizedBox(width: 8),
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
            EmptyState(
              icon: Icons.person_remove_outlined,
              title: _status == 'pending' ? S.noDeletionRequests : S.noDeletionRequestsInList,
            ),
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
        itemBuilder: (_, i) {
          final r = _items[i];
          return DeletionRequestTile(
            request: r,
            busy: _busyId == r.id,
            onCall: () => _call(r),
            onDelete: () => _complete(r),
            onReject: () => _reject(r),
          );
        },
      ),
    );
  }
}

/// One request: the app, the number (tap to call), name, reason, when, and
/// whether an account with that number exists; Delete account / Reject
/// while pending.
class DeletionRequestTile extends StatelessWidget {
  const DeletionRequestTile({
    super.key,
    required this.request,
    required this.busy,
    required this.onCall,
    required this.onDelete,
    required this.onReject,
  });

  final DeletionRequest request;
  final bool busy;
  final VoidCallback onCall;
  final VoidCallback onDelete;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final (String statusText, Color statusColor) = switch (r.status) {
      'done' => (S.statusDone, AppColors.success),
      'rejected' => (S.statusRejected, theme.colorScheme.error),
      _ => (S.statusPending, AppColors.warning),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: StatusChip(
                  label: r.isAgentApp ? S.appAgent : S.appCustomer,
                  color: r.isAgentApp ? AppColors.navy : AppColors.goldDark,
                  icon: r.isAgentApp ? Icons.support_agent_rounded : Icons.favorite_outline_rounded,
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(label: statusText, color: statusColor),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onCall,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.call_rounded, size: 20, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Text(
                    '+91 ${r.phone}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.navy,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (r.fullName != null) Text(r.fullName!, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            r.reason ?? S.noReasonGiven,
            style: r.reason == null
                ? muted?.copyWith(fontStyle: FontStyle.italic)
                : theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                r.accountExists ? Icons.check_circle_outline_rounded : Icons.help_outline_rounded,
                size: 16,
                color: r.accountExists ? AppColors.success : theme.colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  r.accountExists ? S.accountFound : S.noAccountWithNumber,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: r.accountExists ? AppColors.success : theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${S.requestedOn} ${formatDateTime(r.createdAt)}', style: muted),
          if (!r.isPending && r.handledAt != null)
            Text('${S.handledOn} ${formatDateTime(r.handledAt)}', style: muted),
          if (r.note != null) ...[
            const SizedBox(height: 4),
            Text('${S.noteLabel}: ${r.note}', style: theme.textTheme.bodySmall),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      S.deletionVerifyHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                    onPressed: busy ? null : onReject,
                    child: const Text(S.reject),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      backgroundColor: theme.colorScheme.error,
                    ),
                    onPressed: busy ? null : onDelete,
                    child: const Text(S.deleteAccount),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
