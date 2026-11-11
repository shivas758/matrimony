import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../config.dart';
import '../../../models/master_data.dart';
import '../../../models/parsed_profile.dart';
import '../../../models/profile.dart';
import '../../../services/api_client.dart';
import '../../../services/profile_service.dart';
import '../../../state/auth_state.dart';
import '../../../state/masters_state.dart';
import '../../../state/profile_form_logic.dart';
import '../../strings.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/photo_picker.dart';
import '../../widgets/privacy_card.dart';
import '../../widgets/step_header.dart';

part 'profile_form_fields.dart';
part 'profile_form_steps.dart';

/// Add or edit a profile (SPEC §5 screen 5) in four steps (SPEC §9.18 F):
/// Personal details → Professional details → Horoscope → Family & contact.
/// Nothing is sent until Save. Pops `true` when saved.
///
/// The screen is split over three files of one library:
///  * this one — the form's state, validation, saving and the frame
///    (step header, the four pages, Back / Next / Save);
///  * `profile_form_steps.dart` — what each step shows;
///  * `profile_form_fields.dart` — the field widgets and the AI import sheet.
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, this.existing});

  final Profile? existing;

  bool get isEdit => existing != null;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  /// One [Form] per step. All four stay mounted (IndexedStack), so every
  /// field keeps its input and can be validated while another step shows.
  final List<GlobalKey<FormState>> _formKeys = [
    for (final _ in ProfileFormStep.values) GlobalKey<FormState>(),
  ];

  ProfileFormStep _step = ProfileFormStep.personal;

  /// Index of the furthest step opened so far — a new profile moves forward
  /// through Next, and the steps behind it are ticked in the header.
  int _furthest = 0;

  /// Every step may be opened from the header: always for an edit, and for a
  /// new profile once the AI import has filled the whole form.
  late bool _allStepsOpen = widget.isEdit;

  late final TextEditingController _name;
  late final TextEditingController _subcaste;
  late final TextEditingController _gothram;
  late final TextEditingController _weight;
  late final TextEditingController _eduDetails;
  late final TextEditingController _profDetails;
  late final TextEditingController _workPlace;
  late final TextEditingController _income;
  late final TextEditingController _nriPlace;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _about;
  late final TextEditingController _family;
  late final TextEditingController _fatherName;
  late final TextEditingController _fatherPhone;
  late final TextEditingController _motherName;
  late final TextEditingController _motherPhone;
  late final TextEditingController _contactName;
  late final TextEditingController _contactPhone;
  late final TextEditingController _birthPlace;
  late final TextEditingController _siblingsCount;
  late final TextEditingController _siblingsDetails;
  // ---- v2.1 registration-form fields (SPEC §9.7)
  late final TextEditingController _otherIncome;
  late final TextEditingController _birthState;
  late final TextEditingController _fatherOccupation;
  late final TextEditingController _motherOccupation;
  late final TextEditingController _elderSisters;
  late final TextEditingController _youngerSisters;
  late final TextEditingController _elderBrothers;
  late final TextEditingController _youngerBrothers;
  late final TextEditingController _propertyShare;
  late final TextEditingController _propertyDetails;

  /// The education table: one details field and one country per level, in
  /// the paper form's order. Rows left empty are not sent.
  final Map<String, TextEditingController> _eduLevelDetails = {
    for (final level in EducationLevel.levels) level: TextEditingController(),
  };
  final Map<String, int?> _eduLevelCountry = {for (final level in EducationLevel.levels) level: null};

  String _gender = 'bride';
  int? _nationalityId;
  int? _occupationTypeId;
  int? _workCountryId;
  int? _birthCountryId;
  DateTime? _dob;
  TimeOfDay? _birthTime;
  int? _heightCm;
  int? _complexionId;
  int? _communityId;
  int? _subcasteId; // null while the typed subcaste is new (created on save)
  int? _educationId;
  int? _professionId;
  int? _maritalStatusId;
  bool _isNri = false;
  int? _nriCountryId;
  int? _zodiacId;
  int? _nakshatramId;
  int? _religionId;
  int? _motherTongueId;
  final Set<int> _languageIds = {};
  int? _foodHabitId;
  /// null = not recorded, false = none, true = count + details below.
  bool? _hasSiblings;
  String _status = 'active';

  /// The Privacy card (SPEC §9.18 D / E): details switched off and the
  /// audience. Everything shown to the own community until changed.
  ProfilePrivacy _privacy = const ProfilePrivacy();

  final List<XFile> _newPhotos = [];
  late List<ProfilePhoto> _existingPhotos;

  bool _busy = false;
  String? _error;

  /// What the form held when it opened (after the defaults were applied) —
  /// compared on the way out to ask before discarding changes.
  String _pristine = '';

  // AI import (SPEC §4 POST /profiles/parse). Hidden unless the server has a key.
  bool _aiEnabled = false;
  bool _aiBusy = false;
  ParsedProfile? _lastParse;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.fullName ?? '');
    _subcaste = TextEditingController(text: p?.subcaste?.name ?? '');
    _gothram = TextEditingController(text: p?.gothram ?? '');
    _weight = TextEditingController(text: p?.weightKg?.toString() ?? '');
    _eduDetails = TextEditingController(text: p?.educationDetails ?? '');
    _profDetails = TextEditingController(text: p?.professionDetails ?? '');
    _workPlace = TextEditingController(text: p?.workPlace ?? '');
    _income = TextEditingController(text: p?.incomeText ?? '');
    _nriPlace = TextEditingController(text: p?.nriPlace ?? '');
    _city = TextEditingController(text: p?.city ?? '');
    _state = TextEditingController(text: p?.state ?? '');
    _about = TextEditingController(text: p?.about ?? '');
    _family = TextEditingController(text: p?.familyDetails ?? '');
    _fatherName = TextEditingController(text: p?.fatherName ?? '');
    _fatherPhone = TextEditingController(text: p?.fatherPhone ?? '');
    _motherName = TextEditingController(text: p?.motherName ?? '');
    _motherPhone = TextEditingController(text: p?.motherPhone ?? '');
    _contactName = TextEditingController(text: p?.contactName ?? '');
    _contactPhone = TextEditingController(text: p?.contactPhone ?? '');
    _birthPlace = TextEditingController(text: p?.birthPlace ?? '');
    _siblingsCount = TextEditingController(text: p?.siblingsCount?.toString() ?? '');
    _siblingsDetails = TextEditingController(text: p?.siblingsDetails ?? '');
    _otherIncome = TextEditingController(text: p?.otherIncome ?? '');
    _birthState = TextEditingController(text: p?.birthState ?? '');
    _fatherOccupation = TextEditingController(text: p?.fatherOccupation ?? '');
    _motherOccupation = TextEditingController(text: p?.motherOccupation ?? '');
    _elderSisters = TextEditingController(text: _countText(p?.elderSisters));
    _youngerSisters = TextEditingController(text: _countText(p?.youngerSisters));
    _elderBrothers = TextEditingController(text: _countText(p?.elderBrothers));
    _youngerBrothers = TextEditingController(text: _countText(p?.youngerBrothers));
    _propertyShare = TextEditingController(text: p?.propertyShare ?? '');
    _propertyDetails = TextEditingController(text: p?.propertyDetails ?? '');
    for (final row in p?.educationLevels ?? const <EducationLevel>[]) {
      _eduLevelDetails[row.level]?.text = row.details ?? '';
      if (_eduLevelCountry.containsKey(row.level)) _eduLevelCountry[row.level] = row.country?.id;
    }
    _existingPhotos = [...?p?.photos];

    if (p != null) {
      _gender = p.gender;
      _nationalityId = p.nationality?.id;
      _occupationTypeId = p.occupationType?.id;
      _workCountryId = p.workCountry?.id;
      _birthCountryId = p.birthCountry?.id;
      _dob = p.dob;
      _heightCm = p.heightCm;
      _complexionId = p.complexion?.id;
      _communityId = p.community?.id;
      _subcasteId = p.subcaste?.id;
      _educationId = p.education?.id;
      _professionId = p.profession?.id;
      _maritalStatusId = p.maritalStatus?.id;
      _isNri = p.isNri;
      _nriCountryId = p.nriCountry?.id;
      _zodiacId = p.zodiac?.id;
      _nakshatramId = p.nakshatram?.id;
      _status = p.status.apiValue;
      _birthTime = _parseTime(p.birthTime);
      _religionId = p.religion?.id;
      _motherTongueId = p.motherTongue?.id;
      _languageIds.addAll(p.knownLanguages.map((l) => l.id));
      _foodHabitId = p.foodHabit?.id;
      _hasSiblings = p.hasSiblings;
      // The family's saved setting — sent to the owner side only (SPEC §9.18 D / E).
      _privacy = ProfilePrivacy.fromServer(
        hiddenFields: p.hiddenFields,
        audienceAll: p.audienceAll,
        audienceCommunityIds: p.audienceCommunities.map((c) => c.id),
      );
    }
    _pristine = _snapshot();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mastersState = context.read<MastersState>();
      mastersState.load().then((_) {
        // A new profile works in India unless the agent says otherwise
        // (SPEC §9.7: countries start with India). Edits keep what was saved.
        if (!mounted || widget.isEdit || _workCountryId != null) return;
        final india = mastersState.data.indiaCountryId;
        if (india != null) _applyDefault(() => _workCountryId = india);
      });
      // Default to the agent's only community so one-community agents skip a step.
      final agent = context.read<AuthState>().agent;
      if (_communityId == null && (agent?.communities.length ?? 0) == 1) {
        _applyDefault(() => _communityId = agent!.communities.first.id);
      }
      if (!widget.isEdit) {
        context.read<ProfileService>().aiEnabled().then((on) {
          if (mounted) setState(() => _aiEnabled = on);
        });
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name, _subcaste, _gothram, _weight, _eduDetails, _profDetails, _workPlace, _income,
      _nriPlace, _city, _state, _about, _family, _fatherName, _fatherPhone, _motherName,
      _motherPhone, _contactName, _contactPhone, _birthPlace, _siblingsCount, _siblingsDetails,
      _otherIncome, _birthState, _fatherOccupation, _motherOccupation, _elderSisters,
      _youngerSisters, _elderBrothers, _youngerBrothers, _propertyShare, _propertyDetails,
      ..._eduLevelDetails.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// `setState` for the step builders, which live in an extension
  /// (profile_form_steps.dart) and so cannot call the protected method.
  void _set(VoidCallback fn) => setState(fn);

  /// Applies a default the user did not choose (India, the only community)
  /// without making an untouched form count as changed.
  void _applyDefault(VoidCallback fn) {
    final untouched = !_hasChanges;
    setState(fn);
    if (untouched) _pristine = _snapshot();
  }

  /// A count field shows nothing for null; "0" is a real answer.
  static String _countText(int? n) => n == null ? '' : '$n';

  /// null when blank, else the number (the validators keep it 0–20).
  static int? _countOf(TextEditingController c) => int.tryParse(c.text.trim());

  /// The education rows the agent filled in — `{level, details, country_id}`
  /// in the paper order. Rows with neither details nor a country are dropped.
  List<Map<String, dynamic>> _educationLevelRows() => [
        for (final level in EducationLevel.levels)
          if (_eduLevelDetails[level]!.text.trim().isNotEmpty || _eduLevelCountry[level] != null)
            {
              'level': level,
              'details': _eduLevelDetails[level]!.text.trim().isEmpty
                  ? null
                  : _eduLevelDetails[level]!.text.trim(),
              'country_id': _eduLevelCountry[level],
            },
      ];

  int get _photoCount => _existingPhotos.length + _newPhotos.length;

  Future<void> _pickPhotos() async {
    final remaining = AppConfig.maxPhotos - _photoCount;
    if (remaining <= 0) {
      showSnack(context, 'Maximum ${AppConfig.maxPhotos} photos', error: true);
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
    final initial = _dob ?? DateTime(now.year - 27, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: S.dob,
    );
    if (picked != null && mounted) setState(() => _dob = picked);
  }

  Future<void> _pickHeight() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: 380,
        child: ListView.builder(
          itemCount: 121, // 120cm – 240cm
          itemBuilder: (_, i) {
            final cm = 120 + i;
            // Feet/inches first — that is how families quote height.
            return ListTile(
              title: Text(Profile.feetInches(cm)),
              trailing: Text('$cm cm'),
              selected: cm == _heightCm,
              onTap: () => Navigator.pop(context, cm),
            );
          },
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _heightCm = selected);
  }

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

  Future<void> _pickBirthTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _birthTime ?? const TimeOfDay(hour: 6, minute: 0),
      helpText: S.birthTime,
    );
    if (picked != null && mounted) setState(() => _birthTime = picked);
  }

  // ------------------------------------------------------------------ AI import

  Future<void> _fillFromBiodata() async {
    final input = await _AiImportSheet.show(context);
    if (input == null || !mounted) return;
    setState(() => _aiBusy = true);
    try {
      final result = await context
          .read<ProfileService>()
          .parseBioData(filePath: input.path, text: input.text);
      if (!mounted) return;
      _applyDraft(result);
      showSnack(context, S.aiFilled);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  /// Pre-fills the form from the server's draft. Only touches fields the
  /// draft actually contains, so a partial extraction never wipes typed input.
  void _applyDraft(ParsedProfile r) {
    final masters = context.read<MastersState>().data;
    final agent = context.read<AuthState>().agent;
    final allowed = (agent?.isAdmin ?? false)
        ? masters.communities.map((c) => c.id).toSet()
        : (agent?.communities ?? const []).map((c) => c.id).toSet();

    setState(() {
      final name = r.textField('full_name');
      if (name != null) _name.text = name;
      final gender = r.textField('gender');
      if (gender == 'bride' || gender == 'groom') _gender = gender!;
      final dob = r.textField('dob');
      if (dob != null) _dob = DateTime.tryParse(dob) ?? _dob;
      final height = r.intField('height_cm');
      if (height != null) _heightCm = height;
      final weight = r.intField('weight_kg');
      if (weight != null) _weight.text = '$weight';
      _complexionId = r.intField('complexion_id') ?? _complexionId;
      if (r.draft.containsKey('is_nri')) _isNri = r.draft['is_nri'] == true;
      _nriCountryId = r.intField('nri_country_id') ?? _nriCountryId;
      // v2.1 registration-form keys — optional, ignored when absent.
      _nationalityId = r.intField('nationality_id') ?? _nationalityId;
      _occupationTypeId = r.intField('occupation_type_id') ?? _occupationTypeId;
      _workCountryId = r.intField('work_country_id') ?? _workCountryId;
      _birthCountryId = r.intField('birth_country_id') ?? _birthCountryId;
      for (final (key, controller) in [
        ('elder_sisters', _elderSisters),
        ('younger_sisters', _youngerSisters),
        ('elder_brothers', _elderBrothers),
        ('younger_brothers', _youngerBrothers),
      ]) {
        final n = r.intField(key);
        if (n != null) controller.text = '$n';
      }
      final levels = r.educationLevels;
      if (levels.isNotEmpty) {
        for (final row in levels) {
          final level = row['level'] as String;
          _eduLevelDetails[level]?.text = (row['details'] as String?) ?? '';
          if (_eduLevelCountry.containsKey(level)) _eduLevelCountry[level] = row['country_id'] as int?;
        }
      }

      final community = r.intField('community_id');
      if (community != null && allowed.contains(community)) {
        if (community != _communityId) {
          _subcasteId = null;
          _subcaste.clear();
        }
        _communityId = community;
      }
      final subcasteId = r.intField('subcaste_id');
      final subcasteName = r.textField('subcaste_name');
      if (subcasteId != null && masters.subcasteName(subcasteId) != null) {
        _subcasteId = subcasteId;
        _subcaste.text = masters.subcasteName(subcasteId)!;
      } else if (subcasteName != null) {
        _subcasteId = null; // new — created on save
        _subcaste.text = subcasteName;
      }

      _educationId = r.intField('education_id') ?? _educationId;
      _professionId = r.intField('profession_id') ?? _professionId;
      _maritalStatusId = r.intField('marital_status_id') ?? _maritalStatusId;
      _zodiacId = r.intField('zodiac_id') ?? _zodiacId;
      _nakshatramId = r.intField('nakshatram_id') ?? _nakshatramId;
      final birthTime = _parseTime(r.textField('birth_time'));
      if (birthTime != null) _birthTime = birthTime;
      _religionId = r.intField('religion_id') ?? _religionId;
      _motherTongueId = r.intField('mother_tongue_id') ?? _motherTongueId;
      _foodHabitId = r.intField('food_habit_id') ?? _foodHabitId;
      final langs = r.draft['known_language_ids'];
      if (langs is List && langs.isNotEmpty) {
        _languageIds
          ..clear()
          ..addAll(langs.whereType<num>().map((e) => e.toInt()));
      }
      if (r.draft.containsKey('has_siblings')) _hasSiblings = r.draft['has_siblings'] as bool?;
      final siblings = r.intField('siblings_count');
      if (siblings != null) _siblingsCount.text = '$siblings';

      for (final (key, controller) in [
        ('birth_place', _birthPlace),
        ('gothram', _gothram),
        ('education_details', _eduDetails),
        ('profession_details', _profDetails),
        ('work_place', _workPlace),
        ('income_text', _income),
        ('nri_place', _nriPlace),
        ('city', _city),
        ('state', _state),
        ('about', _about),
        ('family_details', _family),
        ('father_name', _fatherName),
        ('father_phone', _fatherPhone),
        ('mother_name', _motherName),
        ('mother_phone', _motherPhone),
        ('contact_name', _contactName),
        ('contact_phone', _contactPhone),
        ('siblings_details', _siblingsDetails),
        ('other_income', _otherIncome),
        ('birth_state', _birthState),
        ('father_occupation', _fatherOccupation),
        ('mother_occupation', _motherOccupation),
        ('property_share', _propertyShare),
        ('property_details', _propertyDetails),
      ]) {
        final v = r.textField(key);
        if (v != null) controller.text = v;
      }

      _lastParse = r;
      _error = null;
      // The draft fills all four steps — let the agent jump to any of them
      // to check the hints.
      _allStepsOpen = true;
    });
  }

  /// The raw text the AI import could not map for [key], if any.
  String? _hint(String key) => _lastParse?.unmatched[key];

  // ------------------------------------------------------------------ steps

  /// Shows [step]. The keyboard goes away with the step it belonged to.
  void _goTo(ProfileFormStep step) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (step == _step) return;
    setState(() {
      _step = step;
      if (step.index > _furthest) _furthest = step.index;
    });
  }

  /// New profile: the steps already opened. Edit (or after an AI import): all.
  bool _canOpen(int index) => _allStepsOpen || index <= _furthest;

  /// Runs the validators of one step. On a failure the step is shown, the
  /// topmost field in error is scrolled into view and false is returned.
  bool _validateStep(ProfileFormStep step) {
    final form = _formKeys[step.index].currentState;
    if (form == null) return true;
    final invalid = form.validateGranularly();
    if (invalid.isEmpty) return true;

    _goTo(step);
    // After the step is on screen: bring the first error into view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FormFieldState<Object?>? top;
      double topY = double.infinity;
      for (final field in invalid) {
        if (!field.mounted) continue;
        final box = field.context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        if (y < topY) {
          topY = y;
          top = field;
        }
      }
      if (top != null) {
        Scrollable.ensureVisible(
          top.context,
          alignment: 0.15,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    showSnack(context, S.checkHighlighted, error: true);
    return false;
  }

  /// Next: only with the current step in order.
  void _next() {
    final next = _step.next;
    if (next == null || !_validateStep(_step)) return;
    setState(() => _error = null);
    _goTo(next);
  }

  void _back() {
    final previous = _step.previous;
    if (previous != null) _goTo(previous);
  }

  // ------------------------------------------------------------------ save

  /// Everything the form holds, as the profile write body. `dob` is null
  /// until picked; [_save] refuses to send that.
  Map<String, dynamic> _collectFields() {
    // Siblings: the breakdown counts only travel when "Has siblings = Yes";
    // when the total was left blank it is the sum of the breakdown.
    final hasSiblings = _hasSiblings == true;
    final breakdown = [
      _countOf(_elderSisters),
      _countOf(_youngerSisters),
      _countOf(_elderBrothers),
      _countOf(_youngerBrothers),
    ];
    final typedCount = int.tryParse(_siblingsCount.text.trim());
    final breakdownSum = breakdown.whereType<int>().fold<int>(0, (a, b) => a + b);
    final siblingsCount = !hasSiblings
        ? null
        : typedCount ?? (breakdown.any((n) => n != null) && breakdownSum > 0 ? breakdownSum : null);

    return <String, dynamic>{
      'full_name': _name.text.trim(),
      'gender': _gender,
      'dob': _dob == null ? null : _fmtDob(_dob!),
      'height_cm': _heightCm,
      'weight_kg': int.tryParse(_weight.text.trim()),
      'complexion_id': _complexionId,
      'nationality_id': _nationalityId,
      'community_id': _communityId,
      // Existing subcaste by id, or free text the server finds-or-creates.
      'subcaste_id': _subcasteId,
      'subcaste_name': _subcasteId == null ? _subcaste.text.trim() : null,
      'gothram': _gothram.text.trim(),
      'education_id': _educationId,
      'education_details': _eduDetails.text.trim(),
      // The education table (SPEC §9.7): the service JSON-encodes it for
      // multipart; as JSON an empty array clears the saved rows.
      'education_levels': _educationLevelRows(),
      'profession_id': _professionId,
      'profession_details': _profDetails.text.trim(),
      'occupation_type_id': _occupationTypeId,
      // Public coarse location (SPEC §9.8); the exact work place is protected.
      'work_country_id': _workCountryId,
      'marital_status_id': _maritalStatusId,
      'zodiac_id': _zodiacId,
      'nakshatram_id': _nakshatramId,
      // Horoscope birth time: "HH:MM" 24h; an empty string clears the time.
      'birth_time': _birthTime == null ? '' : _fmtTime(_birthTime!),
      'income_text': _income.text.trim(),
      'other_income': _otherIncome.text.trim(),
      'is_nri': _isNri,
      'nri_country_id': _isNri ? _nriCountryId : null,
      'religion_id': _religionId,
      'mother_tongue_id': _motherTongueId,
      // Multipart (create) takes a comma list; JSON (edit) takes an array so [] clears it.
      'known_language_ids': widget.isEdit ? _languageIds.toList() : _languageIds.join(','),
      'food_habit_id': _foodHabitId,
      'about': _about.text.trim(),
      // ---- personal details (PROTECTED on the server, SPEC §9.8): native
      // place, birth place, work place, NRI place, parents, contact person,
      // siblings, property, family details.
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'birth_place': _birthPlace.text.trim(),
      'birth_state': _birthState.text.trim(),
      'birth_country_id': _birthCountryId,
      'work_place': _workPlace.text.trim(),
      'nri_place': _isNri ? _nriPlace.text.trim() : null,
      'father_name': _fatherName.text.trim(),
      'father_occupation': _fatherOccupation.text.trim(),
      'father_phone': _fatherPhone.text.trim(),
      'mother_name': _motherName.text.trim(),
      'mother_occupation': _motherOccupation.text.trim(),
      'mother_phone': _motherPhone.text.trim(),
      'contact_name': _contactName.text.trim(),
      'contact_phone': _contactPhone.text.trim(),
      // Tri-state: multipart drops '' (= not recorded); JSON null clears it.
      'has_siblings': widget.isEdit ? _hasSiblings : (_hasSiblings?.toString() ?? ''),
      'siblings_count': siblingsCount,
      'siblings_details': hasSiblings ? _siblingsDetails.text.trim() : null,
      'elder_sisters': hasSiblings ? breakdown[0] : null,
      'younger_sisters': hasSiblings ? breakdown[1] : null,
      'elder_brothers': hasSiblings ? breakdown[2] : null,
      'younger_brothers': hasSiblings ? breakdown[3] : null,
      'property_share': _propertyShare.text.trim(),
      'property_details': _propertyDetails.text.trim(),
      'family_details': _family.text.trim(),
      'status': _status,
    };
  }

  /// The form's content as one string — two snapshots differ exactly when
  /// the agent changed something.
  String _snapshot() => jsonEncode({
        ..._collectFields(),
        'new_photos': [for (final f in _newPhotos) f.path],
        'privacy_hidden': _privacy.hidden.toList()..sort(),
        'privacy_mode': _privacy.mode.name,
        'privacy_communities': _privacy.communityIds.toList()..sort(),
      });

  bool get _hasChanges => _snapshot() != _pristine;

  Future<void> _save() async {
    // Every step is checked, in order; the first one in error is shown.
    for (final step in ProfileFormStep.values) {
      if (!_validateStep(step)) return;
    }
    // The validators above cover both; this only guards the request itself.
    if (_dob == null || _communityId == null) {
      _goTo(ProfileFormStep.personal);
      setState(() => _error = _dob == null ? S.dobRequired : S.communityRequired);
      return;
    }
    final masters = context.read<MastersState>().data;
    final fields = _collectFields();

    // The Privacy card (SPEC §9.18 D / E) — only against a server that
    // serves the list; an older one gets nothing it would not understand.
    final privacyKeys = masters.privacyFields.map((f) => f.key);
    if (privacyKeys.isNotEmpty) {
      fields.addAll(
        widget.isEdit
            // JSON PATCH: real arrays and a real boolean.
            ? _privacy.toJsonFields(privacyKeys, ownCommunityId: _communityId)
            // Multipart POST: JSON array strings and "true" / "false".
            : _privacy.toMultipartFields(privacyKeys, ownCommunityId: _communityId),
      );
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final service = context.read<ProfileService>();
      if (widget.isEdit) {
        await service.update(widget.existing!.id, fields);
        await service.addPhotos(widget.existing!.id, _newPhotos.map((f) => f.path).toList());
      } else {
        await service.create(fields, _newPhotos.map((f) => f.path).toList());
      }
      // A newly typed subcaste is now in the master list — refresh the cache.
      if (mounted) context.read<MastersState>().load(force: true);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      // A field the server refused may live on another step — go there.
      final errors = e.fieldErrors ?? const <String, String>{};
      final step = ProfileFormStep.firstFor(errors.keys);
      if (step != null) _goTo(step);
      setState(() => _error = errors.values.firstOrNull ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaving with unsaved changes asks first (SPEC §9.18 F).
  Future<void> _leave() async {
    if (_busy) return;
    if (_hasChanges) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(S.discardChangesTitle),
          content: const Text(S.discardChangesBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.keepEditing)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(S.discard),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _deleteExistingPhoto(ProfilePhoto photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.removePhoto),
        content: const Text('This photo will be deleted permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text(S.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ProfileService>().deletePhoto(photo.id);
      if (mounted) setState(() => _existingPhotos.removeWhere((p) => p.id == photo.id));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final masters = context.watch<MastersState>().data;
    final agent = context.watch<AuthState>().agent;

    // Agents can only file profiles into their own communities; admins anywhere.
    final allowedCommunities = (agent?.isAdmin ?? false)
        ? masters.communities
        : masters.communities
            .where((c) => (agent?.communities ?? []).any((mine) => mine.id == c.id))
            .toList();

    final pages = <ProfileFormStep, List<Widget>>{
      ProfileFormStep.personal: _personalStep(context, masters, allowedCommunities),
      ProfileFormStep.professional: _professionalStep(context, masters),
      ProfileFormStep.horoscope: _horoscopeStep(context, masters),
      ProfileFormStep.family: _familyStep(context, masters),
    };

    return PopScope(
      // Always asked here, so unsaved input is never lost to a stray back.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.isEdit ? S.editProfileTitle : S.newProfile)),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              StepHeader(
                labels: [for (final s in ProfileFormStep.values) s.shortLabel],
                current: _step.index,
                completed: {
                  for (final s in ProfileFormStep.values)
                    if (s != _step && (widget.isEdit || s.index < _furthest)) s.index,
                },
                onStepTapped: _busy ? null : (i) => _goTo(ProfileFormStep.values[i]),
                canTap: _canOpen,
              ),
              const Divider(height: 1),
              Expanded(
                // All four steps stay alive, so moving between them never
                // loses input and Save can validate every one of them.
                child: IndexedStack(
                  index: _step.index,
                  children: [
                    for (final step in ProfileFormStep.values)
                      Form(
                        key: _formKeys[step.index],
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [_StepTitle(step), ...pages[step]!],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _bottomBar(context),
      ),
    );
  }

  /// Back / Next pinned under the form; the last step's button saves. An
  /// edit can also save from any step.
  Widget _bottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final last = _step.isLast;

    Widget label(String text) => FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1));
    const spinner = SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
    );
    const tight = EdgeInsets.symmetric(horizontal: 12);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  if (!_step.isFirst) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(padding: tight),
                        onPressed: _busy ? null : _back,
                        child: label(S.back),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (widget.isEdit && !last) ...[
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: tight,
                          backgroundColor: AppColors.goldPale,
                          foregroundColor: AppColors.navyDeep,
                        ),
                        onPressed: _busy ? null : _save,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : label(S.save),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    // The way forward gets the most room.
                    flex: _step.isFirst || (widget.isEdit && !last) ? 1 : 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(padding: tight),
                      onPressed: _busy ? null : (last ? _save : _next),
                      child: last ? (_busy ? spinner : label(S.save)) : label(S.next),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
