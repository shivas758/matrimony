import 'package:flutter/material.dart';

import '../../models/master_data.dart';
import '../strings.dart';
import '../theme.dart';

/// Search inside long lists of master values (SPEC §9.23 E). One set of
/// widgets for every place a long list is picked from:
///
/// - [SearchableChipGroup] — filter sheets, the signup communities and the
///   audience communities: a search field above the chips; selected chips
///   always stay visible.
/// - [MasterSelectField] — single choice on a form: a plain dropdown for a
///   short list, a field that opens [showSinglePickerSheet] for a long one.
/// - [showMultiPickerSheet] + [MultiPickerField] — multi choice: a sheet with
///   a search field, checkboxes and Done.
///
/// "Long" = more than [kSearchThreshold] entries.

/// Lists with more entries than this get a search box.
const int kSearchThreshold = 8;

/// True when a list of [count] entries gets a search box.
bool isLongList(int count) => count > kSearchThreshold;

/// One entry of a searchable list. [keywords] also match the search but are
/// not shown — a subcaste carries its community's name there.
class PickerOption {
  const PickerOption(this.id, this.label, {this.keywords});

  final int id;
  final String label;
  final String? keywords;

  /// Case-insensitive, anywhere in the label or the keywords. An empty
  /// query matches everything.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return label.toLowerCase().contains(q) || (keywords ?? '').toLowerCase().contains(q);
  }

  @override
  bool operator ==(Object other) => other is PickerOption && other.id == id && other.label == label;

  @override
  int get hashCode => Object.hash(id, label);
}

/// The options matching [query], in their original order. Options whose id is
/// in [keep] (the selected ones) are always included.
List<PickerOption> filterPickerOptions(
  List<PickerOption> options,
  String query, {
  Set<int> keep = const {},
}) =>
    options.where((o) => keep.contains(o.id) || o.matches(query)).toList();

/// Master rows as picker options.
List<PickerOption> masterOptions(Iterable<MasterItem> items) =>
    [for (final i in items) PickerOption(i.id, i.name)];

/// "Community *" → "Community": a field label without the required mark.
String _plainLabel(String label) => label.replaceAll(RegExp(r'\s*\*\s*$'), '').trim();

// ======================================================================= chips

/// Multi-select chips; with more than [kSearchThreshold] options a search
/// field sits above them. Typing keeps only the matching chips — the
/// selected ones always stay visible.
class SearchableChipGroup extends StatefulWidget {
  const SearchableChipGroup({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
    this.searchLabel = '',
    this.enabled = true,
    this.compact = false,
  });

  final List<PickerOption> options;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  /// What the list is ("Community") — the search hint reads "Search community".
  final String searchLabel;
  final bool enabled;

  /// Compact chips (inside a card).
  final bool compact;

  @override
  State<SearchableChipGroup> createState() => _SearchableChipGroupState();
}

class _SearchableChipGroupState extends State<SearchableChipGroup> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchable = isLongList(widget.options.length);
    final visible = searchable
        ? filterPickerOptions(widget.options, _search.text, keep: widget.selected)
        : widget.options;
    final gap = widget.compact ? 6.0 : 8.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (searchable) ...[
          _SearchField(
            controller: _search,
            hint: S.searchIn(widget.searchLabel),
            enabled: widget.enabled,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 10),
        ],
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              S.noListMatches,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          )
        else
          Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final o in visible)
                FilterChip(
                  label: Text(o.label),
                  selected: widget.selected.contains(o.id),
                  visualDensity: widget.compact ? VisualDensity.compact : null,
                  onSelected: widget.enabled ? (_) => widget.onToggle(o.id) : null,
                ),
            ],
          ),
      ],
    );
  }
}

/// The search box of the chip groups and picker sheets.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        enabled: enabled,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: S.clearAll,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged();
                  },
                ),
        ),
        onChanged: (_) => onChanged(),
      );
}

// ============================================================== picker sheets

/// What a single-choice picker returns: the picked id, or null for "None".
/// The sheet itself returns null when dismissed.
class PickResult {
  const PickResult(this.id);

  final int? id;
}

/// Single choice from a list: tap to pick. With [allowClear] a "None" row
/// clears the value. Null when dismissed.
Future<PickResult?> showSinglePickerSheet(
  BuildContext context, {
  required String title,
  required List<PickerOption> options,
  int? selected,
  bool allowClear = false,
  String? note,
}) =>
    showModalBottomSheet<PickResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PickerSheet(
        title: _plainLabel(title),
        options: options,
        selected: {?selected},
        multi: false,
        allowClear: allowClear,
        note: note,
      ),
    );

/// Multi choice: checkboxes + Done. The new selection, or null when dismissed.
Future<Set<int>?> showMultiPickerSheet(
  BuildContext context, {
  required String title,
  required List<PickerOption> options,
  required Set<int> selected,
  String? note,
}) =>
    showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => PickerSheet(
        title: _plainLabel(title),
        options: options,
        selected: selected,
        multi: true,
        note: note,
      ),
    );

/// The sheet behind [showSinglePickerSheet] / [showMultiPickerSheet]: title,
/// an optional note, a search field (long lists), the filtered list, and
/// Done (multi). Public for tests.
class PickerSheet extends StatefulWidget {
  const PickerSheet({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.multi,
    this.allowClear = false,
    this.note,
  });

  final String title;
  final List<PickerOption> options;
  final Set<int> selected;
  final bool multi;
  final bool allowClear;
  final String? note;

