import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/master_data.dart';
import '../../services/admin_service.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../state/auth_state.dart';
import '../../state/masters_state.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// My communities, requests to join more, change password (SPEC §5 screen 10).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<MasterItem> _mine = [];
  List<CommunityRequest> _requests = [];
  bool _loading = true;
  String? _error;

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
      final result = await context.read<MyAccountService>().communities();
      if (mounted) {
        setState(() {
          _mine = result.communities;
          _requests = result.requests;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestCommunity() async {
    final masters = context.read<MastersState>().data;
    final mineIds = _mine.map((c) => c.id).toSet();
    final pendingIds =
        _requests.where((r) => r.isPending).map((r) => r.communityId).toSet();
    final options = masters.communities
        .where((c) => !mineIds.contains(c.id) && !pendingIds.contains(c.id))
        .toList();

    if (options.isEmpty) {
      showSnack(context, 'No other communities available to request');
      return;
    }

    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'An admin has to approve this before you can see those profiles.',
              ),
            ),
            for (final c in options)
              ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: Text(c.name),
                onTap: () => Navigator.pop(context, c.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;

    try {
      await context.read<MyAccountService>().requestCommunity(picked);
      if (mounted) {
        showSnack(context, S.requestSent);
        _load();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.changePassword),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(labelText: S.currentPassword),
                validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(labelText: S.newPassword),
                validator: (v) => (v ?? '').length < 6 ? 'Use at least 6 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(labelText: S.confirmPassword),
                validator: (v) => v != next.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text(S.save),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    try {
      await context.read<AuthService>().changePassword(
            current: current.text,
            next: next.text,
          );
      if (mounted) showSnack(context, 'Password changed');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  /// Edits one directory field (city or agency name) via PATCH /my/account
  /// (SPEC §9.6). An empty value clears it.
  Future<void> _editDirectoryField({required bool isCity}) async {
    final agent = context.read<AuthState>().agent;
    final ctl = TextEditingController(text: (isCity ? agent?.city : agent?.agencyName) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCity ? S.myCity : S.agencyName),
        content: TextFormField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => Navigator.pop(ctx, true),
          decoration: InputDecoration(
            labelText: isCity ? S.myCity : S.agencyName,
            hintText: isCity ? S.myCityHint : null,
            helperText: S.agentDirectoryNote,
            helperMaxLines: 3,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.save)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final value = ctl.text.trim();
    try {
      final updated = await context.read<MyAccountService>().updateAccount(
            city: isCity ? value : null,
            agencyName: isCity ? null : value,
          );
      if (!mounted) return;
      context.read<AuthState>().updateAgent(updated);
      showSnack(context, S.accountUpdated);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AuthState>().agent;
    final theme = Theme.of(context);
    final pending = _requests.where((r) => r.isPending).toList();
    final decided = _requests.where((r) => !r.isPending).toList();

    return Scaffold(
      appBar: AppBar(title: const Text(S.settings)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (_error != null) ...[
              ErrorState(message: _error!, onRetry: _load),
              const SizedBox(height: 24),
            ],
            const SectionHeader(S.myCommunities),
            if (_loading && _mine.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final c in _mine) Chip(label: Text(c.name))],
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _requestCommunity,
              icon: const Icon(Icons.add_rounded),
              label: const Text(S.requestCommunity),
            ),
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 24),
              const SectionHeader('Pending requests'),
              for (final r in pending)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.hourglass_top_rounded),
                  title: Text(r.communityName),
                  subtitle: const Text('Waiting for admin approval'),
                ),
            ],
            if (decided.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeader('Past requests'),
              for (final r in decided)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    r.status == 'approved' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: StatusColors.forRequestStatus(r.status, theme.colorScheme),
                  ),
                  title: Text(r.communityName),
                  subtitle: Text(r.status),
                ),
            ],
            const SizedBox(height: 32),
            // Directory details Gandharva customers see when choosing an agent.
            const SectionHeader(S.agentDirectory),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_city_rounded),
              title: const Text(S.myCity),
              subtitle: Text(
                (agent?.city ?? '').isNotEmpty ? agent!.city! : S.notSet,
                style: (agent?.city ?? '').isEmpty
                    ? TextStyle(color: theme.colorScheme.outline, fontStyle: FontStyle.italic)
                    : null,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editDirectoryField(isCity: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_rounded),
              title: const Text(S.agencyName),
              subtitle: Text(
                (agent?.agencyName ?? '').isNotEmpty ? agent!.agencyName! : S.notSet,
                style: (agent?.agencyName ?? '').isEmpty
                    ? TextStyle(color: theme.colorScheme.outline, fontStyle: FontStyle.italic)
                    : null,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editDirectoryField(isCity: false),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
              child: Text(
                S.agentDirectoryNote,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(height: 32),
            const SectionHeader('Account'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_rounded),
              title: Text(agent?.fullName ?? ''),
              subtitle: Text('+91 ${agent?.phone ?? ''}'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_reset_rounded),
              title: const Text(S.changePassword),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _changePassword,
            ),
          ],
        ),
      ),
    );
  }
}
