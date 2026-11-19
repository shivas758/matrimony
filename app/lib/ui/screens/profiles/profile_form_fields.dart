part of 'profile_form_screen.dart';

// The building blocks of the profile form: the field widgets the four steps
// (profile_form_steps.dart) are made of.

// ==================================================================== fields

/// "STEP 2 OF 4" over the step's title — the heading of each step's page.
class _StepTitle extends StatelessWidget {
  const _StepTitle(this.step);

  final ProfileFormStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.position.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.goldDark,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(step.title, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.navy)),
        ],
      ),
    );
  }
}

/// Autocomplete over the community's subcastes; typing something new is fine —
/// the server creates it on save (SPEC §2).
class _SubcasteField extends StatefulWidget {
  const _SubcasteField({
    required this.controller,
    required this.options,
    required this.enabled,
    required this.isNew,
    required this.onSelected,
    required this.onTyped,
  });

  final TextEditingController controller;
  final List<Subcaste> options;
  final bool enabled;
  final bool isNew;
  final ValueChanged<Subcaste> onSelected;
  final ValueChanged<String> onTyped;

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
    final helper = widget.isNew ? S.subcasteNew : null;

    return RawAutocomplete<Subcaste>(
      textEditingController: widget.controller,
      focusNode: _focus,
      displayStringForOption: (s) => s.name,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return widget.options;
        return widget.options.where((s) => s.name.toLowerCase().contains(q));
      },
      onSelected: widget.onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) => TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: widget.enabled,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: S.subcaste,
          prefixIcon: const Icon(Icons.account_tree_outlined),
          hintText: widget.enabled ? S.subcasteHint : S.subcasteNeedsCommunity,
          helperText: helper,
          helperMaxLines: 2,
        ),
        onChanged: widget.onTyped,
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
              child: SizedBox(width: 100, height: 100, child: child),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: IconButton(
                tooltip: S.removePhoto,
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
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 100,
              height: 100,
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

/// A master field of the form: the plain dropdown for a short list, the
/// searchable picker sheet for a long one (SPEC §9.23 E).
class _MasterDropdown extends StatelessWidget {
  const _MasterDropdown({
    required this.label,
    required this.icon,
    required this.items,
    required this.value,
    required this.onChanged,
    this.helperText,
    this.validator,
  });

  final String label;
  final IconData icon;
  final List<MasterItem> items;
  final int? value;
  final ValueChanged<int?> onChanged;

  /// Plain guidance under the field.
  final String? helperText;

  /// Set for a required field (the community).
  final FormFieldValidator<int>? validator;

  @override
  Widget build(BuildContext context) => MasterSelectField(
        label: label,
        icon: icon,
        options: masterOptions(items),
        value: value,
        helperText: helperText,
        validator: validator,
        onChanged: onChanged,
      );
}

/// The languages a person knows: chips for a short list, the searchable
/// multi picker for a long one (SPEC §9.23 E).
class _LanguageChips extends StatelessWidget {
  const _LanguageChips({
    required this.items,
    required this.selected,
    required this.onToggle,
    required this.onReplace,
  });

  final List<MasterItem> items;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  /// Long list: the picker's whole new selection.
  final ValueChanged<Set<int>> onReplace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (isLongList(items.length)) {
      return MultiPickerField(
        label: S.knownLanguages,
        icon: Icons.translate_rounded,
        selectedLabels: [
          for (final item in items)
            if (selected.contains(item.id)) item.name,
        ],
        onTap: () async {
          final next = await showMultiPickerSheet(
            context,
            title: S.knownLanguages,
            options: masterOptions(items),
            selected: selected,
          );
          if (next != null) onReplace(next);
        },
      );
    }
    return InputDecorator(
      decoration: InputDecoration(
        labelText: S.knownLanguages,
        prefixIcon: const Icon(Icons.translate_rounded),
        contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
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

/// Name + occupation + phone for a parent (protected fields, SPEC §9.8).
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.nameController,
    required this.phoneController,
    required this.nameLabel,
    required this.phoneLabel,
    this.occupationController,
    this.occupationLabel,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;

  /// The registration form's "occupation" next to each parent's name.
  final TextEditingController? occupationController;
  final String nameLabel;
  final String phoneLabel;
  final String? occupationLabel;

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
          if (occupationController != null) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: occupationController,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: occupationLabel,
                hintText: 'e.g. Farmer, Retired teacher',
                prefixIcon: const Icon(Icons.work_outline_rounded),
                counterText: '',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              LengthLimitingTextInputFormatter(15),
            ],
            decoration: InputDecoration(
              labelText: phoneLabel,
              prefixIcon: const Icon(Icons.phone_outlined),
            ),
          ),
        ],
      );
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

  final String level;
  final TextEditingController controller;
  final List<MasterItem> countries;
  final int? countryId;
  final ValueChanged<int?> onCountryChanged;

  @override
  Widget build(BuildContext context) {
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
              labelText: EducationLevel.levelLabel(level),
              hintText: S.educationLevelDetailsHint,
              counterText: '',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          // Countries are a long list: the searchable picker (SPEC §9.23 E).
          child: MasterSelectField(
            label: S.country,
            options: masterOptions(countries),
            value: countryId,
            onChanged: onCountryChanged,
          ),
        ),
      ],
    );
  }
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
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          final t = (v ?? '').trim();
          if (t.isEmpty) return null;
          final n = int.tryParse(t);
          return n == null || n < 0 || n > 20 ? '0–20' : null;
        },
      );
}

/// A read-only field that opens a picker (date, time, height). [errorText]
/// shows a validation message under it, like any other field.
class _TapField extends StatelessWidget {
  const _TapField({
    required this.label,
    required this.icon,
    required this.value,
    required this.hint,
    required this.onTap,
    this.errorText,
  });

  final String label;
  final IconData icon;
  final String? value;
  final String hint;
  final VoidCallback onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          errorText: errorText,
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

/// A sub-heading inside a step, with room above it.
class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SectionHeader(title),
      );
}