  @override
  State<PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<PickerSheet> {
  final _search = TextEditingController();
  late final Set<int> _selected = {...widget.selected};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final searchable = isLongList(widget.options.length);
    final query = _search.text;
    // Multi choice keeps what is ticked in view while searching.
    final visible = filterPickerOptions(
      widget.options,
      query,
      keep: widget.multi ? _selected : const {},
    );
    final showNone = !widget.multi && widget.allowClear && query.trim().isEmpty;
    final maxHeight = (mq.size.height - mq.viewInsets.bottom) * 0.86;

    final Widget list = visible.isEmpty && !showNone
        ? Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              S.noListMatches,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          )
        : ListView.builder(
            shrinkWrap: !searchable,
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: visible.length + (showNone ? 1 : 0),
            itemBuilder: (context, i) {
              if (showNone && i == 0) {
                return ListTile(
                  key: const ValueKey('pick-none'),
                  title: Text(
                    S.pickNone,
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  trailing: _selected.isEmpty
                      ? const Icon(Icons.check_rounded, color: AppColors.navy)
                      : null,
                  onTap: () => Navigator.pop(context, const PickResult(null)),
                );
              }
              final o = visible[i - (showNone ? 1 : 0)];
              final on = _selected.contains(o.id);
              if (widget.multi) {
                return CheckboxListTile(
                  key: ValueKey('pick-${o.id}'),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: on,
                  title: Text(o.label),
                  onChanged: (v) => setState(() {
                    v == true ? _selected.add(o.id) : _selected.remove(o.id);
                  }),
                );
              }
              return ListTile(
                key: ValueKey('pick-${o.id}'),
                title: Text(
                  o.label,
                  style: on ? const TextStyle(fontWeight: FontWeight.w700) : null,
                ),
                trailing: on ? const Icon(Icons.check_rounded, color: AppColors.navy) : null,
                onTap: () => Navigator.pop(context, PickResult(o.id)),
              );
            },
          );

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Expanded(child: Text(widget.title, style: theme.textTheme.titleLarge)),
              if (widget.multi && _selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text(S.clearAll),
                ),
            ],
          ),
        ),
        if (widget.note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(widget.note!, style: theme.textTheme.bodyMedium),
          ),
        if (searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: _SearchField(
              controller: _search,
              hint: S.searchIn(widget.title),
              onChanged: () => setState(() {}),
            ),
          ),
        const Divider(height: 1),
        if (searchable) Expanded(child: list) else Flexible(child: list),
        if (widget.multi)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: const Text(S.done),
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      // A long list keeps one height while it filters; a short one hugs its rows.
      child: searchable
          ? SizedBox(height: maxHeight, child: body)
          : ConstrainedBox(constraints: BoxConstraints(maxHeight: maxHeight), child: body),
    );
  }
}

// ====================================================================== fields

/// A single-choice master field. Up to [kSearchThreshold] options: the plain
/// dropdown. More: a field that opens the searchable picker sheet.
///
/// [validator] is always called with the current [value].
class MasterSelectField extends StatelessWidget {
  const MasterSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.icon,
    this.helperText,
    this.validator,
    this.allowClear = true,
    this.enabled = true,
    this.menuMaxHeight,
  });

  final String label;
  final List<PickerOption> options;
  final int? value;
  final ValueChanged<int?> onChanged;
  final IconData? icon;
  final String? helperText;
  final FormFieldValidator<int>? validator;

  /// Offer "—" / "None" to clear the value.
  final bool allowClear;
  final bool enabled;
  final double? menuMaxHeight;

  @override
  Widget build(BuildContext context) {
    // Guard against a stale id that is no longer in the list (deactivated row).
    final safeValue = options.any((o) => o.id == value) ? value : null;
    final decoration = InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      helperText: helperText,
      helperMaxLines: 2,
    );

    if (!isLongList(options.length)) {
      return DropdownButtonFormField<int>(
        initialValue: safeValue,
        isExpanded: true,
        menuMaxHeight: menuMaxHeight,
        decoration: decoration,
        items: [
          if (allowClear) const DropdownMenuItem(value: null, child: Text('—')),
          for (final o in options)
            DropdownMenuItem(
              value: o.id,
              child: Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        validator: validator,
        onChanged: enabled ? onChanged : null,
      );
    }

    String? selectedLabel;
    for (final o in options) {
      if (o.id == safeValue) selectedLabel = o.label;
    }
    final shown = selectedLabel ?? (allowClear ? '—' : '');

    return FormField<int>(
      initialValue: safeValue,
      validator: validator == null ? null : (_) => validator!(safeValue),
      builder: (field) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !enabled
            ? null
            : () async {
                final picked = await showSinglePickerSheet(
                  field.context,
                  title: label,
                  options: options,
                  selected: safeValue,
                  allowClear: allowClear,
                );
                if (picked == null) return;
                if (field.mounted) field.didChange(picked.id);
                onChanged(picked.id);
              },
        child: InputDecorator(
          isEmpty: shown.isEmpty,
          decoration: decoration.copyWith(
            errorText: field.errorText,
            enabled: enabled,
            suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
          ),
          child: Text(shown, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// A tappable field that summarises a multi choice ("Telugu, English"); the
/// caller opens [showMultiPickerSheet] from [onTap].
class MultiPickerField extends StatelessWidget {
  const MultiPickerField({
    super.key,
    required this.selectedLabels,
    required this.onTap,
    this.label,
    this.hint,
    this.helperText,
    this.icon = Icons.auto_awesome_rounded,
  });

  final List<String> selectedLabels;
  final VoidCallback? onTap;

  /// A floating label (forms); without one the [hint] shows when empty.
  final String? label;
  final String? hint;
  final String? helperText;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = selectedLabels.isEmpty;
    final text = empty ? (label == null ? (hint ?? '') : '') : selectedLabels.join(', ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        isEmpty: label != null && empty,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          helperText: helperText,
          helperMaxLines: 2,
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: empty ? theme.colorScheme.outline : null),
        ),
      ),
    );
  }
}
