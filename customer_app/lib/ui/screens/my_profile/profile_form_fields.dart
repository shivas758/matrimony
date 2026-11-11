part of 'profile_form_screen.dart';

// The field widgets of the registration form (SPEC §9.18 F). They hold no
// profile state of their own — values and controllers live in
// [_ProfileFormScreenState] so they survive moving between the steps.

/// "Full name *" — how a required field is labelled.
String _required(String label) => '$label *';

class _MasterDropdown extends StatelessWidget {
  const _MasterDropdown({
    required this.label,
    required this.icon,
    required this.items,
    required this.value,
    required this.onChanged,
    this.requiredMessage,
  });

  final String label;
  final IconData icon;
  final List<MasterItem> items;
  final int? value;
  final ValueChanged<int?> onChanged;

  /// Set for a required choice: the message shown while nothing is picked.
  final String? requiredMessage;

  @override
  Widget build(BuildContext context) {
    // Guard against a stale id that is no longer in the list.
    final safeValue = items.any((i) => i.id == value) ? value : null;
    return DropdownButtonFormField<int>(
      // Re-created when the value is set from code (defaults after the masters
      // load), since a FormField only reads initialValue once.
      key: ValueKey('$label:${safeValue ?? 0}:${items.length}'),
      initialValue: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: requiredMessage == null ? label : _required(label),
        prefixIcon: Icon(icon),
        errorMaxLines: 2,
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('—')),
        for (final item in items)
          DropdownMenuItem(value: item.id, child: Text(item.name, overflow: TextOverflow.ellipsis)),
      ],
      validator: requiredMessage == null ? null : (v) => v == null ? requiredMessage : null,
      onChanged: onChanged,
    );
  }
}

class _TapField extends StatelessWidget {
  const _TapField({
    required this.label,
    required this.icon,
    required this.value,
    required this.hint,
    required this.onTap,
    this.onClear,
    this.errorText,
  });

  final String label;
  final IconData icon;
  final String? value;
  final String hint;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  /// Shown under the field in the error colour (a required pick is missing).
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          errorText: errorText,
          errorMaxLines: 2,
          suffixIcon: onClear == null
              ? null
              : IconButton(tooltip: S.clear, icon: const Icon(Icons.close_rounded), onPressed: onClear),
        ),
        child: Text(
          value ?? hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: value == null ? theme.colorScheme.outline : null),
        ),
      ),
    );
  }
}

/// Autocomplete over the community's subcastes; typing something new is fine —
/// the server creates it on save (SPEC §2). Always sends `subcaste_name`.
class _SubcasteField extends StatefulWidget {
  const _SubcasteField({
    required this.controller,
    required this.options,
    required this.enabled,
    required this.isNew,
    required this.onChanged,
  });

  final TextEditingController controller;
  final List<Subcaste> options;
  final bool enabled;
  final bool isNew;
  final VoidCallback onChanged;

  @override
  State<_SubcasteField> createState() => _SubcasteFieldState();
}

class _SubcasteFieldState extends State<_SubcasteField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Subcaste>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (s) => s.name,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return widget.options;
        return widget.options.where((s) => s.name.toLowerCase().contains(q));
      },
      onSelected: (_) => widget.onChanged(),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) => TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: widget.enabled,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: S.subcaste,
          prefixIcon: const Icon(Icons.account_tree_outlined),
          hintText: widget.enabled ? S.subcasteHint : S.subcasteNeedsCommunity,
          helperText: widget.isNew ? S.subcasteNew : null,
          helperMaxLines: 2,
        ),
        onChanged: (_) => widget.onChanged(),
        onSubmitted: (_) => onFieldSubmitted(),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final o in options) ListTile(title: Text(o.name), onTap: () => onSelected(o)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Multi-select chips for the languages a person knows.
class _LanguageChips extends StatelessWidget {
  const _LanguageChips({required this.items, required this.selected, required this.onToggle});

  final List<MasterItem> items;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: S.knownLanguages,
        prefixIcon: Icon(Icons.translate_rounded),
        contentPadding: EdgeInsets.fromLTRB(12, 14, 12, 10),
      ),
      child: items.isEmpty
          ? Text('—', style: TextStyle(color: theme.colorScheme.outline))
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in items)
                  FilterChip(
                    label: Text(item.name),
                    selected: selected.contains(item.id),
                    onSelected: (_) => onToggle(item.id),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
    );
  }
}

/// One row of the education table (SPEC §9.7): the level as the label, free
/// text for the school / college, and the country it was studied in.
class _EducationLevelRow extends StatelessWidget {
  const _EducationLevelRow({
    required this.level,
    required this.controller,
    required this.countries,
    required this.countryId,
    required this.onCountryChanged,
  });

