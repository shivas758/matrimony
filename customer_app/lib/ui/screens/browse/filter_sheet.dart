import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/master_data.dart';
import '../../../models/profile.dart';
import '../../../state/browse_filters.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../widgets/common.dart';
import '../../widgets/searchable_list.dart';

/// Bottom sheet with the age / height sliders and the multi-choice filters
/// (SPEC §9.11 Gandharva 3). The communities on offer are my agent's — the
/// server never shows anything outside them anyway. Every list in the
/// profile form's format (SPEC §9.24 B, [FilterChoiceGroup]): up to eight
/// values as chips; a longer one (community, subcaste, education,
/// profession, …) is one picker field — "Any" or the chosen values as
/// removable chips — that opens the picker sheet with a search box,
/// checkboxes and Done; the countries always open the picker. So the sheet
/// scrolls a screen or two at most, however long the master lists are.
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

  /// New communities; a subcaste belongs to one community, so any whose
  /// community is no longer in scope is dropped.
  void _setCommunities(Set<int> next, List<MasterItem> offered, MasterData masters) {
    final inScope = next.isEmpty ? offered.map((c) => c.id).toSet() : next;
    final stillValid = masters.subcastesForAny(inScope).map((s) => s.id).toSet();
    setState(() => _f = _f.copyWith(
          communityIds: next,
          subcasteIds: _f.subcasteIds.where(stillValid.contains).toSet(),
        ));
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
                FilterChoiceGroup(
                  title: S.community,
                  icon: Icons.groups_rounded,
                  options: pickOptionsOf(communities),
                  selected: _f.communityIds,
                  onChanged: (next) => _setCommunities(next, communities, masters),
                ),
                FilterChoiceGroup(
                  title: S.subcaste,
                  icon: Icons.account_tree_outlined,
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
                  onChanged: (next) => setState(() => _f = _f.copyWith(subcasteIds: next)),
                ),
                FilterChoiceGroup(
                  title: S.education,
                  icon: Icons.school_rounded,
                  options: pickOptionsOf(masters.educations),
                  selected: _f.educationIds,
                  onChanged: (next) => setState(() => _f = _f.copyWith(educationIds: next)),
                ),
                FilterChoiceGroup(
                  title: S.profession,
                  icon: Icons.work_outline_rounded,
                  options: pickOptionsOf(masters.professions),
                  selected: _f.professionIds,
                  onChanged: (next) => setState(() => _f = _f.copyWith(professionIds: next)),
                ),
                FilterChoiceGroup(
                  title: S.occupationType,
                  icon: Icons.badge_outlined,
                  options: pickOptionsOf(masters.occupationTypes),
                  selected: _f.occupationTypeIds,
                  onChanged: (next) => setState(() => _f = _f.copyWith(occupationTypeIds: next)),
                ),
                FilterChoiceGroup(
                  title: S.maritalStatus,
                  icon: Icons.favorite_border_rounded,
                  options: pickOptionsOf(masters.maritalStatuses),
                  selected: _f.maritalStatusIds,
                  onChanged: (next) => setState(() => _f = _f.copyWith(maritalStatusIds: next)),
                ),
                FilterChoiceGroup(
                  title: S.religion,
                  icon: Icons.temple_hindu_rounded,
                  options: pickOptionsOf(masters.religions),
                  selected: _f.religionIds,
                  onChanged: (next) => setState(() => _f = _f.copyWith(religionIds: next)),
                ),
                FilterChoiceGroup(
                  title: S.motherTongue,
                  icon: Icons.record_voice_over_outlined,
                  options: pickOptionsOf(masters.languages),
                  selected: _f.motherTongueIds,
                  onChanged: (next) => setState(() => _f = _f.copyWith(motherTongueIds: next)),
                ),
                FilterChoiceGroup(
                  title: S.foodHabit,
                  icon: Icons.restaurant_rounded,
                  options: pickOptionsOf(masters.foodHabits),
                  selected: _f.foodHabitIds,
                  onChanged: (next) => setState(() => _f = _f.copyWith(foodHabitIds: next)),
                ),
                FilterChoiceGroup(
                  title: S.complexion,
                  icon: Icons.face_rounded,
                  options: pickOptionsOf(masters.complexions),
                  selected: _f.complexionIds,
                  onChanged: (next) => setState(() => _f = _f.copyWith(complexionIds: next)),
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
                    removableChips: true,
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
                    removableChips: true,
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
