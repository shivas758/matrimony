import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/master_data.dart';
import '../../../models/profile.dart';
import '../../../state/browse_filters.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../widgets/common.dart';
import '../../widgets/searchable_list.dart';

/// Bottom sheet with the age / height sliders and the multi-select chips
/// (SPEC §9.11 Gandharva 3). Community chips are my agent's communities —
/// the server never shows anything outside them anyway. A chip group longer
/// than eight gets a search field above it, and the countries open a picker
/// with a search box (SPEC §9.23 E) — [SearchableChipGroup] /
/// [MultiPickerField].
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
                SearchableChipGroup(
                  title: S.community,
                  options: pickOptionsOf(communities),
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
                SearchableChipGroup(
                  title: S.subcaste,
                  options: [
                    for (final s in subcastes)
                      PickOption(
                        s.id,
                        scope.length > 1 ? '${masters.communityName(s.communityId) ?? ''} · ${s.name}' : s.name,
                        // Typing the community's name finds its subcastes too.
                        keywords: masters.communityName(s.communityId),
                      ),
                  ],
                  selected: _f.subcasteIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(subcasteIds: _toggle(_f.subcasteIds, id))),
                ),
                SearchableChipGroup(
                  title: S.education,
                  options: pickOptionsOf(masters.educations),
                  selected: _f.educationIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(educationIds: _toggle(_f.educationIds, id))),
                ),
                SearchableChipGroup(
                  title: S.profession,
                  options: pickOptionsOf(masters.professions),
                  selected: _f.professionIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(professionIds: _toggle(_f.professionIds, id))),
                ),
                SearchableChipGroup(
                  title: S.occupationType,
                  options: pickOptionsOf(masters.occupationTypes),
                  selected: _f.occupationTypeIds,
                  onToggle: (id) => setState(
                      () => _f = _f.copyWith(occupationTypeIds: _toggle(_f.occupationTypeIds, id))),
                ),
                SearchableChipGroup(
                  title: S.maritalStatus,
                  options: pickOptionsOf(masters.maritalStatuses),
                  selected: _f.maritalStatusIds,
                  onToggle: (id) => setState(
                      () => _f = _f.copyWith(maritalStatusIds: _toggle(_f.maritalStatusIds, id))),
                ),
                SearchableChipGroup(
                  title: S.religion,
                  options: pickOptionsOf(masters.religions),
                  selected: _f.religionIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(religionIds: _toggle(_f.religionIds, id))),
                ),
                SearchableChipGroup(
                  title: S.motherTongue,
                  options: pickOptionsOf(masters.languages),
                  selected: _f.motherTongueIds,
                  onToggle: (id) => setState(
                      () => _f = _f.copyWith(motherTongueIds: _toggle(_f.motherTongueIds, id))),
                ),
                SearchableChipGroup(
                  title: S.foodHabit,
                  options: pickOptionsOf(masters.foodHabits),
                  selected: _f.foodHabitIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(foodHabitIds: _toggle(_f.foodHabitIds, id))),
                ),
                SearchableChipGroup(
                  title: S.complexion,
                  options: pickOptionsOf(masters.complexions),
                  selected: _f.complexionIds,
                  onToggle: (id) =>
                      setState(() => _f = _f.copyWith(complexionIds: _toggle(_f.complexionIds, id))),
                ),
                // Work country — the public coarse location (SPEC §9.8).
                if (masters.countries.isNotEmpty) ...[
                  const SectionHeader(S.worksIn),
                  MultiPickerField(
                    icon: Icons.public_rounded,
                    hint: S.anyCountry,
                    title: S.workCountry,
                    options: pickOptionsOf(masters.countries),
                    selected: _f.workCountryIds,
                    onChanged: (next) => setState(() => _f = _f.copyWith(workCountryIds: next)),
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
                  MultiPickerField(
                    icon: Icons.public_rounded,
                    hint: S.anyCountry,
                    title: S.nriCountry,
                    options: pickOptionsOf(masters.countries),
                    selected: _f.countryIds,
                    onChanged: (next) => setState(() => _f = _f.copyWith(countryIds: next)),
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
