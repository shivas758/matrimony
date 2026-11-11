import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/state/profile_form_logic.dart';

/// The pure logic behind the four-step profile form (SPEC §9.18 F) and its
/// Privacy card (§9.18 D / E).
void main() {
  group('ProfileFormStep', () {
    test('four steps in the SPEC order, with their titles', () {
      expect(ProfileFormStep.values.map((s) => s.title), [
        'Personal details',
        'Professional details',
        'Horoscope',
        'Family & contact',
      ]);
      expect(ProfileFormStep.personal.position, 'Step 1 of 4');
      expect(ProfileFormStep.family.position, 'Step 4 of 4');
      // The header labels are the same words, broken for a narrow phone.
      for (final s in ProfileFormStep.values) {
        expect(s.shortLabel.replaceAll('\n', ' '), s.title);
      }
    });

    test('next / previous walk the steps and stop at the ends', () {
      expect(ProfileFormStep.personal.isFirst, isTrue);
      expect(ProfileFormStep.personal.previous, isNull);
      expect(ProfileFormStep.personal.next, ProfileFormStep.professional);
      expect(ProfileFormStep.professional.next, ProfileFormStep.horoscope);
      expect(ProfileFormStep.horoscope.previous, ProfileFormStep.professional);
      expect(ProfileFormStep.family.isLast, isTrue);
      expect(ProfileFormStep.family.next, isNull);
      expect(ProfileFormStep.family.previous, ProfileFormStep.horoscope);
    });

    test('the four required fields are all on step 1', () {
      for (final key in ProfileFormStep.requiredFields) {
        expect(ProfileFormStep.forField(key), ProfileFormStep.personal, reason: key);
      }
    });

    test('every write-body key belongs to the step SPEC §9.18 F puts it on', () {
      const expected = <ProfileFormStep, List<String>>{
        ProfileFormStep.personal: [
          'full_name', 'gender', 'dob', 'marital_status_id', 'religion_id', 'community_id',
          'subcaste_id', 'subcaste_name', 'mother_tongue_id', 'known_language_ids', 'height_cm',
          'weight_kg', 'complexion_id', 'food_habit_id', 'nationality_id', 'about', 'photos',
        ],
        ProfileFormStep.professional: [
          'education_levels', 'education_id', 'education_details', 'occupation_type_id',
          'profession_id', 'profession_details', 'income_text', 'other_income',
          'work_country_id', 'work_place', 'is_nri', 'nri_country_id', 'nri_place',
        ],
        ProfileFormStep.horoscope: [
          'nakshatram_id', 'zodiac_id', 'gothram', 'birth_time', 'birth_place', 'birth_state',
          'birth_country_id',
        ],
        ProfileFormStep.family: [
          'father_name', 'father_occupation', 'father_phone', 'mother_name',
          'mother_occupation', 'mother_phone', 'has_siblings', 'siblings_count',
          'siblings_details', 'elder_sisters', 'younger_sisters', 'elder_brothers',
          'younger_brothers', 'family_details', 'property_share', 'property_details', 'city',
          'state', 'contact_name', 'contact_phone', 'status', 'hidden_fields', 'audience_all',
          'audience_community_ids',
        ],
      };
      expected.forEach((step, keys) {
        for (final key in keys) {
          expect(ProfileFormStep.forField(key), step, reason: key);
        }
      });
    });

    test('AI-import hint keys (no _id) and nested error paths resolve too', () {
      expect(ProfileFormStep.forField('community'), ProfileFormStep.personal);
      expect(ProfileFormStep.forField('known_languages'), ProfileFormStep.personal);
      expect(ProfileFormStep.forField('occupation_type'), ProfileFormStep.professional);
      expect(ProfileFormStep.forField('nri_country'), ProfileFormStep.professional);
      expect(ProfileFormStep.forField('zodiac'), ProfileFormStep.horoscope);
      expect(ProfileFormStep.forField('birth_country'), ProfileFormStep.horoscope);
      expect(ProfileFormStep.forField('education_levels[2].details'), ProfileFormStep.professional);
      expect(ProfileFormStep.forField('education_levels.0.country_id'), ProfileFormStep.professional);
      expect(ProfileFormStep.forField(' Father_Phone '), ProfileFormStep.family);
    });

    test('unknown keys belong to no step', () {
      expect(ProfileFormStep.forField(null), isNull);
      expect(ProfileFormStep.forField(''), isNull);
      expect(ProfileFormStep.forField('uploaded_by'), isNull);
      expect(ProfileFormStep.forField('123'), isNull);
    });

    test('firstFor picks the earliest step; stepsFor lists them in order', () {
      expect(
        ProfileFormStep.firstFor(['contact_phone', 'zodiac_id', 'income_text']),
        ProfileFormStep.professional,
      );
      expect(ProfileFormStep.firstFor(['father_phone']), ProfileFormStep.family);
      expect(ProfileFormStep.firstFor(['nonsense']), isNull);
      expect(ProfileFormStep.firstFor(const []), isNull);
      expect(
        ProfileFormStep.stepsFor(['mother_phone', 'nakshatram', 'father_phone', 'bogus']),
        [ProfileFormStep.horoscope, ProfileFormStep.family],
      );
    });
  });

  group('ProfilePrivacy — hidden fields ↔ switches', () {
    const known = ['name', 'dob', 'community', 'subcaste', 'income', 'star_rasi'];

    test('default: everything shown, own community only', () {
      const p = ProfilePrivacy();
      for (final key in known) {
        expect(p.isShown(key), isTrue, reason: key);
      }
      expect(p.hiddenKeys(known), isEmpty);
      expect(p.mode, AudienceMode.own);
      expect(p.audienceAll, isFalse);
      expect(p.audienceIds(), isEmpty);
    });

    test('switching a detail off and on again', () {
      final off = const ProfilePrivacy().withShown('income', false);
      expect(off.isShown('income'), isFalse);
      expect(off.isHidden('income'), isTrue);
      expect(off.hiddenKeys(known), ['income']);
      expect(off.hiddenCount(known), 1);
      final on = off.withShown('income', true);
      expect(on.isShown('income'), isTrue);
      expect(on.hiddenKeys(known), isEmpty);
    });

    test('the value is immutable — a change returns a new one', () {
      const a = ProfilePrivacy();
      final b = a.withShown('name', false);
      expect(a.isShown('name'), isTrue);
      expect(b.isShown('name'), isFalse);
    });

    test('turning community off also turns subcaste off and locks it', () {
      final p = const ProfilePrivacy().withShown('community', false);
      expect(p.isShown('community'), isFalse);
      expect(p.isShown('subcaste'), isFalse);
      expect(p.isLocked('subcaste'), isTrue);
      expect(p.isLocked('community'), isFalse);
      expect(p.hiddenKeys(known), ['community', 'subcaste']);
      // The locked switch does not move.
      expect(p.withShown('subcaste', true).isShown('subcaste'), isFalse);
    });

    test('turning community back on gives subcaste its own setting back', () {
      final untouched = const ProfilePrivacy().withShown('community', false).withShown('community', true);
      expect(untouched.isShown('subcaste'), isTrue);
      expect(untouched.isLocked('subcaste'), isFalse);

      final wasOff = const ProfilePrivacy()
          .withShown('subcaste', false)
          .withShown('community', false)
          .withShown('community', true);
      expect(wasOff.isShown('community'), isTrue);
      expect(wasOff.isShown('subcaste'), isFalse, reason: 'it was off on its own');
    });

    test('subcaste can be hidden alone', () {
      final p = const ProfilePrivacy().withShown('subcaste', false);
      expect(p.isShown('community'), isTrue);
      expect(p.isLocked('subcaste'), isFalse);
      expect(p.hiddenKeys(known), ['subcaste']);
    });

    test('hiddenKeys follows the served order and drops keys the server does not know', () {
      final p = ProfilePrivacy.fromServer(hiddenFields: ['star_rasi', 'legacy_key', 'name']);
      expect(p.hiddenKeys(known), ['name', 'star_rasi']);
      expect(p.hiddenKeys(const []), isEmpty);
    });

    test('pre-fill from the server: hidden_fields and the three audiences', () {
      final own = ProfilePrivacy.fromServer(hiddenFields: ['dob']);
      expect(own.mode, AudienceMode.own);
      expect(own.isShown('dob'), isFalse);
      expect(own.isShown('name'), isTrue);

      final selected = ProfilePrivacy.fromServer(audienceCommunityIds: [5, 2]);
      expect(selected.mode, AudienceMode.selected);
      expect(selected.communityIds, {2, 5});

      final all = ProfilePrivacy.fromServer(audienceAll: true, audienceCommunityIds: [2]);
      expect(all.mode, AudienceMode.all);
      expect(all.audienceAll, isTrue);

      // The owner side of an older server sends nothing.
      final none = ProfilePrivacy.fromServer();
      expect(none.hidden, isEmpty);
      expect(none.mode, AudienceMode.own);
    });

    test('audience ids travel only for "selected", sorted, without the own community', () {
      final p = const ProfilePrivacy()
          .withMode(AudienceMode.selected)
          .withCommunity(7, true)
          .withCommunity(3, true)
          .withCommunity(1, true);
      expect(p.audienceIds(ownCommunityId: 1), [3, 7]);
      expect(p.audienceIds(), [1, 3, 7]);
      expect(p.withCommunity(7, false).audienceIds(ownCommunityId: 1), [3]);

      // Another mode sends none — but the picks are kept for switching back.
      final asAll = p.withMode(AudienceMode.all);
      expect(asAll.audienceAll, isTrue);
      expect(asAll.audienceIds(ownCommunityId: 1), isEmpty);
      expect(asAll.withMode(AudienceMode.selected).audienceIds(ownCommunityId: 1), [3, 7]);
      expect(p.withMode(AudienceMode.own).audienceIds(), isEmpty);
    });

    test('PATCH body: real JSON values', () {
      final p = const ProfilePrivacy()
          .withShown('community', false)
          .withShown('income', false)
          .withMode(AudienceMode.selected)
          .withCommunity(4, true);
      expect(p.toJsonFields(known, ownCommunityId: 1), {
        'hidden_fields': ['community', 'subcaste', 'income'],
        'audience_all': false,
        'audience_community_ids': [4],
      });
      expect(const ProfilePrivacy().toJsonFields(known), {
        'hidden_fields': <String>[],
        'audience_all': false,
        'audience_community_ids': <int>[],
      });
    });

    test('multipart POST fields: JSON array strings and true / false', () {
      final p = const ProfilePrivacy().withShown('name', false).withMode(AudienceMode.all);
      final fields = p.toMultipartFields(known, ownCommunityId: 1);
      expect(fields['hidden_fields'], '["name"]');
      expect(jsonDecode(fields['hidden_fields']!), ['name']);
      expect(fields['audience_all'], 'true');
      expect(fields['audience_community_ids'], '[]');

      // "Show everything" is sent explicitly, not left out.
      final plain = const ProfilePrivacy().toMultipartFields(known);
      expect(plain, {
        'hidden_fields': '[]',
        'audience_all': 'false',
        'audience_community_ids': '[]',
      });
    });
  });
}
