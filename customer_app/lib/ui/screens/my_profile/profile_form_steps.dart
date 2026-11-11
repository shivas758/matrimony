part of 'profile_form_screen.dart';

// The four steps of the registration form, field for field as SPEC §9.18 F
// lists them. Each is a plain column of fields: the values and controllers
// belong to [_ProfileFormScreenState] (`form`), which rebuilds the steps and
// keeps all four alive, so nothing typed on one step is lost on another.
//
// Fields marked "on request" (SPEC §9.8) say so — other families see them
// only after approval.

const _gap = SizedBox(height: 12);
const _sectionGap = SizedBox(height: 20);

// ============================================================ 1 Personal details

/// Name*, gender*, date of birth*, marital status · religion, community*,
/// subcaste, mother tongue, languages known · height, weight, complexion,
/// food habit, nationality · about · photos.   (* = required)
class _PersonalStep extends StatelessWidget {
  const _PersonalStep({required this.form, required this.masters, required this.agentCommunities});

  final _ProfileFormScreenState form;
  final MasterData masters;

  /// My agent's communities — that is where my profile is first seen.
  final List<MasterItem> agentCommunities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = form;

    final mine = masters.communities.where((c) => agentCommunities.any((m) => m.id == c.id)).toList();
    final communityOptions = mine.isEmpty ? masters.communities : mine;

    final subcasteOptions = masters.subcastesFor(f._communityId);
    final typedSubcaste = f._subcaste.text.trim();
    final subcasteIsNew = typedSubcaste.isNotEmpty &&
        !subcasteOptions.any((s) => s.name.toLowerCase() == typedSubcaste.toLowerCase());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------------------------------------------------------- basic
        const SectionHeader(S.basicDetails),
        KeyedSubtree(
          key: f._nameAnchor,
          child: TextFormField(
            controller: f._name,
            textCapitalization: TextCapitalization.words,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
              labelText: _required(S.fullName),
              prefixIcon: const Icon(Icons.person_rounded),
            ),
            validator: _ProfileFormScreenState._nameError,
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'bride', label: Text(S.bride), icon: Icon(Icons.female_rounded)),
            ButtonSegment(value: 'groom', label: Text(S.groom), icon: Icon(Icons.male_rounded)),
          ],
          selected: {f._gender},
          onSelectionChanged: (s) => f._update(() => f._gender = s.first),
        ),
        const SizedBox(height: 16),
        KeyedSubtree(
          key: f._dobAnchor,
          child: FormField<DateTime>(
            key: f._dobField,
            validator: (_) => f._dob == null ? S.dobRequired : null,
            builder: (field) => _TapField(
              label: _required(S.dob),
              icon: Icons.cake_rounded,
              value: f._dob == null ? null : formatDate(f._dob),
              hint: S.selectDate,
              onTap: f._pickDob,
              errorText: field.errorText,
            ),
          ),
        ),
        const SizedBox(height: 16),
        _MasterDropdown(
          label: S.maritalStatus,
          icon: Icons.favorite_border_rounded,
          items: masters.maritalStatuses,
          value: f._maritalStatusId,
          onChanged: (v) => f._update(() => f._maritalStatusId = v),
        ),
        // ---------------------------------------------------------- community & language
        _sectionGap,
        const SectionHeader(S.communitySection),
        _MasterDropdown(
          label: S.religion,
          icon: Icons.temple_hindu_rounded,
          items: masters.religions,
          value: f._religionId,
          onChanged: (v) => f._update(() => f._religionId = v),
        ),
        _gap,
        KeyedSubtree(
          key: f._communityAnchor,
          child: _MasterDropdown(
            label: S.community,
            icon: Icons.groups_rounded,
            items: communityOptions,
            value: f._communityId,
            requiredMessage: S.communityRequired,
            onChanged: (v) => f._update(() {
              // A subcaste belongs to one community — reset it on change.
              if (v != f._communityId) f._subcaste.clear();
              f._communityId = v;
            }),
          ),
        ),
        _gap,
        _SubcasteField(
          controller: f._subcaste,
          options: subcasteOptions,
          enabled: f._communityId != null,
          isNew: subcasteIsNew,
          onChanged: () => f._update(() {}),
        ),
        _gap,
        _MasterDropdown(
          label: S.motherTongue,
          icon: Icons.record_voice_over_outlined,
          items: masters.languages,
          value: f._motherTongueId,
          onChanged: (v) => f._update(() => f._motherTongueId = v),
        ),
        _gap,
        _LanguageChips(
          items: masters.languages,
          selected: f._languageIds,
          onToggle: (id) => f._update(() {
            f._languageIds.contains(id) ? f._languageIds.remove(id) : f._languageIds.add(id);
          }),
        ),
        // ---------------------------------------------------------- appearance & lifestyle
        _sectionGap,
        const SectionHeader(S.appearance),
        KeyedSubtree(
          key: f._weightAnchor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _TapField(
                  label: S.height,
                  icon: Icons.straighten_rounded,
                  value: f._heightCm == null ? null : '${Profile.feetInches(f._heightCm!)} (${f._heightCm} cm)',
                  hint: S.selectHeight,
                  onTap: f._pickHeight,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: f._weight,
                  keyboardType: TextInputType.number,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(labelText: S.weight, suffixText: 'kg'),
                  validator: _ProfileFormScreenState._weightError,
                ),
              ),
            ],
          ),
        ),
        _gap,
        _MasterDropdown(
          label: S.complexion,
          icon: Icons.face_rounded,
          items: masters.complexions,
          value: f._complexionId,
          onChanged: (v) => f._update(() => f._complexionId = v),
        ),
        _gap,
        _MasterDropdown(
          label: S.foodHabit,
          icon: Icons.restaurant_rounded,
          items: masters.foodHabits,
          value: f._foodHabitId,
          onChanged: (v) => f._update(() => f._foodHabitId = v),
        ),
        _gap,
        _MasterDropdown(
          label: S.nationality,
          icon: Icons.flag_outlined,
          items: masters.countries,
          value: f._nationalityId,
          onChanged: (v) => f._update(() => f._nationalityId = v),
        ),
        // ---------------------------------------------------------- about
        _sectionGap,
        const SectionHeader(S.about),
        TextFormField(
          controller: f._about,
          maxLines: 4,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: S.aboutHint, alignLabelWithHint: true),
        ),
        // ---------------------------------------------------------- photos
        const SizedBox(height: 8),
        SectionHeader(
          S.photos,
          trailing: Text(
            '${f._photoCount} / ${AppConfig.maxPhotos}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        _PhotoStrip(
          existing: f._existingPhotos,
          added: f._newPhotos,
          onAdd: f._pickPhotos,
          onRemoveExisting: f._deleteExistingPhoto,
          onRemoveNew: (file) => f._update(() => f._newPhotos.remove(file)),
          onEditNew: f._editNewPhoto,
        ),
      ],
    );
  }
}

