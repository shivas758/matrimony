import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/master_data.dart';
import '../../../models/profile.dart';
import '../../../state/browse_filters.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../widgets/common.dart';

/// Bottom sheet with the age / height sliders and the multi-select chips
/// (SPEC §9.11 Gandharva 3). Community chips are my agent's communities —
/// the server never shows anything outside them anyway.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial, required this.communities, this.guest = false});

  final BrowseFilters initial;

  /// Guest access (SPEC §9.13): every filter works, including place; only
  /// sort-by-name is not offered (a guest card has no name).
  final bool guest;

  /// The communities on offer (my agent's; all of them when the agent lists none).
  final List<MasterItem> communities;

  /// Returns the edited filters, or null if dismissed.
  static Future<BrowseFilters?> show(
    BuildContext context,
    BrowseFilters initial, {
    required List<MasterItem> communities,
    bool guest = false,
  }) =>
      showModalBottomSheet<BrowseFilters>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FilterSheet(initial: initial, communities: communities, guest: guest),
      );

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late BrowseFilters _f = widget.initial;
  late final TextEditingController _city = TextEditingController(text: widget.initial.city ?? '');

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  Set<int> _toggle(Set<int> current, int id) {
    final next = {...current};
    next.contains(id) ? next.remove(id) : next.add(id);
    return next;
  }

  String get _ageTitle => _f.isAgeDefault
      ? '${S.ageRange}: ${S.any}'
      : '${S.ageRange}: ${_f.ageMin} – ${_f.ageMax} ${S.yearsShort}';

  String get _heightTitle => _f.isHeightDefault
      ? '${S.heightRange}: ${S.any}'
      : '${S.heightRange}: ${Profile.feetInches(_f.heightMin)} – ${Profile.feetInches(_f.heightMax)}';

  @override
  Widget build(BuildContext context) {
    final masters = context.watch<MastersState>().data;
    final theme = Theme.of(context);
    final communities = widget.communities.isEmpty ? masters.communities : widget.communities;
    // Subcastes scoped to the selected communities, or to every offered
    // community when none is selected (SPEC §5 / §9.11).
    final scope = _f.communityIds.isEmpty ? communities.map((c) => c.id).toSet() : _f.communityIds;
    final subcastes = masters.subcastesForAny(scope);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Text(S.filters, style: theme.textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _f = _f.clearedFilters();
                    _city.clear();
                  }),
                  child: const Text(S.clearAll),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                SectionHeader(_ageTitle),
                RangeSlider(
                  values: RangeValues(_f.ageMin.toDouble(), _f.ageMax.toDouble()),
                  min: 18,
                  max: 70,
                  divisions: 52,
                  labels: RangeLabels('${_f.ageMin}', '${_f.ageMax}'),
                  onChanged: (v) => setState(() => _f = _f.copyWith(
                        ageMin: v.start.round(),
                        ageMax: v.end.round(),
                      )),
                ),
                const SizedBox(height: 8),
                // Height in feet/inches on screen, centimetres on the wire.
                SectionHeader(_heightTitle),
                RangeSlider(
                  values: RangeValues(_f.heightMin.toDouble(), _f.heightMax.toDouble()),
                  min: BrowseFilters.defaultHeightMin.toDouble(),
                  max: BrowseFilters.defaultHeightMax.toDouble(),
                  divisions: BrowseFilters.defaultHeightMax - BrowseFilters.defaultHeightMin,
                  labels: RangeLabels(
                    Profile.feetInches(_f.heightMin),
                    Profile.feetInches(_f.heightMax),
                  ),
                  onChanged: (v) => setState(() => _f = _f.copyWith(
                        heightMin: v.start.round(),
                        heightMax: v.end.round(),
                      )),
                ),
                const SizedBox(height: 12),
                _ChipGroup(
                  title: S.community,
                  items: communities,
                  selected: _f.communityIds,
                  onToggle: (id) => setState(() {
                    final next = _toggle(_f.communityIds, id);
                    // A subcaste belongs to one community: drop any whose
                    // community is no longer in scope.
                    final inScope = next.isEmpty ? communities.map((c) => c.id).toSet() : next;
                    final stillValid = masters.subcastesForAny(inScope).map((s) => s.id).toSet();
                    _f = _f.copyWith(
                      communityIds: next,
                      subcasteIds: _f.subcasteIds.where(stillValid.contains).toSet(),
                    );
                  }),
                ),
                _ChipGroup(
                  title: S.subcaste,
                  items: [
                    for (final s in subcastes)
                      MasterItem(
                        id: s.id,
                        name: scope.length > 1
                            ? '${masters.communityName(s.communityId) ?? ''} · ${s.name}'
                            : s.name,
                      ),
                  ],
                  selected: _f.subcasteIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(subcasteIds: _toggle(_f.subcasteIds, id))),
                ),
                _ChipGroup(
                  title: S.education,
                  items: masters.educations,
                  selected: _f.educationIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(educationIds: _toggle(_f.educationIds, id))),
                ),
                _ChipGroup(
                  title: S.profession,
                  items: masters.professions,
                  selected: _f.professionIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(professionIds: _toggle(_f.professionIds, id))),
                ),
                _ChipGroup(
                  title: S.occupationType,
                  items: masters.occupationTypes,
                  selected: _f.occupationTypeIds,
                  onToggle: (id) => setState(
                      () => _f = _f.copyWith(occupationTypeIds: _toggle(_f.occupationTypeIds, id))),
                ),
                _ChipGroup(
                  title: S.maritalStatus,
                  items: masters.maritalStatuses,
                  selected: _f.maritalStatusIds,
                  onToggle: (id) => setState(
                      () => _f = _f.copyWith(maritalStatusIds: _toggle(_f.maritalStatusIds, id))),
                ),
                _ChipGroup(
                  title: S.religion,
                  items: masters.religions,
                  selected: _f.religionIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(religionIds: _toggle(_f.religionIds, id))),
                ),
                _ChipGroup(
                  title: S.motherTongue,
                  items: masters.languages,
                  selected: _f.motherTongueIds,
                  onToggle: (id) => setState(
                      () => _f = _f.copyWith(motherTongueIds: _toggle(_f.motherTongueIds, id))),
                ),
                _ChipGroup(
                  title: S.foodHabit,
                  items: masters.foodHabits,
                  selected: _f.foodHabitIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(foodHabitIds: _toggle(_f.foodHabitIds, id))),
                ),
                _ChipGroup(
                  title: S.complexion,
                  items: masters.complexions,
                  selected: _f.complexionIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(complexionIds: _toggle(_f.complexionIds, id))),
                ),
                // Work country — the public coarse location (SPEC §9.8).
                if (masters.countries.isNotEmpty) ...[
                  const SectionHeader(S.worksIn),
                  _MultiPickerField(
                    icon: Icons.public_rounded,
                    hint: S.anyCountry,
                    selectedLabels: masters.countries
                        .where((c) => _f.workCountryIds.contains(c.id))
                        .map((c) => c.name)
                        .toList(),
                    onTap: () async {
                      final next = await _MultiPickerDialog.show(
                        context,
                        title: S.workCountry,
                        options: masters.countries,
                        selected: _f.workCountryIds,
                      );
                      if (next != null) setState(() => _f = _f.copyWith(workCountryIds: next));
                    },
                  ),
                  const SizedBox(height: 20),
                ],
                const SectionHeader(S.nri),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(S.nriOnly),
                  subtitle: Text(
                    _f.nriOnly ? S.nriOnlyOn : S.nriOnlyOff,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  secondary: const Icon(Icons.flight_takeoff_rounded),
                  value: _f.nriOnly,
                  onChanged: (on) => setState(() => _f = _f.copyWith(
                        nriOnly: on,
                        // Countries only make sense for NRI profiles.
                        countryIds: on ? _f.countryIds : const <int>{},
                      )),
                ),
                if (_f.nriOnly) ...[
                  const SizedBox(height: 8),
                  _MultiPickerField(
                    icon: Icons.public_rounded,
                    hint: S.anyCountry,
                    selectedLabels: masters.countries
                        .where((c) => _f.countryIds.contains(c.id))
                        .map((c) => c.name)
                        .toList(),
                    onTap: () async {
                      final next = await _MultiPickerDialog.show(
                        context,
                        title: S.nriCountry,
                        options: masters.countries,
                        selected: _f.countryIds,
                      );
                      if (next != null) setState(() => _f = _f.copyWith(countryIds: next));
                    },
                  ),
                ],
                const SizedBox(height: 24),
                const SectionHeader(S.place),
                TextField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: S.placeHint,
                    prefixIcon: Icon(Icons.place_rounded),
                  ),
                  onChanged: (v) => _f = _f.copyWith(city: v.trim(), clearCity: v.trim().isEmpty),
                ),
                const SizedBox(height: 24),
                const SectionHeader(S.sortBy),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const {
                      'newest': S.sortNewest,
                      'oldest': S.sortOldest,
                      'name': S.sortName,
                      'age_asc': S.sortAgeAsc,
                      'age_desc': S.sortAgeDesc,
                    }.entries.where((e) => !(widget.guest && e.key == 'name')))
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _f.sort == entry.key,
                        onSelected: (_) => setState(() => _f = _f.copyWith(sort: entry.key)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: FilledButton(
                onPressed: () {
                  final city = _city.text.trim();
                  Navigator.pop(context, _f.copyWith(city: city, clearCity: city.isEmpty));
                },
                child: const Text(S.apply),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({
    required this.title,
    required this.items,
    required this.selected,
    required this.onToggle,
  });

  final String title;
  final List<MasterItem> items;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              FilterChip(
                label: Text(item.name),
                selected: selected.contains(item.id),
                onSelected: (_) => onToggle(item.id),
              ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Tappable field that summarises a long multi-select (countries).
class _MultiPickerField extends StatelessWidget {
  const _MultiPickerField({
    required this.hint,
    required this.selectedLabels,
    required this.onTap,
    required this.icon,
  });

  final String hint;
  final List<String> selectedLabels;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = selectedLabels.isEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(prefixIcon: Icon(icon)),
        child: Text(
          empty ? hint : selectedLabels.join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: empty ? theme.colorScheme.outline : null),
        ),
      ),
    );
  }
}

class _MultiPickerDialog extends StatefulWidget {
  const _MultiPickerDialog({required this.title, required this.options, required this.selected});

  final String title;
  final List<MasterItem> options;
  final Set<int> selected;

  static Future<Set<int>?> show(
    BuildContext context, {
    required String title,
    required List<MasterItem> options,
    required Set<int> selected,
  }) =>
      showDialog<Set<int>>(
        context: context,
        builder: (_) => _MultiPickerDialog(title: title, options: options, selected: selected),
      );

  @override
  State<_MultiPickerDialog> createState() => _MultiPickerDialogState();
}

class _MultiPickerDialogState extends State<_MultiPickerDialog> {
  late final Set<int> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        contentPadding: const EdgeInsets.only(top: 12),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.options.length,
            itemBuilder: (_, i) {
              final o = widget.options[i];
              return CheckboxListTile(
                dense: true,
                value: _selected.contains(o.id),
                title: Text(o.name),
                onChanged: (on) => setState(() {
                  on == true ? _selected.add(o.id) : _selected.remove(o.id);
                }),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text(S.clearAll)),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, _selected), child: const Text(S.done)),
        ],
      );
}
