import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../config.dart';
import '../../../models/master_data.dart';
import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/photo_picker.dart';

/// The registration form in the paper's order (SPEC §9.11 Gandharva 5):
/// Basic → Birth → Community → Appearance → Education table → Work & income →
/// Family → Property → About → Photos. Creates one of my (up to 5) profiles
/// with POST /customer/my-profiles (multipart) or edits a specific one with
/// PATCH /customer/my-profiles/:id + the photo routes (SPEC §9.12). Needs a
/// linked agent. Pops the saved [Profile].
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, this.existing, this.prefillName = false});

  /// Edit this one of my profiles (PATCH /customer/my-profiles/:id); null
  /// creates a new one (POST /customer/my-profiles).
  final Profile? existing;

  /// A new profile starts with the account holder's name — only sensible for
  /// the first one (later ones are usually for a son or daughter).
  final bool prefillName;

  bool get isEdit => existing != null;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _birthPlace;
  late final TextEditingController _birthState;
  late final TextEditingController _subcaste;
  late final TextEditingController _gothram;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _weight;
  late final TextEditingController _eduDetails;
  late final TextEditingController _profDetails;
  late final TextEditingController _income;
  late final TextEditingController _otherIncome;
  late final TextEditingController _workPlace;
  late final TextEditingController _nriPlace;
  late final TextEditingController _fatherName;
  late final TextEditingController _fatherOccupation;
  late final TextEditingController _fatherPhone;
  late final TextEditingController _motherName;
  late final TextEditingController _motherOccupation;
  late final TextEditingController _motherPhone;
  late final TextEditingController _contactName;
  late final TextEditingController _contactPhone;
  late final TextEditingController _elderSisters;
  late final TextEditingController _youngerSisters;
  late final TextEditingController _elderBrothers;
  late final TextEditingController _youngerBrothers;
  late final TextEditingController _siblingsDetails;
  late final TextEditingController _family;
  late final TextEditingController _propertyShare;
  late final TextEditingController _propertyDetails;
  late final TextEditingController _about;

  /// The education table: free text and a country per level, in the paper's
  /// order. Rows left empty are not sent.
  final Map<EducationLevel, TextEditingController> _eduLevelDetails = {
    for (final level in EducationLevel.values) level: TextEditingController(),
  };
  final Map<EducationLevel, int?> _eduLevelCountry = {
    for (final level in EducationLevel.values) level: null,
  };

  String _gender = 'bride';
  int? _maritalStatusId;
  DateTime? _dob;
  TimeOfDay? _birthTime;
  int? _birthCountryId;
  int? _nakshatramId;
  int? _zodiacId;
  int? _nationalityId;
  int? _religionId;
  int? _communityId;
  int? _complexionId;
  int? _motherTongueId;
  final Set<int> _languageIds = {};
  int? _foodHabitId;
  int? _heightCm;
  int? _educationId;
  int? _occupationTypeId;
  int? _professionId;
  int? _workCountryId;
  bool _isNri = false;
  int? _nriCountryId;

  /// null = not recorded, false = none, true = counts + details below.
  bool? _hasSiblings;

  final List<XFile> _newPhotos = [];
  late List<ProfilePhoto> _existingPhotos;

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    // The first new profile starts with the account's name.
    final accountName = widget.prefillName ? context.read<AuthState>().customer?.fullName ?? '' : '';
    _name = TextEditingController(text: p?.fullName ?? accountName);
    _birthPlace = TextEditingController(text: p?.birthPlace ?? '');
    _birthState = TextEditingController(text: p?.birthState ?? '');
    _subcaste = TextEditingController(text: p?.subcaste?.name ?? '');
    _gothram = TextEditingController(text: p?.gothram ?? '');
    _city = TextEditingController(text: p?.city ?? '');
    _state = TextEditingController(text: p?.state ?? '');
    _weight = TextEditingController(text: p?.weightKg?.toString() ?? '');
    _eduDetails = TextEditingController(text: p?.educationDetails ?? '');
    _profDetails = TextEditingController(text: p?.professionDetails ?? '');
    _income = TextEditingController(text: p?.incomeText ?? '');
    _otherIncome = TextEditingController(text: p?.otherIncome ?? '');
    _workPlace = TextEditingController(text: p?.workPlace ?? '');
    _nriPlace = TextEditingController(text: p?.nriPlace ?? '');
    _fatherName = TextEditingController(text: p?.fatherName ?? '');
    _fatherOccupation = TextEditingController(text: p?.fatherOccupation ?? '');
    _fatherPhone = TextEditingController(text: p?.fatherPhone ?? '');
    _motherName = TextEditingController(text: p?.motherName ?? '');
    _motherOccupation = TextEditingController(text: p?.motherOccupation ?? '');
    _motherPhone = TextEditingController(text: p?.motherPhone ?? '');
    _contactName = TextEditingController(text: p?.contactName ?? '');
    _contactPhone = TextEditingController(text: p?.contactPhone ?? '');
    _elderSisters = TextEditingController(text: _countText(p?.elderSisters));
    _youngerSisters = TextEditingController(text: _countText(p?.youngerSisters));
    _elderBrothers = TextEditingController(text: _countText(p?.elderBrothers));
    _youngerBrothers = TextEditingController(text: _countText(p?.youngerBrothers));
    _siblingsDetails = TextEditingController(text: p?.siblingsDetails ?? '');
    _family = TextEditingController(text: p?.familyDetails ?? '');
    _propertyShare = TextEditingController(text: p?.propertyShare ?? '');
    _propertyDetails = TextEditingController(text: p?.propertyDetails ?? '');
    _about = TextEditingController(text: p?.about ?? '');
    for (final row in p?.educationLevels ?? const <EducationLevelEntry>[]) {
      _eduLevelDetails[row.level]?.text = row.details ?? '';
      _eduLevelCountry[row.level] = row.country?.id;
    }
    _existingPhotos = [...?p?.photos];

    if (p != null) {
      _gender = p.gender;
      _maritalStatusId = p.maritalStatus?.id;
      _dob = p.dob;
      _birthTime = _parseTime(p.birthTime);
      _birthCountryId = p.birthCountry?.id;
      _nakshatramId = p.nakshatram?.id;
      _zodiacId = p.zodiac?.id;
      _nationalityId = p.nationality?.id;
      _religionId = p.religion?.id;
      _communityId = p.community?.id;
      _complexionId = p.complexion?.id;
      _motherTongueId = p.motherTongue?.id;
      _languageIds.addAll(p.knownLanguages.map((l) => l.id));
      _foodHabitId = p.foodHabit?.id;
      _heightCm = p.heightCm;
      _educationId = p.education?.id;
      _occupationTypeId = p.occupationType?.id;
      _professionId = p.profession?.id;
      _workCountryId = p.workCountry?.id;
      _isNri = p.isNri;
      _nriCountryId = p.nriCountry?.id;
      _hasSiblings = p.hasSiblings;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mastersState = context.read<MastersState>();
      mastersState.load().then((_) {
        if (!mounted || widget.isEdit) return;
        // A new profile is Indian, born and working in India unless said
        // otherwise (SPEC §9.7: countries start with India).
        final india = _indiaId(mastersState.data);
        if (india == null) return;
        setState(() {
          _nationalityId ??= india;
          _birthCountryId ??= india;
          _workCountryId ??= india;
        });
      });
      // One-community agents: skip a step.
      final agent = context.read<AuthState>().agent;
      if (_communityId == null && (agent?.communities.length ?? 0) == 1) {
        setState(() => _communityId = agent!.communities.first.id);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name, _birthPlace, _birthState, _subcaste, _gothram, _city, _state, _weight, _eduDetails,
      _profDetails, _income, _otherIncome, _workPlace, _nriPlace, _fatherName, _fatherOccupation,
      _fatherPhone, _motherName, _motherOccupation, _motherPhone, _contactName, _contactPhone,
      _elderSisters, _youngerSisters, _elderBrothers, _youngerBrothers, _siblingsDetails, _family,
      _propertyShare, _propertyDetails, _about, ..._eduLevelDetails.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static int? _indiaId(MasterData masters) {
    for (final c in masters.countries) {
      if (c.name.trim().toLowerCase() == 'india') return c.id;
    }
    return null;
  }

  /// A count field shows nothing for null; "0" is a real answer.
  static String _countText(int? n) => n == null ? '' : '$n';

  static int? _countOf(TextEditingController c) => int.tryParse(c.text.trim());

  static String _text(TextEditingController c) => c.text.trim();

  static String _fmtDob(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---- birth time: the API speaks "HH:MM" (24h); the picker speaks TimeOfDay.

  static TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return null;
    final parts = hhmm.split(':');
    final h = parts.length >= 2 ? int.tryParse(parts[0]) : null;
    final m = parts.length >= 2 ? int.tryParse(parts[1]) : null;
    if (h == null || m == null || h > 23 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// The education rows that were filled in — `{level, details, country_id}`.
  List<Map<String, dynamic>> _educationLevelRows() => [
        for (final level in EducationLevel.values)
          if (_text(_eduLevelDetails[level]!).isNotEmpty || _eduLevelCountry[level] != null)
            {
              'level': level.apiValue,
              'details': _text(_eduLevelDetails[level]!).isEmpty ? null : _text(_eduLevelDetails[level]!),
              'country_id': _eduLevelCountry[level],
            },
      ];

  // ------------------------------------------------------------------ pickers

  int get _photoCount => _existingPhotos.length + _newPhotos.length;

  Future<void> _pickPhotos() async {
    final remaining = AppConfig.maxPhotos - _photoCount;
    if (remaining <= 0) {
      showSnack(context, S.maxPhotos(AppConfig.maxPhotos), error: true);
      return;
    }
    // Camera or gallery, then the crop / rotate editor (SPEC §9.17).
    final picked = await PhotoPicker.pick(context, remaining: remaining);
    if (picked.isEmpty || !mounted) return;
    setState(() => _newPhotos.addAll(picked.take(remaining)));
  }

  /// Re-opens the editor on a photo that is not uploaded yet.
  Future<void> _editNewPhoto(XFile file) async {
    final edited = await PhotoPicker.edit(context, file);
    if (edited == null || !mounted) return;
    setState(() {
      final i = _newPhotos.indexOf(file);
      if (i >= 0) _newPhotos[i] = edited;
    });
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dob ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: S.dob,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickBirthTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _birthTime ?? const TimeOfDay(hour: 6, minute: 0),
      helpText: S.birthTime,
    );
    if (picked != null) setState(() => _birthTime = picked);
  }

  /// Feet + inches on screen (that is how families quote height); cm on the wire.
  Future<void> _pickHeight() async {
    final selected = await _HeightPickerDialog.show(context, initialCm: _heightCm);
    if (selected != null) setState(() => _heightCm = selected);
  }

  // ------------------------------------------------------------------ save

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _error = S.errValidation);
      return;
    }
    if (_dob == null) {
      setState(() => _error = S.dobRequired);
      return;
    }
    if (_communityId == null) {
      setState(() => _error = S.communityRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final isEdit = widget.isEdit;
    // Siblings: the counts travel only with "Yes"; the total is their sum.
    final hasSiblings = _hasSiblings == true;
    final counts = [
      _countOf(_elderSisters),
      _countOf(_youngerSisters),
      _countOf(_elderBrothers),
      _countOf(_youngerBrothers),
    ];
    final sum = counts.whereType<int>().fold<int>(0, (a, b) => a + b);
    final siblingsCount = hasSiblings && counts.any((n) => n != null) ? sum : null;

    final fields = <String, dynamic>{
      // ---- Basic
      'full_name': _text(_name),
      'gender': _gender,
      'marital_status_id': _maritalStatusId,
      'dob': _fmtDob(_dob!),
      // "HH:MM" 24h; an empty string clears the time on edit.
      'birth_time': _birthTime == null ? '' : _fmtTime(_birthTime!),
      // ---- Birth (place / state / country are on request; star & rasi public)
      'birth_place': _text(_birthPlace),
      'birth_state': _text(_birthState),
      'birth_country_id': _birthCountryId,
      'nakshatram_id': _nakshatramId,
      'zodiac_id': _zodiacId,
      // ---- Community
      'nationality_id': _nationalityId,
      'religion_id': _religionId,
      'community_id': _communityId,
      // Free text: the server finds it in the community or creates it (SPEC §2).
      'subcaste_name': _text(_subcaste),
      'gothram': _text(_gothram),
      'city': _text(_city),
      'state': _text(_state),
      // ---- Appearance & lifestyle
      'complexion_id': _complexionId,
      'mother_tongue_id': _motherTongueId,
      // Multipart takes a comma list; JSON takes an array so [] clears it.
      'known_language_ids': isEdit ? _languageIds.toList() : _languageIds.join(','),
      'food_habit_id': _foodHabitId,
      'height_cm': _heightCm,
      'weight_kg': int.tryParse(_text(_weight)),
      // ---- Education
      'education_levels': _educationLevelRows(),
      'education_details': _text(_eduDetails),
      'education_id': _educationId,
      // ---- Work & income
      'occupation_type_id': _occupationTypeId,
      'profession_id': _professionId,
      'income_text': _text(_income),
      'other_income': _text(_otherIncome),
      'work_place': _text(_workPlace),
      'work_country_id': _workCountryId,
      'profession_details': _text(_profDetails),
      'is_nri': _isNri,
      'nri_country_id': _isNri ? _nriCountryId : null,
      'nri_place': _isNri ? _text(_nriPlace) : null,
      // ---- Family (on request)
      'father_name': _text(_fatherName),
      'father_occupation': _text(_fatherOccupation),
      'father_phone': _text(_fatherPhone),
      'mother_name': _text(_motherName),
      'mother_occupation': _text(_motherOccupation),
      'mother_phone': _text(_motherPhone),
      'contact_name': _text(_contactName),
      'contact_phone': _text(_contactPhone),
      // Tri-state: multipart drops '' (= not recorded); JSON null clears it.
      'has_siblings': isEdit ? _hasSiblings : (_hasSiblings?.toString() ?? ''),
      'siblings_count': siblingsCount,
      'elder_sisters': hasSiblings ? counts[0] : null,
      'younger_sisters': hasSiblings ? counts[1] : null,
      'elder_brothers': hasSiblings ? counts[2] : null,
      'younger_brothers': hasSiblings ? counts[3] : null,
      'siblings_details': hasSiblings ? _text(_siblingsDetails) : null,
      'family_details': _text(_family),
      // ---- Property (on request)
      'property_share': _text(_propertyShare),
      'property_details': _text(_propertyDetails),
      // ---- About
      'about': _text(_about),
    };

    try {
      final service = context.read<ProfileService>();
      final paths = _newPhotos.map((f) => f.path).toList();
      Profile saved;
      if (isEdit) {
        final id = widget.existing!.id;
        saved = await service.updateProfile(id, fields);
        if (paths.isNotEmpty) {
          await service.addPhotos(id, paths);
          saved = await service.myProfile(id);
        }
      } else {
        saved = await service.createProfile(fields, paths);
      }
      if (!mounted) return;
      // A newly typed subcaste is now in the master list — refresh the cache.
      context.read<MastersState>().load(force: true);
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteExistingPhoto(ProfilePhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.removePhoto),
        content: const Text(S.removePhotoBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.remove)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ProfileService>().deletePhoto(photo.id);
      setState(() => _existingPhotos.removeWhere((p) => p.id == photo.id));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final masters = context.watch<MastersState>().data;
    final agent = context.watch<AuthState>().agent;
    final theme = Theme.of(context);

    // My agent's communities first — that is where my profile will be seen.
    final communities = (agent?.communities ?? const []).isNotEmpty
        ? masters.communities.where((c) => agent!.communities.any((m) => m.id == c.id)).toList()
        : masters.communities;
    final communityOptions = communities.isEmpty ? masters.communities : communities;

    final subcasteOptions = masters.subcastesFor(_communityId);
    final typedSubcaste = _text(_subcaste);
    final subcasteIsNew = typedSubcaste.isNotEmpty &&
        !subcasteOptions.any((s) => s.name.toLowerCase() == typedSubcaste.toLowerCase());

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? S.editProfileTitle : S.newProfileTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              // ============================================================ Basic
              const SectionHeader(S.basicDetails),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: S.fullName,
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                validator: (v) => (v ?? '').trim().length < 2 ? S.nameRequired : null,
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'bride', label: Text(S.bride), icon: Icon(Icons.female_rounded)),
                  ButtonSegment(value: 'groom', label: Text(S.groom), icon: Icon(Icons.male_rounded)),
                ],
                selected: {_gender},
                onSelectionChanged: (s) => setState(() => _gender = s.first),
              ),
              const SizedBox(height: 16),
              _MasterDropdown(
                label: S.maritalStatus,
                icon: Icons.favorite_border_rounded,
                items: masters.maritalStatuses,
                value: _maritalStatusId,
                onChanged: (v) => setState(() => _maritalStatusId = v),
              ),
              const SizedBox(height: 16),
              _TapField(
                label: S.dob,
                icon: Icons.cake_rounded,
                value: _dob == null ? null : formatDate(_dob),
                hint: S.selectDate,
                onTap: _pickDob,
              ),
              const SizedBox(height: 16),
              _TapField(
                label: S.birthTime,
                icon: Icons.schedule_rounded,
                value: _birthTime?.format(context),
                hint: S.selectTime,
                onTap: _pickBirthTime,
                onClear: _birthTime == null ? null : () => setState(() => _birthTime = null),
              ),
              // ============================================================ Birth
              const SizedBox(height: 24),
              const SectionHeader(S.birthDetails),
              TextFormField(
                controller: _birthPlace,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: S.birthPlace,
                  prefixIcon: Icon(Icons.location_on_outlined),
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
                onChanged: (v) => setState(() => _birthCountryId = v),
              ),
              const SizedBox(height: 12),
              _MasterDropdown(
                label: S.nakshatram,
                icon: Icons.auto_awesome_rounded,
                items: masters.nakshatrams,
                value: _nakshatramId,
                onChanged: (v) => setState(() => _nakshatramId = v),
              ),
              const SizedBox(height: 12),
              _MasterDropdown(
                label: S.rasi,
                icon: Icons.brightness_5_rounded,
                items: [for (final z in masters.zodiacSigns) MasterItem(id: z.id, name: z.label)],
                value: _zodiacId,
                onChanged: (v) => setState(() => _zodiacId = v),
              ),
              // ============================================================ Community
              const SizedBox(height: 24),
              const SectionHeader(S.communitySection),
              _MasterDropdown(
                label: S.nationality,
                icon: Icons.flag_outlined,
                items: masters.countries,
                value: _nationalityId,
                onChanged: (v) => setState(() => _nationalityId = v),
              ),
              const SizedBox(height: 12),
              _MasterDropdown(
                label: S.religion,
                icon: Icons.temple_hindu_rounded,
                items: masters.religions,
                value: _religionId,
                onChanged: (v) => setState(() => _religionId = v),
              ),
              const SizedBox(height: 12),
              _MasterDropdown(
                label: S.community,
                icon: Icons.groups_rounded,
                items: communityOptions,
                value: _communityId,
                onChanged: (v) => setState(() {
                  // A subcaste belongs to one community — reset it on change.
                  if (v != _communityId) _subcaste.clear();
                  _communityId = v;
                }),
              ),
              const SizedBox(height: 12),
              _SubcasteField(
                controller: _subcaste,
                options: subcasteOptions,
                enabled: _communityId != null,
                isNew: subcasteIsNew,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _gothram,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: S.gothram,
                  hintText: S.gothramHint,
                  prefixIcon: Icon(Icons.temple_hindu_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: S.nativeCity,
                        prefixIcon: Icon(Icons.home_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _state,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: S.nativeState),
                    ),
                  ),
                ],
              ),
              // ============================================================ Appearance
              const SizedBox(height: 24),
              const SectionHeader(S.appearance),
              _MasterDropdown(
                label: S.complexion,
                icon: Icons.face_rounded,
                items: masters.complexions,
                value: _complexionId,
                onChanged: (v) => setState(() => _complexionId = v),
              ),
              const SizedBox(height: 12),
              _MasterDropdown(
                label: S.motherTongue,
                icon: Icons.record_voice_over_outlined,
                items: masters.languages,
                value: _motherTongueId,
                onChanged: (v) => setState(() => _motherTongueId = v),
              ),
              const SizedBox(height: 12),
              _LanguageChips(
                items: masters.languages,
                selected: _languageIds,
                onToggle: (id) => setState(() {
                  _languageIds.contains(id) ? _languageIds.remove(id) : _languageIds.add(id);
                }),
              ),
              const SizedBox(height: 12),
              _MasterDropdown(
                label: S.foodHabit,
                icon: Icons.restaurant_rounded,
                items: masters.foodHabits,
                value: _foodHabitId,
                onChanged: (v) => setState(() => _foodHabitId = v),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _TapField(
                      label: S.height,
                      icon: Icons.straighten_rounded,
                      value: _heightCm == null ? null : '${Profile.feetInches(_heightCm!)} ($_heightCm cm)',
                      hint: S.selectHeight,
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
                        return n == null || n < 25 || n > 250 ? S.weightHint : null;
                      },
                    ),
                  ),
                ],
              ),
              // ============================================================ Education
              const SizedBox(height: 24),
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
                  controller: _eduLevelDetails[level]!,
                  countries: masters.countries,
                  countryId: _eduLevelCountry[level],
                  onCountryChanged: (v) => setState(() => _eduLevelCountry[level] = v),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _eduDetails,
                maxLines: 2,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: S.otherEducation,
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 4),
              _MasterDropdown(
                label: S.highestQualification,
                icon: Icons.school_rounded,
                items: masters.educations,
                value: _educationId,
                onChanged: (v) => setState(() => _educationId = v),
              ),
              // ============================================================ Work & income
              const SizedBox(height: 24),
              const SectionHeader(S.professional),
              _MasterDropdown(
                label: S.occupationType,
                icon: Icons.badge_outlined,
                items: masters.occupationTypes,
                value: _occupationTypeId,
                onChanged: (v) => setState(() => _occupationTypeId = v),
              ),
              const SizedBox(height: 12),
              _MasterDropdown(
                label: S.occupation,
                icon: Icons.work_outline_rounded,
                items: masters.professions,
                value: _professionId,
                onChanged: (v) => setState(() => _professionId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _income,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: S.salary,
                  hintText: S.salaryHint,
                  prefixIcon: Icon(Icons.currency_rupee_rounded),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _otherIncome,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: S.otherIncome,
                  hintText: S.otherIncomeHint,
                  prefixIcon: Icon(Icons.savings_outlined),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _workPlace,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: S.workPlace,
                  hintText: S.workPlaceHint,
                  prefixIcon: Icon(Icons.location_city_rounded),
                ),
              ),
              const SizedBox(height: 12),
              _MasterDropdown(
                label: S.workCountry,
                icon: Icons.public_rounded,
                items: masters.countries,
                value: _workCountryId,
                onChanged: (v) => setState(() => _workCountryId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _profDetails,
                maxLines: 2,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: S.otherProfessional,
                  hintText: S.otherProfessionalHint,
                  alignLabelWithHint: true,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(S.nriSwitch),
                secondary: const Icon(Icons.flight_takeoff_rounded, color: AppColors.wineLight),
                value: _isNri,
                onChanged: (v) => setState(() => _isNri = v),
              ),
              if (_isNri) ...[
                const SizedBox(height: 8),
                _MasterDropdown(
                  label: S.nriCountry,
                  icon: Icons.public_rounded,
                  items: masters.countries,
                  value: _nriCountryId,
                  onChanged: (v) => setState(() => _nriCountryId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nriPlace,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: S.nriPlace,
                    hintText: S.nriPlaceHint,
                    prefixIcon: Icon(Icons.flight_takeoff_rounded),
                  ),
                ),
              ],
              // ============================================================ Family
              const SizedBox(height: 24),
              const SectionHeader(S.family),
              _OnRequestNote(text: S.onRequestNote),
              const SizedBox(height: 16),
              _PersonBlock(
                nameController: _fatherName,
                occupationController: _fatherOccupation,
                phoneController: _fatherPhone,
                nameLabel: S.fatherName,
                occupationLabel: S.fatherOccupation,
                phoneLabel: S.fatherPhone,
              ),
              const SizedBox(height: 16),
              _PersonBlock(
                nameController: _motherName,
                occupationController: _motherOccupation,
                phoneController: _motherPhone,
                nameLabel: S.motherName,
                occupationLabel: S.motherOccupation,
                phoneLabel: S.motherPhone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: S.contactPersonName,
                  prefixIcon: Icon(Icons.contact_page_outlined),
                ),
              ),
              const SizedBox(height: 12),
              _PhoneField(controller: _contactPhone, label: S.contactPersonPhone),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text(S.hasSiblings, style: theme.textTheme.labelLarge),
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: -1, label: Text(S.notRecorded)),
                  ButtonSegment(value: 0, label: Text(S.no)),
                  ButtonSegment(value: 1, label: Text(S.yes)),
                ],
                selected: {_hasSiblings == null ? -1 : (_hasSiblings! ? 1 : 0)},
                onSelectionChanged: (s) => setState(() {
                  _hasSiblings = switch (s.first) { 1 => true, 0 => false, _ => null };
                }),
              ),
              if (_hasSiblings == true) ...[
                const SizedBox(height: 16),
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
                  controller: _siblingsDetails,
                  maxLines: 3,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: S.siblingsDetails,
                    alignLabelWithHint: true,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _family,
                maxLines: 3,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: S.familyDetails,
                  hintText: S.familyDetailsHint,
                  alignLabelWithHint: true,
                ),
              ),
              // ============================================================ Property
              const SizedBox(height: 16),
              const SectionHeader(S.property),
              TextFormField(
                controller: _propertyShare,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: S.propertyShare,
                  hintText: S.propertyShareHint,
                  prefixIcon: Icon(Icons.pie_chart_outline_rounded),
                  counterText: '',
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
              // ============================================================ About
              const SizedBox(height: 16),
              const SectionHeader(S.about),
              TextFormField(
                controller: _about,
                maxLines: 4,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: S.aboutHint, alignLabelWithHint: true),
              ),
              // ============================================================ Photos
              const SizedBox(height: 16),
              SectionHeader(
                S.photos,
                trailing: Text(
                  '$_photoCount / ${AppConfig.maxPhotos}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              _PhotoStrip(
                existing: _existingPhotos,
                added: _newPhotos,
                onAdd: _pickPhotos,
                onRemoveExisting: _deleteExistingPhoto,
                onRemoveNew: (f) => setState(() => _newPhotos.remove(f)),
                onEditNew: _editNewPhoto,
              ),
              if (_error != null) ...[
                const SizedBox(height: 20),
                ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy ? const ButtonSpinner() : Text(widget.isEdit ? S.saveChanges : S.saveProfile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================================================================== fields

class _MasterDropdown extends StatelessWidget {
  const _MasterDropdown({
    required this.label,
    required this.icon,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final List<MasterItem> items;
  final int? value;
  final ValueChanged<int?> onChanged;

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
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: [
        const DropdownMenuItem(value: null, child: Text('—')),
        for (final item in items) DropdownMenuItem(value: item.id, child: Text(item.name)),
      ],
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
  });

  final String label;
  final IconData icon;
  final String? value;
  final String hint;
  final VoidCallback onTap;
  final VoidCallback? onClear;

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
          suffixIcon: onClear == null
              ? null
              : IconButton(tooltip: S.clear, icon: const Icon(Icons.close_rounded), onPressed: onClear),
        ),
        child: Text(
          value ?? hint,
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
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          final t = (v ?? '').trim();
          if (t.isEmpty) return null;
          final n = int.tryParse(t);
          return n == null || n < 0 || n > 20 ? '0–20' : null;
        },
      );
}

/// The "shared only after approval" note above the family block.
class _OnRequestNote extends StatelessWidget {
  const _OnRequestNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ),
        ],
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
