part of 'profile_form_screen.dart';

/// What each of the four steps shows — exactly the field-to-step mapping of
/// SPEC §9.18 F (mirrored for field errors in [ProfileFormStep.forField]).
/// Fields marked "on request" (§9.8) carry their "visible only after
/// approval" note in whichever step they live.
///
/// An extension rather than more methods on the State, so the long builders
/// sit in their own file; they change state through [_ProfileFormScreenState._set].
extension _ProfileFormSteps on _ProfileFormScreenState {
  /// A hint under a field: the AI import's unmatched text, else [fallback].
  String? _helper(String key, [String? fallback]) {
    final hint = _hint(key);
    return hint == null ? fallback : '${S.aiUnmatchedPrefix}$hint';
  }

  // ================================================================== 1. Personal

  /// Step 1 — name, gender, date of birth, marital status, religion,
  /// community, subcaste, mother tongue, languages known, height, weight,
  /// complexion, food habit, nationality, about, photos. All four required
  /// fields (name, gender, date of birth, community) are here.
  List<Widget> _personalStep(
    BuildContext context,
    MasterData masters,
    List<MasterItem> allowedCommunities,
  ) {
    final theme = Theme.of(context);
    final subcasteOptions = masters.subcastesFor(_communityId);
    final typedSubcaste = _subcaste.text.trim();
    final subcasteIsNew = _subcasteId == null &&
        typedSubcaste.isNotEmpty &&
        !subcasteOptions.any((s) => s.name.toLowerCase() == typedSubcaste.toLowerCase());
    // Steps on which the AI import left something unmatched.
    final toCheck = _lastParse == null
        ? const <ProfileFormStep>[]
        : ProfileFormStep.stepsFor(_lastParse!.unmatched.keys);

    return [
      if (_aiEnabled) ...[
        _AiBanner(busy: _aiBusy, onTap: _fillFromBiodata),
        if (_lastParse != null && _lastParse!.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          _WarningList(warnings: _lastParse!.warnings),
        ],
        if (toCheck.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '${S.aiCheckSteps}${toCheck.map((s) => s.title).join(', ')}.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
        const SizedBox(height: 16),
      ],
      const SectionHeader(S.photos),
      _PhotoStrip(
        existing: _existingPhotos,
        added: _newPhotos,
        onAdd: _pickPhotos,
        onRemoveExisting: _deleteExistingPhoto,
        onRemoveNew: (f) => _set(() => _newPhotos.remove(f)),
        onEditNew: _editNewPhoto,
      ),
      const _Section(S.basicDetails),
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: '${S.fullName} *',
          prefixIcon: Icon(Icons.person_rounded),
        ),
        validator: (v) => (v ?? '').trim().length < 2 ? S.fullNameRequired : null,
      ),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'bride', label: Text(S.bride), icon: Icon(Icons.female_rounded)),
          ButtonSegment(value: 'groom', label: Text(S.groom), icon: Icon(Icons.male_rounded)),
        ],
        selected: {_gender},
        onSelectionChanged: (s) => _set(() => _gender = s.first),
      ),
      const SizedBox(height: 16),
      // Required — a FormField so Next / Save report it like any other field.
      FormField<DateTime>(
        validator: (_) => _dob == null ? S.dobRequired : null,
        builder: (field) => _TapField(
          label: '${S.dob} *',
          icon: Icons.cake_rounded,
          value: _dob == null ? null : formatDate(_dob),
          hint: 'Select date',
          errorText: _dob == null ? field.errorText : null,
          onTap: () async {
            await _pickDob();
            if (field.mounted) field.didChange(_dob);
          },
        ),
      ),
      const SizedBox(height: 16),
      _MasterDropdown(
        label: S.maritalStatus,
        icon: Icons.favorite_border_rounded,
        items: masters.maritalStatuses,
        value: _maritalStatusId,
        helper: _hint('marital_status'),
        onChanged: (v) => _set(() => _maritalStatusId = v),
      ),
      const SizedBox(height: 16),
      _MasterDropdown(
        label: S.religion,
        icon: Icons.temple_hindu_rounded,
        items: masters.religions,
        value: _religionId,
        helper: _hint('religion'),
        onChanged: (v) => _set(() => _religionId = v),
      ),
      const SizedBox(height: 16),
      _MasterDropdown(
        label: '${S.community} *',
        icon: Icons.groups_rounded,
        items: allowedCommunities,
        value: _communityId,
        helper: _hint('community'),
        // Checked against the state, not the menu's own value: the list may
        // still be loading when the community is already known.
        validator: (_) => _communityId == null ? S.communityRequired : null,
        onChanged: (v) => _set(() {
          if (v != _communityId) {
            // A subcaste belongs to one community — reset it on change.
            _subcasteId = null;
            _subcaste.clear();
          }
          _communityId = v;
        }),
      ),
      const SizedBox(height: 16),
      _SubcasteField(
        controller: _subcaste,
        options: subcasteOptions,
        enabled: _communityId != null,
        isNew: subcasteIsNew,
        helper: _hint('subcaste'),
        onSelected: (s) => _set(() {
          _subcasteId = s.id;
          _subcaste.text = s.name;
        }),
        onTyped: (_) => _set(() => _subcasteId = null),
      ),
      const SizedBox(height: 16),
      _MasterDropdown(
        label: S.motherTongue,
        icon: Icons.record_voice_over_outlined,
        items: masters.languages,
        value: _motherTongueId,
        helper: _hint('mother_tongue'),
        onChanged: (v) => _set(() => _motherTongueId = v),
      ),
      const SizedBox(height: 16),
      _LanguageChips(
        items: masters.languages,
        selected: _languageIds,
        helper: _hint('known_languages'),
        onToggle: (id) => _set(() {
          _languageIds.contains(id) ? _languageIds.remove(id) : _languageIds.add(id);
        }),
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: _TapField(
              label: S.height,
              icon: Icons.straighten_rounded,
              value: _heightCm == null ? null : '${Profile.feetInches(_heightCm!)} ($_heightCm cm)',
              hint: 'Select height',
              onTap: _pickHeight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: _weight,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: const InputDecoration(labelText: S.weight, suffixText: 'kg'),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final n = int.tryParse(t);
                return n == null || n < 25 || n > 250 ? '25–250' : null;
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _MasterDropdown(
        label: S.complexion,
        icon: Icons.face_rounded,
        items: masters.complexions,
        value: _complexionId,
        helper: _hint('complexion'),
        onChanged: (v) => _set(() => _complexionId = v),
      ),
      const SizedBox(height: 16),
      _MasterDropdown(
        label: S.foodHabit,
        icon: Icons.restaurant_rounded,
        items: masters.foodHabits,
        value: _foodHabitId,
        helper: _hint('food_habit'),
        onChanged: (v) => _set(() => _foodHabitId = v),
      ),
      const SizedBox(height: 16),
      _MasterDropdown(
        label: S.nationality,
        icon: Icons.flag_outlined,
        items: masters.countries,
        value: _nationalityId,
        helper: _hint('nationality'),
        onChanged: (v) => _set(() => _nationalityId = v),
      ),
      const _Section(S.about),
      TextFormField(
        controller: _about,
        maxLines: 4,
        maxLength: 1000,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'A few lines about the person',
          alignLabelWithHint: true,
        ),
      ),
    ];
  }

  // ============================================================== 2. Professional

  /// Step 2 — the education table (five levels), highest qualification,
  /// other education details, occupation type, profession, profession
  /// details, income, other income, work country, work place*, NRI +
  /// country + place*. (* = on request.)
  List<Widget> _professionalStep(BuildContext context, MasterData masters) {
    final theme = Theme.of(context);
    return [
      // The registration form's education table (SPEC §9.7): five fixed
      // levels, each with free text and the country studied in.
      const SectionHeader(S.educationLevels),
      Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 4),
        child: Text(
          _helper('education_levels', S.educationLevelsHint)!,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ),
      for (final level in EducationLevel.levels) ...[
        _EducationLevelRow(
          level: level,
          controller: _eduLevelDetails[level]!,
          countries: masters.countries,
          countryId: _eduLevelCountry[level],
          onCountryChanged: (v) => _set(() => _eduLevelCountry[level] = v),
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 4),
      _MasterDropdown(
        label: S.highestQualification,
        icon: Icons.school_rounded,
        items: masters.educations,
        value: _educationId,
        helper: _hint('education'),
        onChanged: (v) => _set(() => _educationId = v),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _eduDetails,
        maxLines: 2,
        maxLength: 500,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: S.otherEducationDetails,
          hintText: 'Branch, college, year — e.g. CSE, JNTU Hyderabad, 2018',
          alignLabelWithHint: true,
        ),
      ),
      const _Section(S.profession),
      _MasterDropdown(
        label: S.occupationType,
        icon: Icons.badge_outlined,
        items: masters.occupationTypes,
        value: _occupationTypeId,
        helper: _hint('occupation_type'),
        onChanged: (v) => _set(() => _occupationTypeId = v),
      ),
      const SizedBox(height: 16),
      _MasterDropdown(
        label: S.profession,
        icon: Icons.work_outline_rounded,
        items: masters.professions,
        value: _professionId,
        helper: _hint('profession'),
        onChanged: (v) => _set(() => _professionId = v),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _profDetails,
        maxLines: 2,
        maxLength: 500,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: S.professionDetails,
          hintText: 'Employer, designation — e.g. Senior engineer at TCS',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: _income,
        decoration: const InputDecoration(
          labelText: S.income,
          hintText: 'e.g. 8 LPA',
          prefixIcon: Icon(Icons.currency_rupee_rounded),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _otherIncome,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: S.otherIncome,
          hintText: S.otherIncomeHint,
          prefixIcon: Icon(Icons.savings_outlined),
        ),
      ),
      const _Section(S.location),
      // Public coarse location (SPEC §9.8) — the exact work place below is
      // on request.
      _MasterDropdown(
        label: S.workCountry,
        icon: Icons.public_rounded,
        items: masters.countries,
        value: _workCountryId,
        helper: _hint('work_country'),
        helperText: S.workCountryHint,
        onChanged: (v) => _set(() => _workCountryId = v),
      ),
      const SizedBox(height: 16),
      const LockNote(title: S.onRequestTitle, text: S.onRequestWorkNote),
      const SizedBox(height: 12),
      // Exact work place — protected since v2.1 (the country above is public).
      TextFormField(
        controller: _workPlace,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: S.workPlace,
          hintText: S.workPlaceHint,
          prefixIcon: Icon(Icons.location_city_rounded),
        ),
      ),
      const _Section(S.nri),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('NRI — lives or works abroad'),
        subtitle: _hint('nri_country') == null ? null : Text(_helper('nri_country')!),
        value: _isNri,
        onChanged: (v) => _set(() => _isNri = v ?? false),
      ),
      if (_isNri) ...[
        const SizedBox(height: 8),
        // The country is public; the exact place abroad is on request.
        _MasterDropdown(
          label: S.nriCountry,
          icon: Icons.public_rounded,
          items: masters.countries,
          value: _nriCountryId,
          onChanged: (v) => _set(() => _nriCountryId = v),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _nriPlace,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: S.nriPlace,
            hintText: 'e.g. New Jersey, Dubai, Melbourne',
            prefixIcon: Icon(Icons.flight_takeoff_rounded),
            helperText: S.onRequestTitle,
          ),
        ),
      ],
    ];
  }

  // ================================================================= 3. Horoscope

  /// Step 3 — star (nakshatram), rasi, gothram, birth time, birth place*,
  /// birth state*, birth country*. (* = on request.)
  List<Widget> _horoscopeStep(BuildContext context, MasterData masters) {
    final theme = Theme.of(context);
    return [
      _MasterDropdown(
        label: S.nakshatram,
        icon: Icons.auto_awesome_rounded,
        items: masters.nakshatrams,
        value: _nakshatramId,
        helper: _hint('nakshatram'),
        onChanged: (v) => _set(() => _nakshatramId = v),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        initialValue: masters.zodiacSigns.any((z) => z.id == _zodiacId) ? _zodiacId : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: S.rasi,
          prefixIcon: const Icon(Icons.brightness_5_rounded),
          helperText: _helper('zodiac'),
          helperMaxLines: 2,
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('—')),
          for (final z in masters.zodiacSigns)
            DropdownMenuItem(
              value: z.id,
              child: Text(z.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => _set(() => _zodiacId = v),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _gothram,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: S.gothram,
          hintText: 'e.g. Bharadwaja',
          prefixIcon: Icon(Icons.temple_hindu_rounded),
        ),
      ),
      const SizedBox(height: 16),
      _TapField(
        label: S.birthTime,
        icon: Icons.schedule_rounded,
        value: _birthTime?.format(context),
        hint: 'Select time',
        onTap: _pickBirthTime,
      ),
      if (_birthTime != null || _hint('birth_time') != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Row(
            children: [
              if (_hint('birth_time') != null)
                Expanded(
                  child: Text(
                    _helper('birth_time')!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                )
              else
                const Spacer(),
              if (_birthTime != null)
                TextButton(
                  onPressed: () => _set(() => _birthTime = null),
                  child: const Text('Clear time'),
                ),
            ],
          ),
        ),
      const _Section(S.birthPlace),
      // Birth place / state / country — on request since v2.1 (SPEC §9.8).
      const LockNote(title: S.onRequestTitle, text: S.onRequestBirthNote),
      const SizedBox(height: 12),
      TextFormField(
        controller: _birthPlace,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: S.birthPlace,
          hintText: 'Town / city of birth',
          prefixIcon: const Icon(Icons.location_on_outlined),
          helperText: _helper('birth_place'),
          helperMaxLines: 2,
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _birthState,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: S.birthState,
          prefixIcon: Icon(Icons.map_outlined),
        ),
      ),
      const SizedBox(height: 12),
      _MasterDropdown(
        label: S.birthCountry,
        icon: Icons.flag_outlined,
        items: masters.countries,
        value: _birthCountryId,
        helper: _hint('birth_country'),
        onChanged: (v) => _set(() => _birthCountryId = v),
      ),
    ];
  }

  // ========================================================== 4. Family & contact

  /// Step 4 — father and mother (name, occupation, phone)*, siblings*,
  /// family details*, property share / details*, native place (city,
  /// state)*, contact person (name, phone)* — every field on request — then
  /// the status (edit only) and the Privacy card.
  List<Widget> _familyStep(BuildContext context, MasterData masters) {
    final theme = Theme.of(context);
    return [
      // Everything on this step is PROTECTED ("on request", SPEC §9.8).
      const LockNote(title: S.onRequestTitle, text: S.onRequestFamilyNote),
      const _Section(S.parents),
      _PersonRow(
        nameController: _fatherName,
        phoneController: _fatherPhone,
        occupationController: _fatherOccupation,
        nameLabel: S.fatherName,
        phoneLabel: S.fatherPhone,
        occupationLabel: S.fatherOccupation,
        phoneHelper: _hint('father_phone'),
      ),
      const SizedBox(height: 16),
      _PersonRow(
        nameController: _motherName,
        phoneController: _motherPhone,
        occupationController: _motherOccupation,
        nameLabel: S.motherName,
        phoneLabel: S.motherPhone,
        occupationLabel: S.motherOccupation,
        phoneHelper: _hint('mother_phone'),
      ),
      const _Section(S.siblings),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: -1, label: Text(S.notRecorded)),
          ButtonSegment(value: 0, label: Text(S.no)),
          ButtonSegment(value: 1, label: Text(S.yes)),
        ],
        selected: {_hasSiblings == null ? -1 : (_hasSiblings! ? 1 : 0)},
        onSelectionChanged: (s) => _set(() {
          _hasSiblings = switch (s.first) { 1 => true, 0 => false, _ => null };
        }),
      ),
      if (_hasSiblings == true) ...[
        const SizedBox(height: 16),
        // The registration form's breakdown; the total below may be left
        // blank, in which case it is the sum of these four.
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(S.siblingsBreakdown, style: theme.textTheme.labelLarge),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _CountField(label: S.elderSisters, controller: _elderSisters)),
            const SizedBox(width: 12),
            Expanded(child: _CountField(label: S.youngerSisters, controller: _youngerSisters)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _CountField(label: S.elderBrothers, controller: _elderBrothers)),
            const SizedBox(width: 12),
            Expanded(child: _CountField(label: S.youngerBrothers, controller: _youngerBrothers)),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _siblingsCount,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          decoration: const InputDecoration(
            labelText: S.siblingsCount,
            prefixIcon: Icon(Icons.family_restroom_rounded),
          ),
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty) return null;
            final n = int.tryParse(t);
            return n == null || n < 1 || n > 20 ? '1–20' : null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _siblingsDetails,
          maxLines: 3,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: S.siblingsDetails,
            hintText: 'e.g. One elder brother, married, works in Bengaluru',
            helperText: S.siblingsDetailsHint,
            helperMaxLines: 3,
            alignLabelWithHint: true,
          ),
        ),
      ],
      const _Section(S.familyDetails),
      TextFormField(
        controller: _family,
        maxLines: 4,
        maxLength: 1000,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Parents, family background',
          alignLabelWithHint: true,
        ),
      ),
      const _Section(S.property),
      TextFormField(
        controller: _propertyShare,
        maxLength: 500,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: S.propertyShare,
          hintText: S.propertyShareHint,
          prefixIcon: Icon(Icons.pie_chart_outline_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _propertyDetails,
        maxLines: 3,
        maxLength: 1000,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: S.propertyDetails,
          hintText: S.propertyDetailsHint,
          alignLabelWithHint: true,
        ),
      ),
      const _Section(S.nativePlace),
      TextFormField(
        controller: _city,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: S.city,
          prefixIcon: Icon(Icons.home_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _state,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: S.nativeState,
          prefixIcon: Icon(Icons.map_outlined),
        ),
      ),
      const _Section(S.contactPerson),
      TextFormField(
        controller: _contactName,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: S.contactPersonName,
          prefixIcon: Icon(Icons.contact_page_outlined),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _contactPhone,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
          LengthLimitingTextInputFormatter(15),
        ],
        decoration: InputDecoration(
          labelText: S.contactPersonPhone,
          prefixIcon: const Icon(Icons.phone_rounded),
          helperText: _helper('contact_phone'),
        ),
      ),
      if (widget.isEdit) ...[
        const _Section(S.profileStatus),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final s in ProfileStatus.values)
              ChoiceChip(
                label: Text(s.label),
                selected: _status == s.apiValue,
                onSelected: (_) => _set(() => _status = s.apiValue),
              ),
          ],
        ),
      ],
      // The Privacy card (SPEC §9.18 D / E). The list of switchable details
      // comes from the server; an older one sends none and the card is left out.
      if (masters.privacyFields.isNotEmpty) ...[
        const SizedBox(height: 24),
        PrivacyCard(
          fields: masters.privacyFields,
          alwaysVisible: masters.privacyAlwaysVisible,
          privacy: _privacy,
          communities: masters.communities,
          ownCommunityId: _communityId,
          enabled: !_busy,
          onChanged: (next) => _set(() => _privacy = next),
        ),
      ],
    ];
  }
}
