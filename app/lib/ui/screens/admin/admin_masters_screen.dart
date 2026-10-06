import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/master_data.dart';
import '../../../services/admin_service.dart';
import '../../../services/api_client.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../widgets/common.dart';

/// Editor for the master lists. Seed data is only a starting point — the admin
/// grows these over time (SPEC §2). Subcastes belong to a community, so adding
/// one asks which community first.
class AdminMastersScreen extends StatefulWidget {
  const AdminMastersScreen({super.key});

  @override
  State<AdminMastersScreen> createState() => _AdminMastersScreenState();
}

class _AdminMastersScreenState extends State<AdminMastersScreen> {
  static const _tables = [
    (key: 'communities', label: S.community),
    (key: 'subcastes', label: S.subcaste),
    (key: 'educations', label: S.education),
    (key: 'professions', label: S.profession),
    (key: 'marital_statuses', label: S.maritalStatus),
    (key: 'complexions', label: S.complexion),
    (key: 'countries', label: 'NRI countries'),
    (key: 'religions', label: S.religion),
    (key: 'languages', label: 'Languages'),
    (key: 'food_habits', label: S.foodHabit),
    (key: 'nakshatrams', label: S.nakshatram),
    (key: 'zodiac_signs', label: S.rasi),
  ];

  String _table = 'communities';
  MasterData _data = MasterData.empty;
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
      final data = await context.read<AdminService>().allMasters();
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// After any edit, refresh the session-wide cache so forms pick it up.
  Future<void> _reloadEverywhere() async {
    await _load();
    if (mounted) await context.read<MastersState>().load(force: true);
  }

  List<({int id, String label, String name})> get _rows => switch (_table) {
        'subcastes' => [
            for (final s in _data.subcastes)
              (
                id: s.id,
                label: '${_data.communityName(s.communityId) ?? '?'} › ${s.name}',
                name: s.name,
              ),
          ],
        'educations' => _simple(_data.educations),
        'professions' => _simple(_data.professions),
        'marital_statuses' => _simple(_data.maritalStatuses),
        'complexions' => _simple(_data.complexions),
        'countries' => _simple(_data.countries),
        'religions' => _simple(_data.religions),
        'languages' => _simple(_data.languages),
        'food_habits' => _simple(_data.foodHabits),
        'nakshatrams' => _simple(_data.nakshatrams),
        'zodiac_signs' => [
            for (final z in _data.zodiacSigns) (id: z.id, label: z.label, name: z.label),
          ],
        _ => _simple(_data.communities),
      };

  List<({int id, String label, String name})> _simple(List<MasterItem> items) =>
      [for (final i in items) (id: i.id, label: i.name, name: i.name)];

  bool get _isZodiac => _table == 'zodiac_signs';
  bool get _isSubcaste => _table == 'subcastes';

  /// nakshatrams has no `active` column, and zodiac rows are a fixed pair.
  bool get _supportsDeactivate => !_isZodiac && _table != 'nakshatrams';

  Future<void> _addOrEdit({int? id, String? currentName}) async {
    final name = TextEditingController(text: currentName ?? '');
    final indian = TextEditingController();
    final english = TextEditingController();
    int? communityId = _data.communities.isNotEmpty ? _data.communities.first.id : null;
    final adding = id == null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(adding ? 'Add to ${_labelFor(_table)}' : 'Rename'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _isZodiac
                ? [
                    TextField(
                      controller: indian,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Indian name (e.g. Mesha)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: english,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'English name (e.g. Aries)'),
                    ),
                  ]
                : [
                    if (_isSubcaste && adding) ...[
                      DropdownButtonFormField<int>(
                        initialValue: communityId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: S.community,
                          prefixIcon: Icon(Icons.groups_rounded),
                        ),
                        items: [
                          for (final c in _data.communities)
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                        ],
                        onChanged: (v) => setInner(() => communityId = v),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                  ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.save)),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;

    final body = _isZodiac
        ? <String, dynamic>{'indian_name': indian.text.trim(), 'english_name': english.text.trim()}
        : <String, dynamic>{'name': name.text.trim()};
    if (body.values.any((v) => '$v'.isEmpty)) return;
    if (_isSubcaste && adding) {
      if (communityId == null) {
        showSnack(context, 'Select a community', error: true);
        return;
      }
      body['community_id'] = communityId;
    }

    try {
      final service = context.read<AdminService>();
      if (adding) {
        await service.addMaster(_table, body);
      } else {
        await service.updateMaster(_table, id, body);
      }
      if (mounted) {
        showSnack(context, adding ? 'Added' : 'Updated');
        await _reloadEverywhere();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _setActive(int id, bool active) async {
    try {
      await context.read<AdminService>().updateMaster(_table, id, {'active': active});
      if (mounted) {
        showSnack(context, active ? 'Enabled' : 'Hidden from the app');
        await _reloadEverywhere();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  String _labelFor(String key) =>
      _tables.firstWhere((t) => t.key == key, orElse: () => _tables.first).label;

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    // /masters?include_inactive=true returns inactive rows too; the plain call
    // does not, so anything missing from the active list is inactive.
    final active = context.watch<MastersState>().data;
    final activeIds = switch (_table) {
      'subcastes' => active.subcastes.map((e) => e.id).toSet(),
      'educations' => active.educations.map((e) => e.id).toSet(),
      'professions' => active.professions.map((e) => e.id).toSet(),
      'marital_statuses' => active.maritalStatuses.map((e) => e.id).toSet(),
      'complexions' => active.complexions.map((e) => e.id).toSet(),
      'countries' => active.countries.map((e) => e.id).toSet(),
      'religions' => active.religions.map((e) => e.id).toSet(),
      'languages' => active.languages.map((e) => e.id).toSet(),
      'food_habits' => active.foodHabits.map((e) => e.id).toSet(),
      'nakshatrams' => active.nakshatrams.map((e) => e.id).toSet(),
      'zodiac_signs' => active.zodiacSigns.map((e) => e.id).toSet(),
      _ => active.communities.map((e) => e.id).toSet(),
    };

    return Scaffold(
      appBar: AppBar(title: const Text(S.masterTables)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add_rounded),
        label: Text('Add ${_labelFor(_table).toLowerCase()}'),
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
                for (final t in _tables) ...[
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _table == t.key,
                    onSelected: (_) => setState(() => _table = t.key),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading && rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null && rows.isEmpty
                    ? ErrorState(message: _error!, onRetry: _load)
                    : rows.isEmpty
                        ? EmptyState(
                            icon: Icons.list_alt_rounded,
                            title: _isSubcaste
                                ? 'No subcastes yet'
                                : 'Nothing in ${_labelFor(_table).toLowerCase()} yet',
                            message: _isSubcaste
                                ? 'Agents add them by typing on the profile form, or add one here.'
                                : null,
                          )
                        : RefreshIndicator(
                            onRefresh: _reloadEverywhere,
                            child: ListView.separated(
                              padding: const EdgeInsets.only(bottom: 96),
                              itemCount: rows.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final row = rows[i];
                                final isActive = activeIds.contains(row.id);
                                return ListTile(
                                  title: Text(
                                    row.label,
                                    style: TextStyle(
                                      decoration: isActive ? null : TextDecoration.lineThrough,
                                      color: isActive ? null : Theme.of(context).colorScheme.outline,
                                    ),
                                  ),
                                  subtitle: isActive ? null : const Text('Hidden from the app'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () =>
                                            _addOrEdit(id: row.id, currentName: row.name),
                                      ),
                                      if (_supportsDeactivate)
                                        Switch(
                                          value: isActive,
                                          onChanged: (on) => _setActive(row.id, on),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
