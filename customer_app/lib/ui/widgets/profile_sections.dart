import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../strings.dart';
import '../theme.dart';
import 'common.dart';

/// The parts of a profile page shared by the Browse detail screen and the
/// customer's own profile view (SPEC §9.11 Gandharva 3 and 5): the chip row,
/// the at-a-glance tiles, the public cards (Personal / Education & career /
/// Horoscope / About) and the on-request card.
///
/// Nothing here ever mentions the uploader — the API does not send it, and
/// the widgets only read [Profile].

const _brideColor = Color(0xFFC2185B);
const _groomColor = Color(0xFF1565C0);
const _nriColor = Color(0xFF00695C);

/// Gender · age (DOB) · community · NRI chips.
class ProfileChipRow extends StatelessWidget {
  const ProfileChipRow({super.key, required this.profile, this.trailing = const []});

  final Profile profile;

  /// Extra chips appended after the standard ones (e.g. a status chip).
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusChip(
          label: p.genderLabel,
          color: p.isBride ? _brideColor : _groomColor,
          icon: p.isBride ? Icons.female_rounded : Icons.male_rounded,
        ),
        if (p.ageDobLine != null)
          StatusChip(label: p.ageDobLine!, color: AppColors.maroon, icon: Icons.cake_outlined),
        if (p.communityLine != null)
          StatusChip(label: p.communityLine!, color: AppColors.roseDark, icon: Icons.groups_rounded),
        if (p.isNri)
          StatusChip(label: p.nriLabel ?? S.nri, color: _nriColor, icon: Icons.public_rounded),
        ...trailing,
      ],
    );
  }
}

/// The six most useful facts as a two-column tile grid.
class ProfileFactGrid extends StatelessWidget {
  const ProfileFactGrid({super.key, required this.profile});

  final Profile profile;

  List<(IconData, String, String)> _facts(Profile p) {
    final all = <(IconData, String, String)>[
      if (p.heightLabel != null) (Icons.straighten_rounded, S.height, p.heightLabel!),
      if (p.education != null) (Icons.school_rounded, S.education, p.education!.name),
      if (p.profession != null) (Icons.work_outline_rounded, S.profession, p.profession!.name),
      if (p.religion != null) (Icons.temple_hindu_rounded, S.religion, p.religion!.name),
      if (p.motherTongue != null) (Icons.translate_rounded, S.motherTongue, p.motherTongue!.name),
      if (p.foodHabit != null) (Icons.restaurant_rounded, S.foodHabit, p.foodHabit!.name),
      if (p.maritalStatus != null)
        (Icons.favorite_border_rounded, S.maritalStatus, p.maritalStatus!.name),
      if (p.placeLine != null) (Icons.public_rounded, S.worksIn, p.placeLine!),
      if (p.starRasi != null) (Icons.auto_awesome_rounded, S.starRasi, p.starRasi!),
    ];
    return all.take(6).toList();
  }

  @override
  Widget build(BuildContext context) {
    final facts = _facts(profile);
    if (facts.isEmpty) return const SizedBox.shrink();
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.4,
      children: [for (final f in facts) FactTile(icon: f.$1, label: f.$2, value: f.$3)],
    );
  }
}

/// Personal · Education & career · Horoscope · About — the "before approval"
/// sheet (SPEC §9.8). Sections with nothing recorded are skipped.
class ProfilePublicCards extends StatelessWidget {
  const ProfilePublicCards({super.key, required this.profile});

  final Profile profile;

  static bool _has(String? s) => s != null && s.isNotEmpty;