// ============================================================ 2 Professional details

/// The education table (five levels), highest qualification, other education
/// details · occupation type, profession, profession details, income, other
/// income, work country, work place (on request), NRI + country + place (on
/// request).
class _ProfessionalStep extends StatelessWidget {
  const _ProfessionalStep({required this.form, required this.masters});

  final _ProfileFormScreenState form;
  final MasterData masters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---------------------------------------------------------- education
        const SectionHeader(S.educationSection),
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            S.educationLevelsHint,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        for (final level in EducationLevel.values) ...[
          _EducationLevelRow(
            level: level,
            controller: f._eduLevelDetails[level]!,
            countries: masters.countries,
            countryId: f._eduLevelCountry[level],
            onCountryChanged: (v) => f._update(() => f._eduLevelCountry[level] = v),
          ),
          _gap,
        ],
        _MasterDropdown(
          label: S.highestQualification,
          icon: Icons.school_rounded,
          items: masters.educations,
          value: f._educationId,
          onChanged: (v) => f._update(() => f._educationId = v),
        ),
        _gap,
        TextFormField(
          controller: f._eduDetails,
          maxLines: 2,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: S.otherEducation,
            alignLabelWithHint: true,
          ),
        ),
        // ---------------------------------------------------------- work & income
        const SizedBox(height: 8),
        const SectionHeader(S.professional),
        _MasterDropdown(
          label: S.occupationType,
          icon: Icons.badge_outlined,
          items: masters.occupationTypes,
          value: f._occupationTypeId,
          onChanged: (v) => f._update(() => f._occupationTypeId = v),
        ),
        _gap,
        _MasterDropdown(
          label: S.occupation,
          icon: Icons.work_outline_rounded,
          items: masters.professions,
          value: f._professionId,
          onChanged: (v) => f._update(() => f._professionId = v),
        ),
        _gap,
        TextFormField(
          controller: f._profDetails,
          maxLines: 2,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: S.otherProfessional,
            hintText: S.otherProfessionalHint,
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: f._income,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: S.salary,
            hintText: S.salaryHint,
            prefixIcon: Icon(Icons.currency_rupee_rounded),
            counterText: '',
          ),
        ),
        _gap,
        TextFormField(
          controller: f._otherIncome,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: S.otherIncome,
            hintText: S.otherIncomeHint,
            prefixIcon: Icon(Icons.savings_outlined),
            counterText: '',
          ),
        ),
        _gap,
        _MasterDropdown(
          label: S.workCountry,
          icon: Icons.public_rounded,
          items: masters.countries,
          value: f._workCountryId,
          onChanged: (v) => f._update(() => f._workCountryId = v),
        ),
        _gap,
        TextFormField(
          controller: f._workPlace,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: S.workPlace,
            hintText: S.workPlaceHint,
            prefixIcon: Icon(Icons.location_city_rounded),
            // On request (SPEC §9.8) — the country above is the public part.
            helperText: S.afterApprovalOnly,
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(S.nriSwitch),
          secondary: const Icon(Icons.flight_takeoff_rounded, color: AppColors.wineLight),
          value: f._isNri,
          onChanged: (v) => f._update(() => f._isNri = v),
        ),
        if (f._isNri) ...[
          const SizedBox(height: 8),
          _MasterDropdown(
            label: S.nriCountry,
            icon: Icons.public_rounded,
            items: masters.countries,
            value: f._nriCountryId,
            onChanged: (v) => f._update(() => f._nriCountryId = v),
          ),
          _gap,
          TextFormField(
            controller: f._nriPlace,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: S.nriPlace,
              hintText: S.nriPlaceHint,
              prefixIcon: Icon(Icons.flight_takeoff_rounded),
              helperText: S.afterApprovalOnly,
              helperMaxLines: 2,
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================ 3 Horoscope

/// Star (nakshatram), rasi, gothram, birth time · birth place, birth state,
/// birth country (on request).
class _HoroscopeStep extends StatelessWidget {
  const _HoroscopeStep({required this.form, required this.masters});

  final _ProfileFormScreenState form;
  final MasterData masters;

  @override
  Widget build(BuildContext context) {
    final f = form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(S.starSection),
        _MasterDropdown(
          label: S.nakshatram,
          icon: Icons.auto_awesome_rounded,
          items: masters.nakshatrams,
          value: f._nakshatramId,
          onChanged: (v) => f._update(() => f._nakshatramId = v),
        ),
        _gap,
        _MasterDropdown(
          label: S.rasi,
          icon: Icons.brightness_5_rounded,
          items: [for (final z in masters.zodiacSigns) MasterItem(id: z.id, name: z.label)],
          value: f._zodiacId,
          onChanged: (v) => f._update(() => f._zodiacId = v),
        ),
        _gap,
        TextFormField(
          controller: f._gothram,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: S.gothram,
            hintText: S.gothramHint,
            prefixIcon: Icon(Icons.temple_hindu_rounded),
          ),
        ),
        _gap,
        _TapField(
          label: S.birthTime,
          icon: Icons.schedule_rounded,
          value: f._birthTime?.format(context),
          hint: S.selectTime,
          onTap: f._pickBirthTime,
          onClear: f._birthTime == null ? null : () => f._update(() => f._birthTime = null),
        ),
        // ---------------------------------------------------------- birth place (on request)
        _sectionGap,
        const SectionHeader(S.birthDetails),
        const LockNote(text: S.birthPlaceNote),
        const SizedBox(height: 16),
        TextFormField(
          controller: f._birthPlace,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: S.birthPlace,
            prefixIcon: Icon(Icons.location_on_outlined),
          ),
        ),
        _gap,
        TextFormField(
          controller: f._birthState,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: S.birthState,
            prefixIcon: Icon(Icons.map_outlined),
          ),
        ),
        _gap,
        _MasterDropdown(
          label: S.birthCountry,
          icon: Icons.flag_outlined,
          items: masters.countries,
          value: f._birthCountryId,
          onChanged: (v) => f._update(() => f._birthCountryId = v),
        ),
      ],
    );
  }
}

