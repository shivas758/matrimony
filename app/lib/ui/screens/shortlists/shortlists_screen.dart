import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/shortlist.dart';
import '../../../services/api_client.dart';
import '../../../services/share_service.dart';
import '../../strings.dart';
import '../../widgets/common.dart';
import '../profiles/profile_detail_screen.dart';
import '../notifications_screen.dart';

/// Shortlists grouped by client label (SPEC §5 screen 8).
class ShortlistsScreen extends StatefulWidget {
  const ShortlistsScreen({super.key});

  @override
  State<ShortlistsScreen> createState() => _ShortlistsScreenState();
}

class _ShortlistsScreenState extends State<ShortlistsScreen> {
  List<ShortlistGroup> _groups = [];
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
      final groups = await context.read<ShortlistService>().groups();
      if (mounted) setState(() => _groups = groups);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(ShortlistEntry entry) async {
    try {
      await context.read<ShortlistService>().remove(entry.shortlistId);
      if (mounted) {
        showSnack(context, 'Removed from shortlist');
        _load();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(S.shortlists), actions: const [NotificationBell()]),
      body: switch ((_loading && _groups.isEmpty, _error != null && _groups.isEmpty)) {
        (true, _) => const Center(child: CircularProgressIndicator()),
        (_, true) => ErrorState(message: _error!, onRetry: _load),
        _ => _groups.isEmpty
            ? RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  children: [
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
                    const EmptyState(
                      icon: Icons.bookmark_border_rounded,
                      title: S.noShortlists,
                      message: S.noShortlistsHint,
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: _groups.length,
                  itemBuilder: (_, i) {
                    final g = _groups[i];
                    return Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: i == 0,
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            '${g.profiles.length}',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(
                          g.displayLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('${g.profiles.length} profiles'),
                        children: [
                          for (final e in g.profiles)
                            Dismissible(
                              key: ValueKey(e.shortlistId),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                color: theme.colorScheme.errorContainer,
                                child: Icon(Icons.delete_rounded,
                                    color: theme.colorScheme.onErrorContainer),
                              ),
                              onDismissed: (_) => _remove(e),
                              child: ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: AuthedPhoto(
                                      url: e.photoAbsoluteUrl,
                                      api: api,
                                      placeholderInitials: initialsOf(e.fullName),
                                    ),
                                  ),
                                ),
                                title: Text(e.fullName),
                                subtitle: Text(
                                  [
                                    e.gender == 'bride' ? S.bride : S.groom,
                                    if (e.age != null) '${e.age} yrs',
                                    e.placeLine,
                                    e.community,
                                  ].whereType<String>().join(' · '),
                                ),
                                trailing: e.status == 'active'
                                    ? const Icon(Icons.chevron_right_rounded)
                                    : StatusChip(
                                        label: e.status,
                                        color: theme.colorScheme.outline,
                                      ),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ProfileDetailScreen(profileId: e.profileId),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      },
    );
  }
}
