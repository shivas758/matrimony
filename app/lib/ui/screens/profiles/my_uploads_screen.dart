import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'profile_detail_screen.dart';
import 'profile_form_screen.dart';

/// My uploads with status chips and quick status changes (SPEC §5 screen 6).
class MyUploadsScreen extends StatefulWidget {
  const MyUploadsScreen({super.key});

  @override
  State<MyUploadsScreen> createState() => _MyUploadsScreenState();
}

class _MyUploadsScreenState extends State<MyUploadsScreen> {
  final List<Profile> _profiles = [];
  String? _statusFilter;
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
      final page = await context.read<ProfileService>().list({
        'mine': 'true',
        'limit': 100,
        'sort': 'newest',
        if (_statusFilter != null) 'status': _statusFilter,
      });
      if (mounted) {
        setState(() {
          _profiles
            ..clear()
            ..addAll(page.profiles);
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(Profile p) async {
    final next = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in const {
              'active': ('Active — visible to other agents', Icons.check_circle_outline_rounded),
              'on_hold': ('On hold — talks in progress, hidden from others', Icons.pause_circle_outline_rounded),
              'engaged': ('Engaged — hidden from others', Icons.favorite_rounded),
              'married': ('Married — hidden from others', Icons.celebration_rounded),
              'hidden': ('Hidden — only you can see it', Icons.visibility_off_rounded),
            }.entries)
              ListTile(
                leading: Icon(entry.value.$2),
                title: Text(entry.value.$1),
                selected: p.status.apiValue == entry.key,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (next == null || next == p.status.apiValue || !mounted) return;

    try {
      await context.read<ProfileService>().update(p.id, {'status': next});
      if (mounted) {
        showSnack(context, 'Status updated');
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
      appBar: AppBar(
        title: Text('${S.myUploads}${_profiles.isNotEmpty ? ' (${_profiles.length})' : ''}'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const ProfileFormScreen()),
          );
          if (created == true) _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text(S.addProfile),
      ),
      body: Column(
        // Keeps the horizontal chip bar full-width instead of centred.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _statusFilter == null,
                  onSelected: (_) {
                    setState(() => _statusFilter = null);
                    _load();
                  },
                ),
                for (final s in ProfileStatus.values.map((v) => v.apiValue)) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(ProfileStatus.fromApi(s).label),
                    selected: _statusFilter == s,
                    onSelected: (_) {
                      setState(() => _statusFilter = s);
                      _load();
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(api, theme)),
        ],
      ),
    );
  }

  Widget _body(ApiClient api, ThemeData theme) {
    if (_loading && _profiles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _profiles.isEmpty) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_profiles.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'You have not added any profiles yet',
        message: S.noProfilesHint,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
        itemCount: _profiles.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 88),
        itemBuilder: (_, i) {
          final p = _profiles[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: AuthedPhoto(
                  url: p.primaryPhotoUrl,
                  api: api,
                  placeholderInitials: initialsOf(p.fullName),
                ),
              ),
            ),
            title: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  p.genderLabel,
                  if (p.ageDobLine != null) p.ageDobLine!,
                  p.community?.name,
                  if (p.photos.isEmpty) 'No photo',
                ].whereType<String>().join(' · '),
              ),
            ),
            trailing: ActionChip(
              label: Text(p.status.label),
              avatar: Icon(
                Icons.circle,
                size: 10,
                color: StatusColors.forProfileStatus(p.status.apiValue, theme.colorScheme),
              ),
              onPressed: () => _changeStatus(p),
            ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ProfileDetailScreen(profileId: p.id)),
              );
              _load();
            },
          );
        },
      ),
    );
  }
}
