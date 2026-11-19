import 'package:flutter/material.dart';

import '../../models/master_data.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';

/// Search inside long lists of master values (SPEC §9.23 E / §9.24 B) — one
/// widget set for the Browse filter sheet, the four-step profile form and
/// the privacy audience:
///
/// * [SearchableChipGroup] — filter chips with a search field above them once
///   there are more than [kSearchableAfter]; selected chips always stay.
/// * [SearchablePickerField] — a single choice: the field opens
///   [showSingleChoicePicker] (search on top, tap to pick).
/// * [MultiPickerField] — a multi choice: the field opens
///   [showMultiChoicePicker] (search on top, checkboxes, Done).
/// * [FilterChoiceGroup] — a Browse filter: chips for a short list, a
///   [MultiPickerField] with removable chips for a long one.
///
/// Matching is case-insensitive, anywhere in the name — and in an option's
/// [PickOption.keywords] (a subcaste is also found by its community's name).

/// Lists longer than this get a search box; shorter ones stay as they are.
const int kSearchableAfter = 8;

/// More than [kSearchableAfter] entries.
bool isLongList(int length) => length > kSearchableAfter;

/// One entry of a long list.
class PickOption {
  const PickOption(this.id, this.label, {this.keywords});

  final int id;

  /// What the person reads.
  final String label;

  /// Other words it can be found by (not shown).
  final String? keywords;

  /// Matches [query] — case-insensitive, anywhere in the label or keywords;
  /// a blank query matches everything.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return label.toLowerCase().contains(q) || (keywords?.toLowerCase().contains(q) ?? false);
  }
}

/// [items] as picker options (label = name).
List<PickOption> pickOptionsOf(Iterable<MasterItem> items) => [for (final i in items) PickOption(i.id, i.name)];

/// The [options] that match [query]; the ids in [keep] (the selected ones)
/// always stay. The original order is kept.
List<PickOption> filterOptions(List<PickOption> options, String query, {Set<int> keep = const {}}) =>
    options.where((o) => keep.contains(o.id) || o.matches(query)).toList();

/// The search box above a long list: a magnifier, the hint and a clear button.
class ListSearchField extends StatelessWidget {
  const ListSearchField({super.key, required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: S.clear,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ),
      );
}

/// A titled group of filter chips (the Browse filter sheet). With more than
/// [kSearchableAfter] options a search field sits above the chips: typing
/// keeps only the matching ones, and the selected ones always stay visible.
class SearchableChipGroup extends StatefulWidget {
  const SearchableChipGroup({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final String title;
  final List<PickOption> options;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  State<SearchableChipGroup> createState() => _SearchableChipGroupState();
}

class _SearchableChipGroupState extends State<SearchableChipGroup> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    final searchable = isLongList(widget.options.length);
    final shown = searchable ? filterOptions(widget.options, _query, keep: widget.selected) : widget.options;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(widget.title),
        if (searchable) ...[
          ListSearchField(
            controller: _search,
            hint: S.searchIn(widget.title),
            onChanged: (q) => setState(() => _query = q),
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in shown)
              FilterChip(
                label: Text(o.label),
                selected: widget.selected.contains(o.id),
                onSelected: (_) => widget.onToggle(o.id),
              ),
          ],
        ),
        if (searchable && !shown.any((o) => !widget.selected.contains(o.id)) && _query.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(S.nothingMatches, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// What a single-choice picker gave back: [id], or null when the choice was
/// cleared. (Dismissing the sheet gives no [PickResult] at all.)
class PickResult {
  const PickResult(this.id);

  final int? id;
}

/// A bottom sheet with a search field and the filtered list; tap an entry to
/// pick it. *Clear* (when [allowClear] and something is picked) empties the
/// choice. Null when dismissed.
Future<PickResult?> showSingleChoicePicker(
  BuildContext context, {
  required String title,
  required List<PickOption> options,
  int? selected,
  bool allowClear = true,
}) =>
    showModalBottomSheet<PickResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PickerSheet(
        title: title,
        options: options,
        selected: {?selected},
        multi: false,
        allowClear: allowClear,
      ),
    );

/// A bottom sheet with a search field, the filtered list with checkboxes and
/// *Done*. Gives the new selection; null when dismissed.
Future<Set<int>?> showMultiChoicePicker(
  BuildContext context, {
  required String title,
  required List<PickOption> options,
  required Set<int> selected,
}) =>
    showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PickerSheet(title: title, options: options, selected: selected, multi: true),
    );

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.multi,
    this.allowClear = true,
  });

  final String title;
  final List<PickOption> options;
  final Set<int> selected;
  final bool multi;
  final bool allowClear;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _search = TextEditingController();
  late final Set<int> _selected = {...widget.selected};
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = filterOptions(widget.options, _query);
    final canClear = widget.multi ? _selected.isNotEmpty : widget.allowClear && _selected.isNotEmpty;
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.wine)),
                      if (widget.multi && _selected.isNotEmpty)
                        Text(
                          S.selectedCount(_selected.length),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                    ],
                  ),
                ),
                if (canClear)
                  TextButton(
                    onPressed: () => widget.multi
                        ? setState(_selected.clear)
                        : Navigator.of(context).pop(const PickResult(null)),
                    child: Text(widget.multi ? S.clearAll : S.clear),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: ListSearchField(
              controller: _search,
              hint: S.searchIn(widget.title),
              onChanged: (q) => setState(() => _query = q),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: shown.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      S.nothingMatches,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                    ),
                  )
                : ListView.builder(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final o = shown[i];
                      final on = _selected.contains(o.id);
                      if (widget.multi) {
                        return CheckboxListTile(
                          dense: true,
                          value: on,
                          title: Text(o.label),
                          onChanged: (v) => setState(() => v == true ? _selected.add(o.id) : _selected.remove(o.id)),
                        );
                      }
                      return ListTile(
                        dense: true,
                        selected: on,
                        title: Text(o.label),
                        trailing: on ? const Icon(Icons.check_rounded, color: AppColors.wine) : null,
                        onTap: () => Navigator.of(context).pop(PickResult(o.id)),
                      );
                    },
                  ),
          ),
          if (widget.multi)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(<int>{..._selected}),
                  child: const Text(S.done),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single choice of a long list inside a form: looks like the dropdown,