  final EducationLevel level;
  final TextEditingController controller;
  final List<MasterItem> countries;
  final int? countryId;
  final ValueChanged<int?> onCountryChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = countries.any((c) => c.id == countryId) ? countryId : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: controller,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: level.label,
              hintText: S.educationLevelDetailsHint,
              counterText: '',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<int>(
            key: ValueKey('${level.apiValue}:${safeValue ?? 0}:${countries.length}'),
            initialValue: safeValue,
            isExpanded: true,
            decoration: const InputDecoration(labelText: S.country),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              for (final c in countries)
                DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onCountryChanged,
          ),
        ),
      ],
    );
  }
}

/// Name + occupation + phone for a parent (on request, SPEC §9.8).
class _PersonBlock extends StatelessWidget {
  const _PersonBlock({
    required this.nameController,
    required this.occupationController,
    required this.phoneController,
    required this.nameLabel,
    required this.occupationLabel,
    required this.phoneLabel,
  });

  final TextEditingController nameController;
  final TextEditingController occupationController;
  final TextEditingController phoneController;
  final String nameLabel;
  final String occupationLabel;
  final String phoneLabel;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextFormField(
            controller: nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: nameLabel,
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: occupationController,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: occupationLabel,
              hintText: S.occupationHint,
              prefixIcon: const Icon(Icons.work_outline_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          _PhoneField(controller: phoneController, label: phoneLabel),
        ],
      );
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
          LengthLimitingTextInputFormatter(15),
        ],
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.phone_outlined)),
      );
}

/// A small 0–20 number field for the siblings breakdown.
class _CountField extends StatelessWidget {
  const _CountField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: InputDecoration(labelText: label),
        validator: _ProfileFormScreenState._countError,
      );
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.existing,
    required this.added,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
    required this.onEditNew,
  });

  final List<ProfilePhoto> existing;
  final List<XFile> added;
  final VoidCallback onAdd;
  final ValueChanged<ProfilePhoto> onRemoveExisting;
  final ValueChanged<XFile> onRemoveNew;

  /// Opens the editor again on a photo that is not uploaded yet (SPEC §9.17).
  final ValueChanged<XFile> onEditNew;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final theme = Theme.of(context);

    Widget tile(Widget child, VoidCallback onRemove, {VoidCallback? onEdit}) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 104, height: 104, child: child),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: IconButton(
                tooltip: S.remove,
                icon: const CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close_rounded, size: 15, color: Colors.white),
                ),
                onPressed: onRemove,
              ),
            ),
            if (onEdit != null)
              Positioned(
                bottom: -6,
                right: -6,
                child: IconButton(
                  tooltip: S.editPhoto,
                  icon: const CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.crop_rotate_rounded, size: 14, color: Colors.white),
                  ),
                  onPressed: onEdit,
                ),
              ),
          ],
        );

    return SizedBox(
      height: 112,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: theme.colorScheme.primary),
                  const SizedBox(height: 6),
                  Text(S.addPhotos, style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ),
          for (final photo in existing) ...[
            const SizedBox(width: 10),
            tile(AuthedPhoto(url: photo.absoluteUrl, api: api), () => onRemoveExisting(photo)),
          ],
          for (final file in added) ...[
            const SizedBox(width: 10),
            tile(
              Image.file(File(file.path), fit: BoxFit.cover),
              () => onRemoveNew(file),
              onEdit: () => onEditNew(file),
            ),
          ],
        ],
      ),
    );
  }
}

/// Feet + inches pickers → centimetres.
class _HeightPickerDialog extends StatefulWidget {
  const _HeightPickerDialog({required this.initialCm});

  final int? initialCm;

  static Future<int?> show(BuildContext context, {int? initialCm}) => showDialog<int>(
        context: context,
        builder: (_) => _HeightPickerDialog(initialCm: initialCm),
      );

  @override
  State<_HeightPickerDialog> createState() => _HeightPickerDialogState();
}

class _HeightPickerDialogState extends State<_HeightPickerDialog> {
  late int _feet;
  late int _inches;

  @override
  void initState() {
    super.initState();
    final totalInches = ((widget.initialCm ?? 165) / 2.54).round();
    _feet = (totalInches ~/ 12).clamp(3, 7);
    _inches = (totalInches % 12).clamp(0, 11);
  }

  int get _cm => ((_feet * 12 + _inches) * 2.54).round();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text(S.heightPickerTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _feet,
                  decoration: const InputDecoration(labelText: S.feet),
                  items: [for (var f = 3; f <= 7; f++) DropdownMenuItem(value: f, child: Text("$f'"))],
                  onChanged: (v) => setState(() => _feet = v ?? _feet),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _inches,
                  decoration: const InputDecoration(labelText: S.inches),
                  items: [for (var i = 0; i <= 11; i++) DropdownMenuItem(value: i, child: Text('$i"'))],
                  onChanged: (v) => setState(() => _inches = v ?? _inches),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${Profile.feetInches(_cm)}  ·  $_cm cm',
            style: theme.textTheme.titleMedium?.copyWith(color: AppColors.wine),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _cm), child: const Text(S.done)),
      ],
    );
  }
}