  /// "B.Tech CSE (India)" — details and the country studied in; a dash when
  /// the row was saved with neither.
  static String _levelValue(EducationLevelEntry lv) {
    final parts = [lv.details, lv.country == null ? null : '(${lv.country!.name})'].where(_has);
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final theme = Theme.of(context);

    final personal = <Widget>[
      if (p.maritalStatus != null) DetailRow(label: S.maritalStatus, value: p.maritalStatus!.name),
      if (p.ageDobLine != null) DetailRow(label: S.age, value: p.ageDobLine!),
      if (p.birthTimeLabel != null) DetailRow(label: S.birthTime, value: p.birthTimeLabel!),
      if (p.religion != null) DetailRow(label: S.religion, value: p.religion!.name),
      if (p.community != null) DetailRow(label: S.community, value: p.community!.name),
      if (p.subcaste != null) DetailRow(label: S.subcaste, value: p.subcaste!.name),
      if (_has(p.gothram)) DetailRow(label: S.gothram, value: p.gothram!),
      if (p.motherTongue != null) DetailRow(label: S.motherTongue, value: p.motherTongue!.name),
      if (p.knownLanguagesLabel != null)
        DetailRow(label: S.knownLanguages, value: p.knownLanguagesLabel!),
      if (p.complexion != null) DetailRow(label: S.complexion, value: p.complexion!.name),
      if (p.foodHabit != null) DetailRow(label: S.foodHabit, value: p.foodHabit!.name),
      if (p.heightLabel != null) DetailRow(label: S.height, value: p.heightLabel!),
      if (p.weightLabel != null) DetailRow(label: S.weight, value: p.weightLabel!),
      if (p.nationality != null) DetailRow(label: S.nationality, value: p.nationality!.name),
    ];

    final career = <Widget>[
      if (p.education != null) DetailRow(label: S.highestQualification, value: p.education!.name),
      // The education table (SPEC §9.7): one row per filled level.
      for (final lv in p.educationLevels) DetailRow(label: lv.level.label, value: _levelValue(lv)),
      if (_has(p.educationDetails)) DetailRow(label: S.educationDetails, value: p.educationDetails!),
      if (p.profession != null) DetailRow(label: S.profession, value: p.profession!.name),
      if (p.occupationType != null) DetailRow(label: S.occupationType, value: p.occupationType!.name),
      if (_has(p.professionDetails))
        DetailRow(label: S.professionDetails, value: p.professionDetails!),
      // Public coarse location only (SPEC §9.8): the work country / NRI country.
      if (p.workCountry != null) DetailRow(label: S.worksIn, value: p.workCountry!.name),
      if (p.nriLabel != null) DetailRow(label: S.nri, value: p.nriLabel!),
      if (_has(p.incomeText)) DetailRow(label: S.income, value: p.incomeText!),
      if (_has(p.otherIncome)) DetailRow(label: S.otherIncome, value: p.otherIncome!),
    ];

    final horoscope = <Widget>[
      if (p.nakshatram != null) DetailRow(label: S.nakshatram, value: p.nakshatram!.name),
      if (p.zodiac != null) DetailRow(label: S.rasi, value: p.zodiac!.label),
      if (p.dobLabel != null) DetailRow(label: S.dob, value: p.dobLabel!),
      if (p.birthTimeLabel != null) DetailRow(label: S.birthTime, value: p.birthTimeLabel!),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (personal.isNotEmpty) ...[
          const SectionHeader(S.personal),
          SurfaceCard(child: Column(children: personal)),
          const SizedBox(height: 16),
        ],
        if (career.isNotEmpty) ...[
          const SectionHeader(S.educationCareer),
          SurfaceCard(child: Column(children: career)),
          const SizedBox(height: 16),
        ],
        if (p.nakshatram != null || p.zodiac != null || p.birthTimeLabel != null) ...[
          const SectionHeader(S.horoscope),
          SurfaceCard(child: Column(children: horoscope)),
          const SizedBox(height: 16),
        ],
        if (_has(p.about)) ...[
          const SectionHeader(S.about),
          SurfaceCard(
            child: Text(p.about!, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

/// The on-request block (SPEC §9.8): birth place, work place, place abroad,
/// parents with occupations and phones, contact person, siblings, family,
/// property, native place. Shown for my own profile and while an accepted
/// interest is live — the server omits these fields otherwise.
class SharedDetailsCard extends StatelessWidget {
  const SharedDetailsCard({super.key, required this.profile, this.daysLeft, this.own = false});

  final Profile profile;

  /// Days of access left (another family's profile); null for my own.
  final int? daysLeft;

  /// My own profile — no countdown, a note on who sees this instead.
  final bool own;

  static bool _has(String? s) => s != null && s.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = daysLeft;

    return SurfaceCard(
      color: AppColors.roseLight.withValues(alpha: 0.45),
      borderColor: AppColors.roseGold.withValues(alpha: 0.6),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_open_rounded, size: 18, color: AppColors.maroon),
              const SizedBox(width: 8),
              Expanded(child: Text(S.sharedDetailsTitle, style: theme.textTheme.titleSmall)),
              if (!own && days != null)
                StatusChip(
                  label: days <= 0 ? S.interestStatusLabel('expired') : S.daysLeft(days),
                  color: days <= 3 ? AppColors.warning : AppColors.success,
                  icon: Icons.schedule_rounded,
                ),
            ],
          ),
          if (own) ...[
            const SizedBox(height: 6),
            Text(
              S.sharedOnlyAfterApproval,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          if (p.birthPlaceLine != null) DetailRow(label: S.birthPlace, value: p.birthPlaceLine!),
          if (_has(p.workPlace)) DetailRow(label: S.workPlace, value: p.workPlace!),
          if (_has(p.nriPlace)) DetailRow(label: S.nriPlace, value: p.nriPlace!),
          if (_has(p.fatherName)) DetailRow(label: S.fatherName, value: p.fatherName!),
          if (_has(p.fatherOccupation))
            DetailRow(label: S.fatherOccupation, value: p.fatherOccupation!),
          if (_has(p.fatherPhone)) PhoneRow(label: S.fatherPhone, phone: p.fatherPhone!),
          if (_has(p.motherName)) DetailRow(label: S.motherName, value: p.motherName!),
          if (_has(p.motherOccupation))
            DetailRow(label: S.motherOccupation, value: p.motherOccupation!),
          if (_has(p.motherPhone)) PhoneRow(label: S.motherPhone, phone: p.motherPhone!),
          if (_has(p.contactName)) DetailRow(label: S.contactPersonName, value: p.contactName!),
          if (_has(p.contactPhone)) PhoneRow(label: S.contactPersonPhone, phone: p.contactPhone!),
          // Siblings: the breakdown when recorded, else the plain count.
          if (p.siblingsBreakdown != null)
            DetailRow(label: S.siblings, value: p.siblingsBreakdown!)
          else if (p.siblingsLabel != null)
            DetailRow(label: S.siblings, value: p.siblingsLabel!),
          if (_has(p.siblingsDetails))
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
              child: Text(p.siblingsDetails!, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
            ),
          if (_has(p.familyDetails)) ...[
            const SizedBox(height: 6),
            Text(S.familyDetails, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline)),
            const SizedBox(height: 4),
            Text(p.familyDetails!, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
            const SizedBox(height: 8),
          ],
          if (_has(p.propertyShare)) DetailRow(label: S.propertyShare, value: p.propertyShare!),
          if (_has(p.propertyDetails)) DetailRow(label: S.propertyDetails, value: p.propertyDetails!),
          if (p.nativePlace != null) DetailRow(label: S.nativePlace, value: p.nativePlace!),
          if (!p.hasPersonalDetails)
            Text(S.noPersonalDetails, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline)),
        ],
      ),
    );
  }
}
