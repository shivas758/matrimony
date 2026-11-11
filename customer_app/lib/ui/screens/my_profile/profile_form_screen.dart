import 'dart:convert';
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
import '../../widgets/step_header.dart';
import 'privacy_screen.dart';

part 'profile_form_fields.dart';
part 'profile_form_steps.dart';

/// The registration form in four steps (SPEC §9.18 F):
///
///  1. **Personal details** — name, gender, date of birth, marital status,
///     religion, community, subcaste, mother tongue, languages, height,
///     weight, complexion, food habit, nationality, about, photos.
///  2. **Professional details** — the education table, highest
///     qualification, occupation, income, work country, work place*, NRI.
///  3. **Horoscope** — star, rasi, gothram, birth time, birth place*.
///  4. **Family & contact** — parents*, siblings*, family*, property*, native
///     place*, contact person*.           (* = on request, SPEC §9.8)
///
/// A step header shows where you are; **Back** / **Next** sit at the bottom
/// and Next validates the step it leaves (the required fields — name, gender,
/// date of birth, community — are all in step 1). The last step's button
/// saves. When editing, every step can be opened from the header and Save is
/// in the app bar on every step. Nothing is sent until Save, and leaving with
/// unsaved changes asks first.
///
/// Creates my profile with POST /customer/my-profiles (multipart) or edits it
/// with PATCH /customer/my-profiles/:id + the photo routes (SPEC §9.12).
/// Needs a linked agent. Pops the saved [Profile].
///
/// The four steps live in `profile_form_steps.dart`, their field widgets in
/// `profile_form_fields.dart`; all state stays here, so moving between the
/// steps loses nothing.
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, this.existing, this.prefillName = false});

  /// Edit this profile of mine (PATCH /customer/my-profiles/:id); null
  /// creates a new one (POST /customer/my-profiles).
  final Profile? existing;

  /// A new profile starts with the account holder's name.
  final bool prefillName;

  bool get isEdit => existing != null;

  /// Registers a new profile: the form, and — once it is saved — the Privacy
  /// settings, opened this one time automatically so the family decides what
  /// others see before the profile goes anywhere (SPEC §9.18 G). Returns the
  /// new profile (with the privacy choices when they were saved); null when
  /// the form was left without saving.
  static Future<Profile?> create(BuildContext context, {bool prefillName = false}) async {
    final navigator = Navigator.of(context);
    final masters = context.read<MastersState>();
    final saved = await navigator.push<Profile>(
      MaterialPageRoute(builder: (_) => ProfileFormScreen(prefillName: prefillName)),
    );
    // A server older than v2.8 has no toggles to offer.
    if (saved == null || !masters.data.hasPrivacy || !navigator.mounted) return saved;
    final withPrivacy = await navigator.push<Profile>(
      MaterialPageRoute(builder: (_) => PrivacyScreen(profile: saved, afterCreate: true)),
    );
    return withPrivacy ?? saved;
  }

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  static const _stepCount = 4;
  static const _stepTitles = [S.stepPersonal, S.stepProfessional, S.stepHoroscope, S.stepFamily];
  static const _stepLabels = [
    S.stepPersonalShort,
    S.stepProfessionalShort,
    S.stepHoroscopeShort,
    S.stepFamilyShort,
  ];

  /// One form (and one scroll view) per step, all kept alive in an
  /// [IndexedStack] — so a hidden step can still be validated on Save.
  final _formKeys = List.generate(_stepCount, (_) => GlobalKey<FormState>());
  final _scrolls = List.generate(_stepCount, (_) => ScrollController());

  // Where to scroll when a field is wrong.
  final _nameAnchor = GlobalKey();
  final _dobAnchor = GlobalKey();
  final _communityAnchor = GlobalKey();
  final _weightAnchor = GlobalKey();
  final _siblingsAnchor = GlobalKey();
  final _dobField = GlobalKey<FormFieldState<DateTime>>();

  int _step = 0;

  /// The furthest step opened so far — a new profile's header lets you go
  /// back to (and return from) the steps you have already passed.
  int _reached = 0;

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

  /// What the form held when it opened (after the defaults) — anything else
  /// is an unsaved change.
  String _baseline = '';

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    // A new profile starts with the account's name.
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
      _gender = p.gender == 'groom' ? 'groom' : 'bride';
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
      // Every step of an existing profile is open from the start.
      _reached = _stepCount - 1;
    }
    _baseline = _signature();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mastersState = context.read<MastersState>();
      mastersState.load().then((_) {
        if (!mounted || widget.isEdit) return;
        // A new profile is Indian, born and working in India unless said
        // otherwise (SPEC §9.7: countries start with India).
        final india = _indiaId(mastersState.data);
        if (india == null) return;
        _applyDefaults(() {
          _nationalityId ??= india;
          _birthCountryId ??= india;
          _workCountryId ??= india;
        });
      });
      // One-community agents: skip a step.
      final agent = context.read<AuthState>().agent;
      if (_communityId == null && (agent?.communities.length ?? 0) == 1) {
        _applyDefaults(() => _communityId = agent!.communities.first.id);
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
    for (final s in _scrolls) {
      s.dispose();
    }
    super.dispose();
  }

  /// `setState` for the step widgets in the part files.
  void _update(VoidCallback fn) => setState(fn);

  /// Values the form fills in by itself are not "changes": when nothing was
  /// touched yet, the baseline moves with them.
  void _applyDefaults(VoidCallback fn) {
    final untouched = !_isDirty;
    setState(fn);
    if (untouched) _baseline = _signature();
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

  // ------------------------------------------------------------------ validators

  static String? _nameError(String? v) => (v ?? '').trim().length < 2 ? S.nameRequired : null;

  static String? _weightError(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return n == null || n < 25 || n > 250 ? S.weightHint : null;
  }

  static String? _countError(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return n == null || n < 0 || n > 20 ? '0–20' : null;
  }

  List<TextEditingController> get _siblingCounts =>
      [_elderSisters, _youngerSisters, _elderBrothers, _youngerBrothers];

  /// The first thing wrong on [step], as the place to scroll to; null when
  /// the step is fine. The required fields are all in step 1.
  GlobalKey? _firstProblem(int step) => switch (step) {
        0 => _nameError(_name.text) != null
            ? _nameAnchor
            : _dob == null
                ? _dobAnchor
                : _communityId == null
                    ? _communityAnchor
                    : _weightError(_weight.text) != null
                        ? _weightAnchor
                        : null,
        3 => _hasSiblings == true && _siblingCounts.any((c) => _countError(c.text) != null) ? _siblingsAnchor : null,
        _ => null,
      };

  /// Runs the validators of [step] (showing their messages) and says whether
  /// it may be left.
  bool _validateStep(int step) {
    final fieldsOk = _formKeys[step].currentState?.validate() ?? true;
    return _firstProblem(step) == null && fieldsOk;
  }

  /// Opens [step] and scrolls to its first problem.
  void _showProblem(int step) {
    final anchor = _firstProblem(step);
    setState(() {
      _step = step;
      _error = S.stepHasErrors(_stepTitles[step]);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = anchor?.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // ------------------------------------------------------------------ steps

  void _open(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      if (step > _reached) _reached = step;
      _error = null;
    });
  }

  void _next() {
    if (_busy || _step >= _stepCount - 1) return;
    if (_validateStep(_step)) {
      _open(_step + 1);
    } else {
      _showProblem(_step);
    }
  }

  void _back() {
    if (_busy || _step == 0) return;
    _open(_step - 1);
  }

  /// A new profile's header reaches the steps already passed; an existing
  /// profile's reaches every step.
  bool _canJump(int step) => !_busy && (widget.isEdit || step <= _reached);

  /// Tapping a step in the header. Registering: moving forward still checks
  /// the steps in between; editing: go anywhere (Save checks everything).
  void _jump(int step) {
    if (!_canJump(step) || step == _step) return;
    if (!widget.isEdit) {
      for (var s = _step; s < step; s++) {
        if (!_validateStep(s)) {
          _showProblem(s);
          return;
        }
      }
    }
    _open(step);
  }

  // ------------------------------------------------------------------ unsaved changes

  /// Everything the form would send, as one string.
  String _signature() => jsonEncode([_fields(), for (final f in _newPhotos) f.path]);

  bool get _isDirty => _signature() != _baseline;

  Future<void> _leave() async {
    if (_busy) return;
    if (_isDirty && !await confirmDiscard(context)) return;
    if (mounted) Navigator.of(context).pop();
  }

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
    final latest = DateTime(now.year - 18, now.month, now.day);
    final earliest = DateTime(now.year - 100);
    var initial = _dob ?? DateTime(now.year - 25, now.month, now.day);
    if (initial.isAfter(latest)) initial = latest;
    if (initial.isBefore(earliest)) initial = earliest;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: latest,
      helpText: S.dob,
    );
    if (picked == null || !mounted) return;
    setState(() => _dob = picked);
    // Clears "Select your date of birth" once it has been shown.
    if (_dobField.currentState?.hasError ?? false) _dobField.currentState!.validate();
  }

  Future<void> _pickBirthTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _birthTime ?? const TimeOfDay(hour: 6, minute: 0),
      helpText: S.birthTime,
    );
    if (picked != null && mounted) setState(() => _birthTime = picked);
  }

  /// Feet + inches on screen (that is how families quote height); cm on the wire.
  Future<void> _pickHeight() async {
    final selected = await _HeightPickerDialog.show(context, initialCm: _heightCm);
    if (selected != null && mounted) setState(() => _heightCm = selected);
  }

  // ------------------------------------------------------------------ save

  /// Which step holds the field the server complained about.
  static const _fieldSteps = <String, int>{
    'full_name': 0, 'gender': 0, 'dob': 0, 'marital_status_id': 0, 'religion_id': 0, 'community_id': 0,
    'subcaste_name': 0, 'subcaste_id': 0, 'mother_tongue_id': 0, 'known_language_ids': 0, 'height_cm': 0,
    'weight_kg': 0, 'complexion_id': 0, 'food_habit_id': 0, 'nationality_id': 0, 'about': 0, 'photos': 0,
    'education_levels': 1, 'education_id': 1, 'education_details': 1, 'occupation_type_id': 1,
    'profession_id': 1, 'profession_details': 1, 'income_text': 1, 'other_income': 1, 'work_country_id': 1,
    'work_place': 1, 'is_nri': 1, 'nri_country_id': 1, 'nri_place': 1,
    'nakshatram_id': 2, 'zodiac_id': 2, 'gothram': 2, 'birth_time': 2, 'birth_place': 2, 'birth_state': 2,
    'birth_country_id': 2,
  };

  /// The request body — every field of the four steps.
  Map<String, dynamic> _fields() {
    final isEdit = widget.isEdit;
    // Siblings: the counts travel only with "Yes"; the total is their sum.
    final hasSiblings = _hasSiblings == true;
    final counts = _siblingCounts.map(_countOf).toList();
    final sum = counts.whereType<int>().fold<int>(0, (a, b) => a + b);
    final siblingsCount = hasSiblings && counts.any((n) => n != null) ? sum : null;

    return <String, dynamic>{
      // ---- 1 Personal details
      'full_name': _text(_name),
      'gender': _gender,
      'dob': _dob == null ? null : _fmtDob(_dob!),
      'marital_status_id': _maritalStatusId,
      'religion_id': _religionId,
      'community_id': _communityId,
      // Free text: the server finds it in the community or creates it (SPEC §2).
      'subcaste_name': _text(_subcaste),
      'mother_tongue_id': _motherTongueId,
      // Multipart takes a comma list; JSON takes an array so [] clears it.
      'known_language_ids': isEdit ? _languageIds.toList() : _languageIds.join(','),
      'height_cm': _heightCm,
      'weight_kg': int.tryParse(_text(_weight)),
      'complexion_id': _complexionId,
      'food_habit_id': _foodHabitId,
      'nationality_id': _nationalityId,
      'about': _text(_about),
      // ---- 2 Professional details
      'education_levels': _educationLevelRows(),
      'education_id': _educationId,
      'education_details': _text(_eduDetails),
      'occupation_type_id': _occupationTypeId,
      'profession_id': _professionId,
      'profession_details': _text(_profDetails),
      'income_text': _text(_income),
      'other_income': _text(_otherIncome),
      'work_country_id': _workCountryId,
      'work_place': _text(_workPlace),
      'is_nri': _isNri,
      'nri_country_id': _isNri ? _nriCountryId : null,
      'nri_place': _isNri ? _text(_nriPlace) : null,
      // ---- 3 Horoscope (star, rasi, gothram and time are public; the birth
      // place, state and country are on request)
      'nakshatram_id': _nakshatramId,
      'zodiac_id': _zodiacId,
      'gothram': _text(_gothram),
      // "HH:MM" 24h; an empty string clears the time on edit.
      'birth_time': _birthTime == null ? '' : _fmtTime(_birthTime!),
      'birth_place': _text(_birthPlace),
      'birth_state': _text(_birthState),
      'birth_country_id': _birthCountryId,
      // ---- 4 Family & contact (all on request)
      'father_name': _text(_fatherName),
      'father_occupation': _text(_fatherOccupation),
      'father_phone': _text(_fatherPhone),
      'mother_name': _text(_motherName),
      'mother_occupation': _text(_motherOccupation),
      'mother_phone': _text(_motherPhone),
      // Tri-state: multipart drops '' (= not recorded); JSON null clears it.
      'has_siblings': isEdit ? _hasSiblings : (_hasSiblings?.toString() ?? ''),
      'siblings_count': siblingsCount,
      'elder_sisters': hasSiblings ? counts[0] : null,
      'younger_sisters': hasSiblings ? counts[1] : null,
      'elder_brothers': hasSiblings ? counts[2] : null,
      'younger_brothers': hasSiblings ? counts[3] : null,
      'siblings_details': hasSiblings ? _text(_siblingsDetails) : null,
      'family_details': _text(_family),
      'property_share': _text(_propertyShare),
      'property_details': _text(_propertyDetails),
      'city': _text(_city),
      'state': _text(_state),
      'contact_name': _text(_contactName),
      'contact_phone': _text(_contactPhone),
    };
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    // Every step is checked — a problem on a step that is not on screen
    // takes the user there.
    for (var step = 0; step < _stepCount; step++) {
      if (!_validateStep(step)) {
        _showProblem(step);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final fields = _fields();
    try {
      final service = context.read<ProfileService>();
      final paths = _newPhotos.map((f) => f.path).toList();
      Profile saved;
      if (widget.isEdit) {
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
      if (!mounted) return;
      // The server names the field: open the (first) step it lives on.
      int? step;
      for (final field in e.fieldErrors?.keys ?? const <String>[]) {
        final at = _fieldSteps[field] ?? _stepCount - 1;
        if (step == null || at < step) step = at;
      }
      setState(() {
        _error = friendlyMessage(e);
        if (step != null) _step = step;
      });
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
      if (mounted) setState(() => _existingPhotos.removeWhere((p) => p.id == photo.id));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, friendlyMessage(e), error: true);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final masters = context.watch<MastersState>().data;
    final agent = context.watch<AuthState>().agent;
    final isEdit = widget.isEdit;
    final last = _step == _stepCount - 1;

    final steps = <Widget>[
      _PersonalStep(form: this, masters: masters, agentCommunities: agent?.communities ?? const []),
      _ProfessionalStep(form: this, masters: masters),
      _HoroscopeStep(form: this, masters: masters),
      _FamilyStep(form: this),
    ];

    // System back and the app bar's arrow both ask before unsaved changes go.
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? S.editProfileTitle : S.newProfileTitle),
          leading: BackButton(onPressed: _busy ? null : _leave),
          actions: [
            // Editing: Save from any step.
            if (isEdit && !last)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: _busy ? null : _save,
                  child: const Text(S.save),
                ),
              ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Not while the keyboard leaves almost no room (a phone held
              // sideways): the field being typed in matters more.
              if (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom > 360)
                StepHeader(
                  labels: _stepLabels,
                  current: _step,
                  completed: {
                    for (var i = 0; i < _stepCount; i++)
                      if (i != _step && (isEdit || i < _reached)) i,
                  },
                  onTap: _jump,
                  canTap: _canJump,
                ),
              Expanded(
                child: IndexedStack(
                  index: _step,
                  children: [
                    for (var i = 0; i < _stepCount; i++)
                      Form(
                        key: _formKeys[i],
                        // Every field of a step stays built (a lazy list would
                        // drop the ones scrolled away, and their validators).
                        child: SingleChildScrollView(
                          controller: _scrolls[i],
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _StepTitle(step: i + 1, total: _stepCount, title: _stepTitles[i]),
                              steps[i],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.rule)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      if (_step > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                            onPressed: _busy ? null : _back,
                            child: const Text(S.back, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: 2,
                        child: last
                            ? FilledButton(
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                                onPressed: _busy ? null : _save,
                                child: _busy
                                    ? const ButtonSpinner()
                                    : Text(
                                        isEdit ? S.saveChanges : S.saveProfile,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              )
                            : FilledButton(
                                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                                onPressed: _busy ? null : _next,
                                child: _busy
                                    ? const ButtonSpinner()
                                    : const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(child: Text(S.next, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                          SizedBox(width: 6),
                                          Icon(Icons.arrow_forward_rounded, size: 18),
                                        ],
                                      ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Step 2 of 4" over the step's full name, at the top of each step.
class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.step, required this.total, required this.title});

  final int step;
  final int total;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            S.stepOf(step, total),
            style: theme.textTheme.labelMedium?.copyWith(color: AppColors.goldDark, fontWeight: FontWeight.w700),
          ),
          Text(title, style: theme.textTheme.titleLarge?.copyWith(color: AppColors.wine)),
        ],
      ),
    );
  }
}
