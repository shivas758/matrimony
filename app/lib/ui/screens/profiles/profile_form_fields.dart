part of 'profile_form_screen.dart';

// The building blocks of the profile form: the AI import banner and sheet,
// and the field widgets the four steps (profile_form_steps.dart) are made of.

// ==================================================================== AI import

class _AiBanner extends StatelessWidget {
  const _AiBanner({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              busy
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Icon(Icons.auto_fix_high_rounded, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      busy ? S.aiParsing : S.fillFromBiodata,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PDF, photo, or pasted text',
                      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (!busy) const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningList extends StatelessWidget {
  const _WarningList({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text(w, style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet: choose a file or paste text. Returns one of the two.
class _AiImportSheet extends StatefulWidget {
  const _AiImportSheet();

  static Future<({String? path, String? text})?> show(BuildContext context) =>
      showModalBottomSheet<({String? path, String? text})>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => const _AiImportSheet(),
      );

  @override
  State<_AiImportSheet> createState() => _AiImportSheetState();
}

class _AiImportSheetState extends State<_AiImportSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    // file_picker ≥ 12: static call, empty list means the user cancelled.
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'txt'],
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path != null && mounted) Navigator.pop(context, (path: path, text: null));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.fillFromBiodata, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            S.aiImportBody,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text(S.aiPickFile),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: TextStyle(color: theme.colorScheme.outline)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            maxLines: 6,
            minLines: 4,
            decoration: const InputDecoration(hintText: S.aiPasteHint, alignLabelWithHint: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _text.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, (path: null, text: _text.text)),
            child: const Text(S.aiUseText),
          ),
        ],
      ),
    );
  }
}

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
    this.helper,
  });

  final TextEditingController controller;
  final List<Subcaste> options;
  final bool enabled;
  final bool isNew;
  final String? helper;
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
    final helper = widget.helper != null
        ? '${S.aiUnmatchedPrefix}${widget.helper}'
        : widget.isNew
            ? S.subcasteNew
            : null;

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

class _MasterDropdown extends StatelessWidget {
  const _MasterDropdown({
    required this.label,
    required this.icon,
    required this.items,
    required this.value,
    required this.onChanged,
    this.helper,
    this.helperText,
    this.validator,
  });

  final String label;
  final IconData icon;
  final List<MasterItem> items;
  final int? value;
  final ValueChanged<int?> onChanged;

  /// Raw text the AI import could not map — shown so the agent can pick manually.
  final String? helper;

  /// Plain guidance under the field, shown when there is no AI hint.
  final String? helperText;

  /// Set for a required field (the community).
  final FormFieldValidator<int>? validator;

  @override
  Widget build(BuildContext context) {
    // Guard against a stale id that is no longer in the list (deactivated row).
    final safeValue = items.any((i) => i.id == value) ? value : null;
    return DropdownButtonFormField<int>(
      initialValue: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        helperText: helper == null ? helperText : '${S.aiUnmatchedPrefix}$helper',
        helperMaxLines: 2,
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('—')),
        for (final item in items)
          DropdownMenuItem(
            value: item.id,
            child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      validator: validator,
      onChanged: onChanged,
    );
  }
}

/// Multi-select chips for the languages a person knows.
class _LanguageChips extends StatelessWidget {
  const _LanguageChips({
    required this.items,
    required this.selected,
    required this.onToggle,
    this.helper,
  });

  final List<MasterItem> items;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: S.knownLanguages,
        prefixIcon: const Icon(Icons.translate_rounded),
        helperText: helper == null ? null : '${S.aiUnmatchedPrefix}$helper',
        helperMaxLines: 2,
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
    this.phoneHelper,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;

  /// The registration form's "occupation" next to each parent's name.
  final TextEditingController? occupationController;
  final String nameLabel;
  final String phoneLabel;
  final String? occupationLabel;
  final String? phoneHelper;

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
              helperText: phoneHelper == null ? null : '${S.aiUnmatchedPrefix}$phoneHelper',
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
              labelText: EducationLevel.levelLabel(level),
              hintText: S.educationLevelDetailsHint,
              counterText: '',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<int>(
            initialValue: safeValue,
            isExpanded: true,
            decoration: const InputDecoration(labelText: S.country),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              for (final c in countries)
                DropdownMenuItem(
                  value: c.id,
                  child: Text(c.name, overflow: TextOverflow.ellipsis),
                ),
            ],
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
