import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/profile.dart';
import '../../../state/masters_state.dart';
import '../../../state/profile_filters.dart';
import '../../strings.dart';
import '../../widgets/common.dart';
import '../../widgets/searchable_lists.dart';

/// Bottom sheet with the age/height sliders and multi-select chips (SPEC §5
/// screen 3). Long chip lists get a search field and long multi choices open
/// the searchable picker (SPEC §9.23 E).
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial, this.showStatusFilter = false});

  final ProfileFilters initial;
  final bool showStatusFilter;

  /// Returns the edited filters, or null if dismissed.
  static Future<ProfileFilters?> show(
    BuildContext context,
    ProfileFilters initial, {
    bool showStatusFilter = false,
  }) =>
      showModalBottomSheet<ProfileFilters>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FilterSheet(initial: initial, showStatusFilter: showStatusFilter),
      );

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late ProfileFilters _f = widget.initial;
  late final TextEditingController _city =
      TextEditingController(text: widget.initial.city ?? '');

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

  String get _heightTitle => _f.isHeightDefault
      ? '${S.heightRange}: any'
      : '${S.heightRange}: ${Profile.feetInches(_f.heightMin)} – ${Profile.feetInches(_f.heightMax)}';

  @override
  Widget build(BuildContext context) {
    final masters = context.watch<MastersState>().data;
    final theme = Theme.of(context);

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
                const SectionHeader(S.gender),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'any', label: Text(S.both)),
                    ButtonSegment(value: 'bride', label: Text(S.bride)),
                    ButtonSegment(value: 'groom', label: Text(S.groom)),
                  ],
                  selected: {_f.gender ?? 'any'},
                  onSelectionChanged: (s) => setState(() {
                    final v = s.first;
                    _f = v == 'any' ? _f.copyWith(clearGender: true) : _f.copyWith(gender: v);
                  }),
                ),
                const SizedBox(height: 24),
                SectionHeader(
                  '${S.ageRange}: ${_f.ageMin} – ${_f.ageMax} years',
                ),
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
                  min: ProfileFilters.defaultHeightMin.toDouble(),
                  max: ProfileFilters.defaultHeightMax.toDouble(),
                  divisions: ProfileFilters.defaultHeightMax - ProfileFilters.defaultHeightMin,
                  labels: RangeLabels(
                    Profile.feetInches(_f.heightMin),
                    Profile.feetInches(_f.heightMax),
                  ),
                  onChanged: (v) => setState(() => _f = _f.copyWith(
                        heightMin: v.start.round(),
                        heightMax: v.end.round(),
                      )),
                ),
                if (!_f.isHeightDefault)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      '${_f.heightMin} – ${_f.heightMax} cm',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                const SizedBox(height: 8),
                _ChipGroup(
                  title: S.community,
                  options: masterOptions(masters.communities),
                  selected: _f.communityIds,
                  onToggle: (id) => setState(() {
                    final communities = _toggle(_f.communityIds, id);
                    // A subcaste belongs to one community: drop any whose
                    // community was just deselected.
                    final stillValid = masters
                        .subcastesForAny(communities)
                        .map((s) => s.id)
                        .toSet();
                    _f = _f.copyWith(
                      communityIds: communities,
                      subcasteIds: _f.subcasteIds.where(stillValid.contains).toSet(),
                    );
                  }),
                ),
                // Subcaste chips appear only for the selected communities (SPEC §5).
                // A subcaste also matches its community's name in the search.
                _ChipGroup(
                  title: S.subcaste,
                  options: [
                    for (final s in masters.subcastesForAny(_f.communityIds))
                      PickerOption(
                        s.id,
                        _f.communityIds.length > 1
                            ? '${masters.communityName(s.communityId) ?? ''} · ${s.name}'
                            : s.name,
                        keywords: masters.communityName(s.communityId),
                      ),
                  ],
                  selected: _f.subcasteIds,
                  onToggle: (id) => setState(() => _f = _f.copyWith(
                        subcasteIds: _toggle(_f.subcasteIds, id),
                      )),
                ),
                _ChipGroup(
                  title: S.education,
                  options: masterOptions(masters.educations),
                  selected: _f.educationIds,
                  onToggle: (id) => setState(() => _f = _f.copyWith(
                        educationIds: _toggle(_f.educationIds, id),
                      )),
                ),
                _ChipGroup(
                  title: S.profession,
                  options: masterOptions(masters.professions),
                  selected: _f.professionIds,
                  onToggle: (id) => setState(() => _f = _f.copyWith(
                        professionIds: _toggle(_f.professionIds, id),
                      )),
                ),
                _ChipGroup(
                  title: S.occupationType,
                  options: masterOptions(masters.occupationTypes),
                  selected: _f.occupationTypeIds,
                  onToggle: (id) => setState(() => _f = _f.copyWith(
                        occupationTypeIds: _toggle(_f.occupationTypeIds, id),
                      )),
                ),
                // Work country — the public coarse location (SPEC §9.8). The
                // countries list is long, so it uses the picker dialog like the
                // NRI country below.
                if (masters.countries.isNotEmpty) ...[
                  const SectionHeader(S.worksIn),
                  MultiPickerField(
                    icon: Icons.public_rounded,
                    hint: S.anyWorkCountry,
                    selectedLabels: masters.countries
                        .where((c) => _f.workCountryIds.contains(c.id))
                        .map((c) => c.name)
                        .toList(),
                    onTap: () async {
                      final next = await showMultiPickerSheet(
                        context,
                        title: S.workCountry,
                        options: [
                          for (final c in masters.countries) PickerOption(c.id, c.name),
                        ],
                        selected: _f.workCountryIds,
                      );
                      if (next != null) setState(() => _f = _f.copyWith(workCountryIds: next));
                    },
                  ),
                  const SizedBox(height: 20),
                ],
                _ChipGroup(
                  title: S.maritalStatus,
                  options: masterOptions(masters.maritalStatuses),
                  selected: _f.maritalStatusIds,
                  onToggle: (id) => setState(() => _f = _f.copyWith(
                        maritalStatusIds: _toggle(_f.maritalStatusIds, id),
                      )),
                ),
                _ChipGroup(
                  title: S.complexion,
                  options: masterOptions(masters.complexions),
                  selected: _f.complexionIds,
                  onToggle: (id) => setState(() => _f = _f.copyWith(
                        complexionIds: _toggle(_f.complexionIds, id),
                      )),
                ),
                _ChipGroup(
                  title: S.religion,
                  options: masterOptions(masters.religions),
                  selected: _f.religionIds,
                  onToggle: (id) => setState(() => _f = _f.copyWith(
                        religionIds: _toggle(_f.religionIds, id),
                      )),
                ),
                _ChipGroup(
                  title: S.motherTongue,
                  options: masterOptions(masters.languages),
                  selected: _f.motherTongueIds,
                  onToggle: (id) => setState(() => _f = _f.copyWith(
                        motherTongueIds: _toggle(_f.motherTongueIds, id),
                      )),
                ),
                _ChipGroup(
                  title: S.knownLanguages,
                  options: masterOptions(masters.languages),
                  selected: _f.languageIds,
                  onToggle: (id) => setState(() => _f = _f.copyWith(
                        languageIds: _toggle(_f.languageIds, id),
                      )),
                ),
                _ChipGroup(
                  title: S.foodHabit,
                  options: masterOptions(masters.foodHabits),
                  selected: _f.foodHabitIds,
                  onToggle: (id) => setState(() => _f = _f.copyWith(
                        foodHabitIds: _toggle(_f.foodHabitIds, id),
                      )),
                ),
                const SectionHeader(S.nri),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(S.nriOnly),
                  subtitle: Text(
                    _f.nriOnly ? 'Pick one or more countries below, or leave it as any' : 'Profiles living or working abroad',
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
                  MultiPickerField(
                    icon: Icons.public_rounded,
                    hint: S.anyCountry,
                    selectedLabels: masters.countries
                        .where((c) => _f.countryIds.contains(c.id))
                        .map((c) => c.name)
                        .toList(),
                    onTap: () async {
                      final next = await showMultiPickerSheet(
                        context,
                        title: S.nriCountry,
                        options: [
                          for (final c in masters.countries) PickerOption(c.id, c.name),
                        ],
                        selected: _f.countryIds,
                      );
                      if (next != null) setState(() => _f = _f.copyWith(countryIds: next));
                    },
                  ),
                ],
                const SizedBox(height: 20),
                const SectionHeader(S.rasi),
                MultiPickerField(
                  hint: 'Any rasi',
                  selectedLabels: masters.zodiacSigns
                      .where((z) => _f.zodiacIds.contains(z.id))
                      .map((z) => z.label)
                      .toList(),
                  onTap: () async {
                    final next = await showMultiPickerSheet(
                      context,
                      title: S.rasi,
                      options: [
                        for (final z in masters.zodiacSigns) PickerOption(z.id, z.label),
                      ],
                      selected: _f.zodiacIds,
                    );
                    if (next != null) setState(() => _f = _f.copyWith(zodiacIds: next));
                  },
                ),
                const SizedBox(height: 20),
                const SectionHeader(S.nakshatram),
                MultiPickerField(
                  hint: 'Any nakshatram',
                  selectedLabels: masters.nakshatrams
                      .where((n) => _f.nakshatramIds.contains(n.id))
                      .map((n) => n.name)
                      .toList(),
                  onTap: () async {
                    final next = await showMultiPickerSheet(
                      context,
                      title: S.nakshatram,
                      options: [
                        for (final n in masters.nakshatrams) PickerOption(n.id, n.name),
                      ],
                      selected: _f.nakshatramIds,
                    );
                    if (next != null) setState(() => _f = _f.copyWith(nakshatramIds: next));
                  },
                ),
                const SizedBox(height: 24),
                const SectionHeader(S.place),
                TextField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: S.placeHint,
                    prefixIcon: Icon(Icons.place_rounded),
                  ),
                  onChanged: (v) =>
                      _f = _f.copyWith(city: v.trim(), clearCity: v.trim().isEmpty),
                ),
                if (widget.showStatusFilter) ...[
                  const SizedBox(height: 24),
                  const SectionHeader(S.profileStatus),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final s in ProfileStatus.values)
                        ChoiceChip(
                          label: Text(s.label),
                          selected: _f.status == s.apiValue,
                          onSelected: (on) => setState(() => _f =
                              on ? _f.copyWith(status: s.apiValue) : _f.copyWith(clearStatus: true)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                const SectionHeader(S.sortBy),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const {
                      'newest': 'Newest first',
                      'oldest': 'Oldest first',
                      'name': 'Name (A-Z)',
                      'age_asc': 'Age (low to high)',
                      'age_desc': 'Age (high to low)',
                    }.entries)
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
                  Navigator.pop(
                    context,
                    _f.copyWith(city: city, clearCity: city.isEmpty),
                  );
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

/// A titled chip group of the sheet; long ones get a search field above the
/// chips (SPEC §9.23 E).
class _ChipGroup extends StatelessWidget {
  const _ChipGroup({
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final String title;
  final List<PickerOption> options;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        SearchableChipGroup(
          key: ValueKey('chips-$title'),
          searchLabel: title,
          options: options,
          selected: selected,
          onToggle: onToggle,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
