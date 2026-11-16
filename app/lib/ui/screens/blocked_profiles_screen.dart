import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/moderation.dart';
import '../../services/admin_service.dart';
import '../../services/api_client.dart';
import '../../state/profiles_state.dart';
import '../strings.dart';
import '../widgets/common.dart';

/// Settings → Blocked profiles (SPEC §9.22 B): what I blocked, with Unblock.
class BlockedProfilesScreen extends StatefulWidget {
  const BlockedProfilesScreen({super.key});

  @override
  State<BlockedProfilesScreen> createState() => _BlockedProfilesScreenState();
}

class _BlockedProfilesScreenState extends State<BlockedProfilesScreen> {
  List<BlockedProfile> _items = [];
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
      final items = await context.read<MyAccountService>().blocks();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(BlockedProfile b) async {
    setState(() => _busyId = b.profileId);
    try {
      await context.read<MyAccountService>().unblock(b.profileId);
      if (!mounted) return;
      setState(() => _items.removeWhere((x) => x.profileId == b.profileId));
      showSnack(context, S.unblocked(b.label));
      // The profile is back in the lists.
      Provider.of<ProfilesState?>(context, listen: false)?.refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.blockedProfiles)),
      body: _body(),
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
            const EmptyState(
              icon: Icons.block_rounded,
              title: S.noBlockedProfiles,
              message: S.noBlockedProfilesHint,
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
          final b = _items[i];
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Icon(Icons.block_rounded, color: theme.colorScheme.outline),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.label, style: theme.textTheme.titleSmall),
                      if (b.createdAt != null)
                        Text(
                          S.blockedOn(formatDate(b.createdAt)),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // The theme's buttons stretch full width — not in a row.
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: _busyId == b.profileId ? null : () => _unblock(b),
                  child: const Text(S.unblock),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
