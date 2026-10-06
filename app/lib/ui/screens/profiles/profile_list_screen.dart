import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/profile_filters.dart';
import '../../../state/profiles_state.dart';
import '../../strings.dart';
import '../../widgets/common.dart';
import 'filter_sheet.dart';
import 'profile_card.dart';
import 'profile_detail_screen.dart';
import 'profile_form_screen.dart';
import 'my_uploads_screen.dart';
import '../notifications_screen.dart';

class ProfileListScreen extends StatefulWidget {
  const ProfileListScreen({super.key});

  @override
  State<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<ProfileListScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      context.read<ProfilesState>().loadMore();
    }
  }

  Future<void> _openFilters() async {
    final state = context.read<ProfilesState>();
    final next = await FilterSheet.show(context, state.filters);
    if (next != null) await state.setFilters(next);
  }

  Future<void> _addProfile() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ProfileFormScreen()),
    );
    if (created == true && mounted) context.read<ProfilesState>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProfilesState>();
    final theme = Theme.of(context);
    final activeCount = state.filters.activeCount;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: S.searchHint,
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: context.read<ProfilesState>().setSearch,
              )
            : Text('${S.profiles}${state.total > 0 ? ' (${state.total})' : ''}'),
        actions: [
          IconButton(
            tooltip: _searching ? S.close : S.searchHint,
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                context.read<ProfilesState>().setSearch('');
              }
            },
          ),
          IconButton(
            tooltip: S.myUploads,
            icon: const Icon(Icons.folder_shared_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MyUploadsScreen()),
            ),
          ),
          const NotificationBell(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProfile,
        icon: const Icon(Icons.add_rounded),
        label: const Text(S.addProfile),
      ),
      body: Column(
        // Without this the filter bar shrinks to its content and floats centred.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterBar(
            activeCount: activeCount,
            onOpenFilters: _openFilters,
            presets: state.presets,
            onApplyPreset: (p) => context.read<ProfilesState>().applyPreset(p),
            onSavePreset: activeCount == 0 ? null : () => _promptSavePreset(context),
            onDeletePreset: (name) => context.read<ProfilesState>().deletePreset(name),
          ),
          Expanded(child: _body(state, theme)),
        ],
      ),
    );
  }

  Widget _body(ProfilesState state, ThemeData theme) {
    if (state.loading && state.profiles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.profiles.isEmpty) {
      return ErrorState(message: state.error!, onRetry: () => state.refresh());
    }
    if (state.isEmpty) {
      final filtered = state.filters.activeCount > 0 || (state.filters.query ?? '').isNotEmpty;
      return RefreshIndicator(
        onRefresh: state.refresh,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
            EmptyState(
              icon: filtered ? Icons.search_off_rounded : Icons.people_outline_rounded,
              title: filtered ? S.noMatches : S.noProfiles,
              message: filtered ? S.noMatchesHint : S.noProfilesHint,
              actionLabel: filtered ? S.clearAll : null,
              onAction: filtered
                  ? () => state.setFilters(ProfileFilters(sort: state.filters.sort))
                  : null,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          childAspectRatio: 0.62,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: state.profiles.length + (state.loadingMore ? 2 : 0),
        itemBuilder: (context, i) {
          if (i >= state.profiles.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = state.profiles[i];
          return ProfileCard(
            profile: profile,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileId: profile.id)),
            ),
          );
        },
      ),
    );
  }

  Future<void> _promptSavePreset(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.savePreset),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Brides 25-30 Kamma'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(S.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await context.read<ProfilesState>().savePreset(name);
      if (context.mounted) showSnack(context, 'Saved "$name"');
    }
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.activeCount,
    required this.onOpenFilters,
    required this.presets,
    required this.onApplyPreset,
    required this.onSavePreset,
    required this.onDeletePreset,
  });

  final int activeCount;
  final VoidCallback onOpenFilters;
  final List<FilterPreset> presets;
  final ValueChanged<FilterPreset> onApplyPreset;
  final VoidCallback? onSavePreset;
  final ValueChanged<String> onDeletePreset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Badge(
              isLabelVisible: activeCount > 0,
              label: Text('$activeCount'),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onPressed: onOpenFilters,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text(S.filters),
              ),
            ),
            if (onSavePreset != null) ...[
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: S.savePreset,
                icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                onPressed: onSavePreset,
              ),
            ],
            for (final preset in presets) ...[
              const SizedBox(width: 8),
              InputChip(
                label: Text(preset.name),
                avatar: const Icon(Icons.bookmark_rounded, size: 16),
                onPressed: () => onApplyPreset(preset),
                onDeleted: () => onDeletePreset(preset.name),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