// ============================================================ 4 Family & contact

/// Father and mother (name, occupation, phone) · siblings · family details ·
/// property share / details · native place (city, state) · contact person
/// (name, phone). Everything here is on request (SPEC §9.8).
class _FamilyStep extends StatelessWidget {
  const _FamilyStep({required this.form});

  final _ProfileFormScreenState form;

  @override
  Widget build(BuildContext context) {
    final f = form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LockNote(text: S.onRequestNote),
        const SizedBox(height: 8),
        // ---------------------------------------------------------- parents
        const SectionHeader(S.parents),
        _PersonBlock(
          nameController: f._fatherName,
          occupationController: f._fatherOccupation,
          phoneController: f._fatherPhone,
          nameLabel: S.fatherName,
          occupationLabel: S.fatherOccupation,
          phoneLabel: S.fatherPhone,
        ),
        const SizedBox(height: 20),
        _PersonBlock(
          nameController: f._motherName,
          occupationController: f._motherOccupation,
          phoneController: f._motherPhone,
          nameLabel: S.motherName,
          occupationLabel: S.motherOccupation,
          phoneLabel: S.motherPhone,
        ),
        // ---------------------------------------------------------- siblings
        _sectionGap,
        const SectionHeader(S.hasSiblings),
        KeyedSubtree(
          key: f._siblingsAnchor,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: -1, label: Text(S.notRecorded)),
              ButtonSegment(value: 0, label: Text(S.no)),
              ButtonSegment(value: 1, label: Text(S.yes)),
            ],
            selected: {f._hasSiblings == null ? -1 : (f._hasSiblings! ? 1 : 0)},
            onSelectionChanged: (s) => f._update(() {
              f._hasSiblings = switch (s.first) { 1 => true, 0 => false, _ => null };
            }),
          ),
        ),
        if (f._hasSiblings == true) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _CountField(label: S.elderSisters, controller: f._elderSisters)),
              const SizedBox(width: 12),
              Expanded(child: _CountField(label: S.youngerSisters, controller: f._youngerSisters)),
            ],
          ),
          _gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _CountField(label: S.elderBrothers, controller: f._elderBrothers)),
              const SizedBox(width: 12),
              Expanded(child: _CountField(label: S.youngerBrothers, controller: f._youngerBrothers)),
            ],
          ),
          _gap,
          TextFormField(
            controller: f._siblingsDetails,
            maxLines: 3,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: S.siblingsDetails,
              alignLabelWithHint: true,
            ),
          ),
        ],
        // ---------------------------------------------------------- family
        _sectionGap,
        const SectionHeader(S.family),
        TextFormField(
          controller: f._family,
          maxLines: 3,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: S.familyDetails,
            hintText: S.familyDetailsHint,
            alignLabelWithHint: true,
          ),
        ),
        // ---------------------------------------------------------- property
        const SizedBox(height: 8),
        const SectionHeader(S.property),
        TextFormField(
          controller: f._propertyShare,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: S.propertyShare,
            hintText: S.propertyShareHint,
            prefixIcon: Icon(Icons.pie_chart_outline_rounded),
            counterText: '',
          ),
        ),
        _gap,
        TextFormField(
          controller: f._propertyDetails,
          maxLines: 3,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: S.propertyDetails,
            hintText: S.propertyDetailsHint,
            alignLabelWithHint: true,
          ),
        ),
        // ---------------------------------------------------------- native place
        const SizedBox(height: 8),
        const SectionHeader(S.nativePlaceSection),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: f._city,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: S.city,
                  prefixIcon: Icon(Icons.home_rounded),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: f._state,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: S.nativeState),
              ),
            ),
          ],
        ),
        // ---------------------------------------------------------- contact person
        _sectionGap,
        const SectionHeader(S.contactPerson),
        TextFormField(
          controller: f._contactName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: S.contactPersonName,
            prefixIcon: Icon(Icons.contact_page_outlined),
          ),
        ),
        _gap,
        _PhoneField(controller: f._contactPhone, label: S.contactPersonPhone),
      ],
    );
  }
}