/// opens [showSingleChoicePicker]. A [FormField], so a required choice
/// ([validator]) shows its message like any other field.
class SearchablePickerField extends StatelessWidget {
  const SearchablePickerField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.icon,
    this.validator,
    this.pickerTitle,
  });

  final String label;
  final List<PickOption> options;
  final int? value;
  final ValueChanged<int?> onChanged;
  final IconData? icon;
  final FormFieldValidator<int>? validator;

  /// The sheet's title; [label] without a trailing "*" when null.
  final String? pickerTitle;

  @override
  Widget build(BuildContext context) {
    // A stale id that is no longer in the list reads as nothing picked.
    String? labelOf(int? id) {
      for (final o in options) {
        if (o.id == id) return o.label;
      }
      return null;
    }

    final current = labelOf(value);
    final safeValue = current == null ? null : value;
    return FormField<int>(
      // Re-created when the value is set from code (a FormField reads its
      // initial value once) — the same as the plain dropdown.
      key: ValueKey('$label:${safeValue ?? 0}:${options.length}'),
      initialValue: safeValue,
      validator: validator,
      builder: (field) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showSingleChoicePicker(
            context,
            title: pickerTitle ?? label.replaceAll(RegExp(r'\s*\*$'), ''),
            options: options,
            selected: safeValue,
          );
          if (picked == null) return;
          field.didChange(picked.id);
          onChanged(picked.id);
        },
        child: InputDecorator(
          isEmpty: current == null,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: icon == null ? null : Icon(icon),
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
            errorText: field.errorText,
            errorMaxLines: 2,
          ),
          child: Text(current ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// A multi choice of a long list: the picked names (or [hint]) in a field
/// that opens [showMultiChoicePicker]. With [removableChips] (the Browse
/// filters, SPEC §9.24 B) the picked values show as small chips, each with
/// its own ×, and a × at the end of the field clears them all.
class MultiPickerField extends StatelessWidget {
  const MultiPickerField({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.hint,
    this.icon,
    this.label,
    this.removableChips = false,
  });

  /// The sheet's title.
  final String title;
  final List<PickOption> options;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final String hint;
  final IconData? icon;

  /// The field's own label, when it has one.
  final String? label;

  /// Picked values as removable chips instead of one comma-separated line.
  final bool removableChips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = [for (final o in options) if (selected.contains(o.id)) o];
    final empty = picked.isEmpty;
    final chips = removableChips && !empty;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final next = await showMultiChoicePicker(context, title: title, options: options, selected: selected);
        if (next != null) onChanged(next);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
          suffixIcon: chips
              ? IconButton(
                  tooltip: S.clear,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => onChanged(<int>{}),
                )
              : const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: chips
            ? Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // Tapping a chip itself opens the picker (the field's tap);
                  // its × removes just that value.
                  for (final o in picked)
                    InputChip(
                      label: Text(o.label),
                      onDeleted: () => onChanged({...selected}..remove(o.id)),
                      deleteButtonTooltipMessage: S.removeValue(o.label),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              )
            : Text(
                empty ? hint : picked.map((o) => o.label).join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: empty ? theme.colorScheme.outline : null),
              ),
      ),
    );
  }
}

/// One multi-choice filter of the Browse sheet (SPEC §9.24 B), in the
/// profile form's format: up to [kSearchableAfter] values stay plain chips
/// ([SearchableChipGroup]); a longer list is one compact
/// [MultiPickerField] — "Any" or the chosen values as removable chips — that
/// opens the picker sheet (search, checkboxes, Clear all, Done), so the
/// filter sheet no longer grows with the master lists. An empty list shows
/// nothing.
class FilterChoiceGroup extends StatelessWidget {
  const FilterChoiceGroup({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.icon,
    this.hint = S.anyValue,
  });

  /// The section heading and the picker sheet's title.
  final String title;
  final List<PickOption> options;
  final Set<int> selected;

  /// The whole new selection.
  final ValueChanged<Set<int>> onChanged;

  /// The picker field's icon (long lists only).
  final IconData? icon;

  /// What the picker field reads while nothing is chosen.
  final String hint;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    if (!isLongList(options.length)) {
      return SearchableChipGroup(
        title: title,
        options: options,
        selected: selected,
        onToggle: (id) => onChanged(selected.contains(id) ? ({...selected}..remove(id)) : {...selected, id}),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        MultiPickerField(
          title: title,
          hint: hint,
          icon: icon,
          options: options,
          selected: selected,
          onChanged: onChanged,
          removableChips: true,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
