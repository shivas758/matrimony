import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/safety.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../../state/browse_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// More → *Blocked profiles* (SPEC §9.22 B): `GET /customer/blocks`, each
/// row with *Unblock* (`DELETE /customer/blocks/:profileId`). The name is
/// the one I saw when blocking — the profile itself stays hidden from me
/// until I unblock it.
class BlockedProfilesScreen extends StatefulWidget {
  const BlockedProfilesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BlockedProfilesScreen()),
      );

  @override
  State<BlockedProfilesScreen> createState() => _BlockedProfilesScreenState();
}

class _BlockedProfilesScreenState extends State<BlockedProfilesScreen> {
  List<BlockedProfile>? _blocks;
  String? _error;
  bool _loading = true;

  /// The row whose Unblock is in flight.
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
      final blocks = await context.read<ProfileService>().blockedProfiles();
      if (mounted) setState(() => _blocks = blocks);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(BlockedProfile block) async {
    if (_busyId != null) return;
    setState(() => _busyId = block.profileId);
    try {
      await context.read<ProfileService>().unblockProfile(block.profileId);
      if (!mounted) return;
      setState(() => _blocks = [...?_blocks]..removeWhere((b) => b.profileId == block.profileId));
      showSnack(context, S.unblockedSnack(block.displayLabel));
      // It may show up in Browse again.
      final browse = context.read<BrowseState?>();
      if (browse != null && browse.access != null) browse.refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks;
    Widget body;
    if (_loading && blocks == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (blocks == null) {
      body = ErrorState(message: _error ?? S.somethingWrong, onRetry: _load);
    } else if (blocks.isEmpty) {
      body = ListView(
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          const EmptyState(icon: Icons.block_rounded, title: S.noBlockedTitle, message: S.noBlockedBody),
        ],
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: blocks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _BlockTile(
          block: blocks[i],
          busy: _busyId == blocks[i].profileId,
          onUnblock: _busyId == null ? () => _unblock(blocks[i]) : null,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text(S.blockedProfiles)),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({required this.block, required this.busy, required this.onUnblock});

  final BlockedProfile block;
  final bool busy;
  final VoidCallback? onUnblock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: AppColors.goldLight, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: const Icon(Icons.block_rounded, size: 20, color: AppColors.wine),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.displayLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.wine),
                ),
                if (block.createdAt != null)
                  Text(
                    S.blockedOn(formatDate(block.createdAt)),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            // The theme's buttons are full width; this one sits in a row.
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: onUnblock,
            child: busy ? const ButtonSpinner(color: AppColors.wine) : const Text(S.unblock),
          ),
        ],
      ),
    );
  }
}
