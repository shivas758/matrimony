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
import '../../strings.dart';
import '../../widgets/common.dart';

/// Add or edit a profile (SPEC §5 screen 5). Pops `true` when saved.
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key, this.existing});

  final Profile? existing;

  bool get isEdit => existing != null;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

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

  final List<XFile> _newPhotos = [];
  late List<ProfilePhoto> _existingPhotos;

  bool _busy = false;
  String? _error;

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
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mastersState = context.read<MastersState>();
      mastersState.load().then((_) {
        // A new profile works in India unless the agent says otherwise
        // (SPEC §9.7: countries start with India). Edits keep what was saved.
        if (!mounted || widget.isEdit || _workCountryId != null) return;
        final india = mastersState.data.indiaCountryId;
        if (india != null) setState(() => _workCountryId = india);
      });
      // Default to the agent's only community so one-community agents skip a step.
      final agent = context.read<AuthState>().agent;
      if (_communityId == null && (agent?.communities.length ?? 0) == 1) {
        setState(() => _communityId = agent!.communities.first.id);
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
    final picked = await _picker.pickMultiImage(imageQuality: 92, limit: remaining);
    if (picked.isEmpty) return;
    setState(() => _newPhotos.addAll(picked.take(remaining)));
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
    if (picked != null) setState(() => _dob = picked);
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
    if (selected != null) setState(() => _heightCm = selected);
  }

  String _fmtDob(DateTime d) =>
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
    if (picked != null) setState(() => _birthTime = picked);
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
    });
  }

  String? _hint(String key) => _lastParse?.unmatched[key];

  // ------------------------------------------------------------------ save

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      setState(() => _error = 'Select the date of birth');
      return;
    }
    if (_communityId == null) {
      setState(() => _error = 'Select a community');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

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

    final fields = <String, dynamic>{
      'full_name': _name.text.trim(),
      'gender': _gender,
      'dob': _fmtDob(_dob!),
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
      if (mounted) {
        setState(() => _error = e.fieldErrors?.values.firstOrNull ?? e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      setState(() => _existingPhotos.removeWhere((p) => p.id == photo.id));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final masters = context.watch<MastersState>().data;
    final agent = context.watch<AuthState>().agent;
    final theme = Theme.of(context);

    // Agents can only file profiles into their own communities; admins anywhere.
    final allowedCommunities = (agent?.isAdmin ?? false)
        ? masters.communities
        : masters.communities
            .where((c) => (agent?.communities ?? []).any((mine) => mine.id == c.id))
            .toList();

    final subcasteOptions = masters.subcastesFor(_communityId);
    final typedSubcaste = _subcaste.text.trim();
    final subcasteIsNew = _subcasteId == null &&
        typedSubcaste.isNotEmpty &&
        !subcasteOptions.any((s) => s.name.toLowerCase() == typedSubcaste.toLowerCase());

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEdit ? S.editProfileTitle : S.newProfile)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              if (_aiEnabled) ...[
                _AiBanner(busy: _aiBusy, onTap: _fillFromBiodata),
                if (_lastParse != null && _lastParse!.warnings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _WarningList(warnings: _lastParse!.warnings),
                ],
                const SizedBox(height: 20),
              ],
              const SectionHeader(S.photos),
              _PhotoStrip(
                existing: _existingPhotos,
                added: _newPhotos,
                onAdd: _pickPhotos,
                onRemoveExisting: _deleteExistingPhoto,
                onRemoveNew: (f) => setState(() => _newPhotos.remove(f)),
              ),
              const SizedBox(height: 24),
              const SectionHeader(S.basicDetails),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: S.fullName,
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the full name' : null,
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
              _TapField(
                label: S.dob,
                icon: Icons.cake_rounded,
                value: _dob == null ? null : formatDate(_dob),
                hint: 'Select date',
                onTap: _pickDob,
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
                      value: _heightCm == null
                          ? null
                          : '${Profile.feetInches(_heightCm!)} ($_heightCm cm)',
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
                onChanged: (v) => setState(() => _complexionId = v),
              ),
              const SizedBox(height: 16),
              _MasterDropdown(
                label: S.nationality,
                icon: Icons.flag_outlined,
                items: masters.countries,
                value: _nationalityId,
                helper: _hint('nationality'),
                onChanged: (v) => setState(() => _nationalityId = v),
              ),
              const SizedBox(height: 16),
              _MasterDropdown(
                label: S.community,
                icon: Icons.groups_rounded,
                items: allowedCommunities,
                value: _communityId,
                helper: _hint('community'),
                onChanged: (v) => setState(() {
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
                onSelected: (s) => setState(() {
                  _subcasteId = s.id;
                  _subcaste.text = s.name;
                }),
                onTyped: (_) => setState(() => _subcasteId = null),
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
              _MasterDropdown(
                label: S.maritalStatus,
                icon: Icons.favorite_border_rounded,
                items: masters.maritalStatuses,
                value: _maritalStatusId,
                helper: _hint('marital_status'),
                onChanged: (v) => setState(() => _maritalStatusId = v),
              ),
              const SizedBox(height: 16),
              _MasterDropdown(
                label: S.religion,
                icon: Icons.temple_hindu_rounded,
                items: masters.religions,
                value: _religionId,
                helper: _hint('religion'),
                onChanged: (v) => setState(() => _religionId = v),
              ),
              const SizedBox(height: 16),
              _MasterDropdown(
                label: S.motherTongue,
                icon: Icons.record_voice_over_outlined,
                items: masters.languages,
                value: _motherTongueId,
                helper: _hint('mother_tongue'),
                onChanged: (v) => setState(() => _motherTongueId = v),
              ),
              const SizedBox(height: 16),
              _LanguageChips(
                items: masters.languages,
                selected: _languageIds,
                helper: _hint('known_languages'),
                onToggle: (id) => setState(() {
                  _languageIds.contains(id) ? _languageIds.remove(id) : _languageIds.add(id);
                }),
              ),
              const SizedBox(height: 16),
              _MasterDropdown(
                label: S.foodHabit,
                icon: Icons.restaurant_rounded,
                items: masters.foodHabits,
                value: _foodHabitId,
                helper: _hint('food_habit'),
                onChanged: (v) => setState(() => _foodHabitId = v),
              ),
              const SizedBox(height: 24),
              const SectionHeader(S.education),
              _MasterDropdown(
                label: S.education,
                icon: Icons.school_rounded,
                items: masters.educations,
                value: _educationId,
                helper: _hint('education'),
                onChanged: (v) => setState(() => _educationId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _eduDetails,
                maxLines: 2,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: S.educationDetails,
                  hintText: 'Branch, college, year — e.g. CSE, JNTU Hyderabad, 2018',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              // The registration form's education table (SPEC §9.7): five
              // fixed levels, each with free text and the country studied in.
              const SectionHeader(S.educationLevels),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4),
                child: Text(
                  _hint('education_levels') == null
                      ? S.educationLevelsHint
                      : '${S.aiUnmatchedPrefix}${_hint('education_levels')}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              for (final level in EducationLevel.levels) ...[
                _EducationLevelRow(
                  level: level,
                  controller: _eduLevelDetails[level]!,
                  countries: masters.countries,
                  countryId: _eduLevelCountry[level],
                  onCountryChanged: (v) => setState(() => _eduLevelCountry[level] = v),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              const SectionHeader(S.profession),
              _MasterDropdown(
                label: S.profession,
                icon: Icons.work_outline_rounded,
                items: masters.professions,
                value: _professionId,
                helper: _hint('profession'),
                onChanged: (v) => setState(() => _professionId = v),
              ),
              const SizedBox(height: 16),
              _MasterDropdown(
                label: S.occupationType,
                icon: Icons.badge_outlined,
                items: masters.occupationTypes,
                value: _occupationTypeId,
                helper: _hint('occupation_type'),
                onChanged: (v) => setState(() => _occupationTypeId = v),
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
              // Public coarse location (SPEC §9.8) — the exact work place is
              // in the personal-details block below.
              _MasterDropdown(
                label: S.workCountry,
                icon: Icons.public_rounded,
                items: masters.countries,
                value: _workCountryId,
                helper: _hint('work_country'),
                helperText: S.workCountryHint,
                onChanged: (v) => setState(() => _workCountryId = v),
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 8),
              const SectionHeader(S.nri),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('NRI — lives or works abroad'),
                subtitle: _hint('nri_country') == null
                    ? null
                    : Text('${S.aiUnmatchedPrefix}${_hint('nri_country')}'),
                value: _isNri,
                onChanged: (v) => setState(() => _isNri = v ?? false),
              ),
              if (_isNri) ...[
                const SizedBox(height: 8),
                // The country is public; the exact place abroad is protected
                // and lives in the personal-details block below.
                _MasterDropdown(
                  label: S.nriCountry,
                  icon: Icons.public_rounded,
                  items: masters.countries,
                  value: _nriCountryId,
                  onChanged: (v) => setState(() => _nriCountryId = v),
                ),
              ],
              const SizedBox(height: 24),
              const SectionHeader(S.horoscope),
              _MasterDropdown(
                label: S.nakshatram,
                icon: Icons.auto_awesome_rounded,
                items: masters.nakshatrams,
                value: _nakshatramId,
                helper: _hint('nakshatram'),
                onChanged: (v) => setState(() => _nakshatramId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: masters.zodiacSigns.any((z) => z.id == _zodiacId) ? _zodiacId : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: S.rasi,
                  prefixIcon: const Icon(Icons.brightness_5_rounded),
                  helperText: _hint('zodiac') == null ? null : '${S.aiUnmatchedPrefix}${_hint('zodiac')}',
                  helperMaxLines: 2,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final z in masters.zodiacSigns)
                    DropdownMenuItem(value: z.id, child: Text(z.label)),
                ],
                onChanged: (v) => setState(() => _zodiacId = v),
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
                            '${S.aiUnmatchedPrefix}${_hint('birth_time')}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                        )
                      else
                        const Spacer(),
                      if (_birthTime != null)
                        TextButton(
                          onPressed: () => setState(() => _birthTime = null),
                          child: const Text('Clear time'),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              const SectionHeader(S.about),
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
              // ---------------------------------------------------------------
              // Everything from here to the status chips is PROTECTED ("on
              // request", SPEC §9.8): native place, birth place, work place,
              // NRI place, parents, contact person, siblings, property, family.
              const SizedBox(height: 8),
              const SectionHeader(S.personalDetailsTitle),
              Container(
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
                      child: Text(
                        S.personalDetailsNote,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Native place — protected, so it lives here rather than under Details.
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _city,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: '${S.nativePlace} — ${S.city}',
                        prefixIcon: Icon(Icons.home_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _state,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'State'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Birth place / state / country — protected since v2.1.
              TextFormField(
                controller: _birthPlace,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: S.birthPlace,
                  hintText: 'Town / city of birth',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  helperText: _hint('birth_place') == null
                      ? S.birthPlaceProtectedHint
                      : '${S.aiUnmatchedPrefix}${_hint('birth_place')}',
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
                onChanged: (v) => setState(() => _birthCountryId = v),
              ),
              const SizedBox(height: 16),
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
              if (_isNri) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nriPlace,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: S.nriPlace,
                    hintText: 'e.g. New Jersey, Dubai, Melbourne',
                    prefixIcon: Icon(Icons.flight_takeoff_rounded),
                  ),
                ),
              ],
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
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
                  helperText: _hint('contact_phone') == null
                      ? null
                      : '${S.aiUnmatchedPrefix}${_hint('contact_phone')}',
                ),
              ),
              const SizedBox(height: 20),
              // Siblings — protected since v2.1 (SPEC §9.8).
              const SectionHeader(S.siblings),
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
                // The registration form's breakdown; the total below may be
                // left blank, in which case it is the sum of these four.
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
              const SizedBox(height: 20),
              // Property — protected (SPEC §9.8).
              const SectionHeader(S.property),
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
              const SizedBox(height: 12),
              // Family background — protected since v2.1.
              const SectionHeader(S.familyDetails),
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
              if (widget.isEdit) ...[
                const SizedBox(height: 24),
                const SectionHeader(S.profileStatus),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in ProfileStatus.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: _status == s.apiValue,
                        onSelected: (_) => setState(() => _status = s.apiValue),
                      ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text(S.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
  });

  final List<ProfilePhoto> existing;
  final List<XFile> added;
  final VoidCallback onAdd;
  final ValueChanged<ProfilePhoto> onRemoveExisting;
  final ValueChanged<XFile> onRemoveNew;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final theme = Theme.of(context);

    Widget tile(Widget child, VoidCallback onRemove) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 100, height: 100, child: child),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: IconButton(
                icon: const CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close_rounded, size: 15, color: Colors.white),
                ),
                onPressed: onRemove,
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
            tile(Image.file(File(file.path), fit: BoxFit.cover), () => onRemoveNew(file)),
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
        for (final item in items) DropdownMenuItem(value: item.id, child: Text(item.name)),
      ],
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

class _TapField extends StatelessWidget {
  const _TapField({
    required this.label,
    required this.icon,
    required this.value,
    required this.hint,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String? value;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        child: Text(
          value ?? hint,
          style: TextStyle(color: value == null ? theme.colorScheme.outline : null),
        ),
      ),
    );
  }
}
