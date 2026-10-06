import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/contact_request.dart';
import 'package:matrimony_agents/models/hold_request.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/models/parsed_profile.dart';
import 'package:matrimony_agents/models/profile.dart';
import 'package:matrimony_agents/state/profile_filters.dart';

void main() {
  group('ProfileFilters', () {
    test('default filters send no narrowing params', () {
      final q = ProfileFilters.empty.toQuery();
      expect(q.containsKey('gender'), isFalse);
      expect(q.containsKey('age_min'), isFalse, reason: 'default age range is not a filter');
      expect(q.containsKey('age_max'), isFalse);
      expect(q.containsKey('height_min'), isFalse, reason: 'default height range is not a filter');
      expect(q.containsKey('height_max'), isFalse);
      expect(q.containsKey('nri'), isFalse);
      expect(q.containsKey('country_id'), isFalse);
      expect(q.containsKey('occupation_type_id'), isFalse);
      expect(q.containsKey('work_country_id'), isFalse);
      expect(q['page'], 1);
      expect(q['sort'], 'newest');
    });

    test('multi-selects serialise as comma-separated ids', () {
      const f = ProfileFilters(communityIds: {3, 1}, educationIds: {7}, complexionIds: {2, 4});
      final q = f.toQuery();
      expect((q['community_id'] as String).split(',').toSet(), {'3', '1'});
      expect(q['education_id'], '7');
      expect((q['complexion_id'] as String).split(',').toSet(), {'2', '4'});
    });

    test('subcaste ids serialise, count as a filter, and survive presets', () {
      const f = ProfileFilters(communityIds: {1}, subcasteIds: {5, 9});
      expect((f.toQuery()['subcaste_id'] as String).split(',').toSet(), {'5', '9'});
      expect(f.activeCount, 2);
      final back = ProfileFilters.decode(f.encode());
      expect(back.subcasteIds, {5, 9});
      expect(ProfileFilters.empty.toQuery().containsKey('subcaste_id'), isFalse);
    });

    test('religion, mother tongue, languages and food habit serialise and round-trip', () {
      const f = ProfileFilters(religionIds: {1}, motherTongueIds: {2, 3}, languageIds: {3}, foodHabitIds: {4});
      final q = f.toQuery();
      expect(q['religion_id'], '1');
      expect((q['mother_tongue_id'] as String).split(',').toSet(), {'2', '3'});
      expect(q['language_id'], '3');
      expect(q['food_habit_id'], '4');
      expect(f.activeCount, 4);
      final back = ProfileFilters.decode(f.encode());
      expect(back.religionIds, {1});
      expect(back.motherTongueIds, {2, 3});
      expect(back.languageIds, {3});
      expect(back.foodHabitIds, {4});
      expect(ProfileFilters.empty.toQuery().containsKey('religion_id'), isFalse);
    });

    test('occupation type and work country (v2.1) serialise, count and round-trip', () {
      const f = ProfileFilters(occupationTypeIds: {2, 5}, workCountryIds: {1});
      final q = f.toQuery();
      expect((q['occupation_type_id'] as String).split(',').toSet(), {'2', '5'});
      expect(q['work_country_id'], '1');
      expect(f.activeCount, 2);
      final back = ProfileFilters.decode(f.encode());
      expect(back.occupationTypeIds, {2, 5});
      expect(back.workCountryIds, {1});
      // copyWith keeps them like every other set.
      expect(f.copyWith(gender: 'bride').occupationTypeIds, {2, 5});
      expect(f.copyWith(workCountryIds: const {}).workCountryIds, isEmpty);
      // Work country is independent of the NRI switch.
      expect(q.containsKey('nri'), isFalse);
    });

    test('age range only travels when moved off the default', () {
      final q = const ProfileFilters(ageMin: 24, ageMax: 32).toQuery();
      expect(q['age_min'], 24);
      expect(q['age_max'], 32);
    });

    test('height range travels in cm, each end only when moved', () {
      final q = const ProfileFilters(heightMin: 160).toQuery();
      expect(q['height_min'], 160);
      expect(q.containsKey('height_max'), isFalse);
      expect(const ProfileFilters(heightMin: 160, heightMax: 175).activeCount, 1);
    });

    test('NRI filter: switch alone, or one or many countries', () {
      expect(const ProfileFilters(nriOnly: true).toQuery()['nri'], 'true');
      final many = const ProfileFilters(nriOnly: true, countryIds: {4, 7}).toQuery();
      expect(many['nri'], 'true');
      expect((many['country_id'] as String).split(',').toSet(), {'4', '7'});
      // Picking countries implies NRI even if the switch flag was not set.
      expect(const ProfileFilters(countryIds: {4}).toQuery()['nri'], 'true');
      // The NRI switch and its countries count as one filter chip.
      expect(const ProfileFilters(nriOnly: true, countryIds: {4, 7}).activeCount, 1);
    });

    test('activeCount reflects what the agent actually set', () {
      expect(ProfileFilters.empty.activeCount, 0);
      expect(const ProfileFilters(gender: 'bride').activeCount, 1);
      expect(
        const ProfileFilters(gender: 'bride', ageMin: 25, communityIds: {1}, city: 'Hyderabad')
            .activeCount,
        4,
      );
      // A search term is not a filter chip.
      expect(const ProfileFilters(query: 'Priya').activeCount, 0);
    });

    test('clearedFilters keeps the search text and sort', () {
      const f = ProfileFilters(
        gender: 'groom',
        communityIds: {2},
        occupationTypeIds: {1},
        workCountryIds: {3},
        query: 'ravi',
        sort: 'name',
      );
      final cleared = f.clearedFilters();
      expect(cleared.activeCount, 0);
      expect(cleared.occupationTypeIds, isEmpty);
      expect(cleared.workCountryIds, isEmpty);
      expect(cleared.query, 'ravi');
      expect(cleared.sort, 'name');
    });

    test('presets survive a JSON round trip', () {
      const f = ProfileFilters(
        gender: 'bride',
        ageMin: 22,
        ageMax: 29,
        heightMin: 150,
        heightMax: 165,
        communityIds: {1, 4},
        complexionIds: {2},
        nakshatramIds: {9},
        nriOnly: true,
        countryIds: {3},
        city: 'Warangal',
        sort: 'age_asc',
      );
      final back = ProfileFilters.decode(f.encode());
      expect(back.gender, 'bride');
      expect(back.ageMin, 22);
      expect(back.ageMax, 29);
      expect(back.heightMin, 150);
      expect(back.heightMax, 165);
      expect(back.communityIds, {1, 4});
      expect(back.complexionIds, {2});
      expect(back.nakshatramIds, {9});
      expect(back.nriOnly, isTrue);
      expect(back.countryIds, {3});
      expect(back.city, 'Warangal');
      expect(back.sort, 'age_asc');
    });

    test('old presets without the new keys still decode', () {
      final back = ProfileFilters.decode('{"gender":"groom","community_ids":[2],"sort":"name"}');
      expect(back.gender, 'groom');
      expect(back.isHeightDefault, isTrue);
      expect(back.nriOnly, isFalse);
      expect(back.countryIds, isEmpty);
      // v2.1 keys missing → empty, not an error.
      expect(back.occupationTypeIds, isEmpty);
      expect(back.workCountryIds, isEmpty);
      expect(back.activeCount, 2, reason: 'gender + community; nothing from the missing keys');
    });

    test('copyWith can clear nullable fields', () {
      const f = ProfileFilters(gender: 'bride', city: 'Hyderabad');
      expect(f.copyWith(clearGender: true).gender, isNull);
      expect(f.copyWith(clearCity: true).city, isNull);
      expect(f.copyWith(clearGender: true).city, 'Hyderabad');
    });
  });

  group('MasterData', () {
    test('occupation types load and India is found by name', () {
      final m = MasterData.fromJson({
        'communities': [
          {'id': 1, 'name': 'Kamma'},
        ],
        'professions': [],
        'educations': [],
        'marital_statuses': [],
        'countries': [
          {'id': 1, 'name': 'India'},
          {'id': 2, 'name': 'United States'},
        ],
        'occupation_types': [
          {'id': 3, 'name': 'Private job'},
          {'id': 4, 'name': 'Business'},
        ],
        'zodiac_signs': [],
        'nakshatrams': [],
      });
      expect(m.occupationTypes.length, 2);
      expect(m.occupationTypeName(4), 'Business');
      expect(m.occupationTypeName(99), isNull);
      expect(m.indiaCountryId, 1);
      expect(MasterData.empty.indiaCountryId, isNull);
      expect(MasterData.empty.occupationTypes, isEmpty);
    });
  });

  group('Profile', () {
    Map<String, dynamic> base() => {
          'id': 1,
          'full_name': 'Priya Kumari',
          'gender': 'bride',
          'status': 'active',
          'age': 27,
          'height_cm': 160,
          'weight_kg': 52,
          'gothram': 'Bharadwaja',
          'complexion': {'id': 2, 'name': 'Fair'},
          'community': {'id': 1, 'name': 'Kamma'},
          'education': {'id': 7, 'name': 'B.Tech / B.E.'},
          'education_details': 'CSE, JNTU 2018',
          'nakshatram': {'id': 4, 'name': 'Rohini'},
          'zodiac': {'id': 11, 'english_name': 'Aquarius', 'indian_name': 'Kumbha'},
          'is_nri': false,
          'photos': [],
        };

    test('omitted protected fields stay null and access defaults to none', () {
      final p = Profile.fromJson(base()..['contact_access'] = 'none');
      expect(p.contactAccess, ContactAccess.none);
      expect(p.contactPhone, isNull);
      expect(p.contactName, isNull);
      expect(p.city, isNull, reason: 'native place is protected');
      expect(p.nativePlace, isNull);
      expect(p.fatherPhone, isNull);
      expect(p.motherName, isNull);
      // v2.1: these are protected too and simply absent from the JSON.
      expect(p.workPlace, isNull);
      expect(p.nriPlace, isNull);
      expect(p.birthPlace, isNull);
      expect(p.birthState, isNull);
      expect(p.birthCountry, isNull);
      expect(p.birthPlaceLine, isNull);
      expect(p.fatherOccupation, isNull);
      expect(p.motherOccupation, isNull);
      expect(p.hasSiblings, isNull);
      expect(p.siblingsCount, isNull);
      expect(p.siblingsDetails, isNull);
      expect(p.elderSisters, isNull);
      expect(p.youngerBrothers, isNull);
      expect(p.siblingsLabel, isNull);
      expect(p.siblingsBreakdown, isNull);
      expect(p.familyDetails, isNull);
      expect(p.propertyShare, isNull);
      expect(p.propertyDetails, isNull);
      expect(p.hasContact, isFalse);
      expect(p.hasPersonalDetails, isFalse);
    });

    test('granted access exposes contacts, parents and the native place', () {
      final p = Profile.fromJson(base()
        ..['contact_access'] = 'granted'
        ..['contact_name'] = 'Ramesh Kumar'
        ..['contact_phone'] = '9876543210'
        ..['city'] = 'Nalgonda'
        ..['state'] = 'Telangana'
        ..['father_name'] = 'Ramesh Kumar'
        ..['father_phone'] = '9876543210'
        ..['mother_name'] = 'Sita Kumari'
        ..['contact_expires_at'] =
            DateTime.now().add(const Duration(days: 15)).toUtc().toIso8601String());
      expect(p.contactAccess, ContactAccess.granted);
      expect(p.contactPhone, '9876543210');
      expect(p.nativePlace, 'Nalgonda, Telangana');
      expect(p.fatherName, 'Ramesh Kumar');
      expect(p.motherName, 'Sita Kumari');
      expect(p.hasContact, isTrue);
      expect(p.hasPersonalDetails, isTrue);
      expect(p.contactDaysLeft, inInclusiveRange(14, 15));
    });

    test('granted access parses the v2.1 protected fields and their helpers', () {
      final p = Profile.fromJson(base()
        ..['contact_access'] = 'granted'
        ..['work_place'] = 'Hyderabad'
        ..['birth_place'] = 'Guntur'
        ..['birth_state'] = 'Andhra Pradesh'
        ..['birth_country'] = {'id': 1, 'name': 'India'}
        ..['father_occupation'] = 'Farmer'
        ..['mother_occupation'] = 'Home maker'
        ..['has_siblings'] = true
        ..['siblings_count'] = 3
        ..['siblings_details'] = 'All married'
        ..['elder_sisters'] = 2
        ..['younger_sisters'] = 0
        ..['elder_brothers'] = null
        ..['younger_brothers'] = 1
        ..['family_details'] = 'Joint family'
        ..['property_share'] = 'Equal share'
        ..['property_details'] = '5 acres');
      expect(p.workPlace, 'Hyderabad');
      expect(p.birthPlace, 'Guntur');
      expect(p.birthState, 'Andhra Pradesh');
      expect(p.birthCountry?.name, 'India');
      expect(p.birthPlaceLine, 'Guntur, Andhra Pradesh, India');
      expect(p.fatherOccupation, 'Farmer');
      expect(p.motherOccupation, 'Home maker');
      expect(p.siblingsLabel, '3');
      expect(p.elderSisters, 2);
      expect(p.youngerSisters, 0);
      expect(p.elderBrothers, isNull);
      expect(p.youngerBrothers, 1);
      expect(p.siblingsBreakdown, '2 elder sisters · 1 younger brother');
      expect(p.familyDetails, 'Joint family');
      expect(p.propertyShare, 'Equal share');
      expect(p.propertyDetails, '5 acres');
      expect(p.hasPersonalDetails, isTrue);
    });

    test('hasPersonalDetails covers every protected field on its own', () {
      Profile withField(String key, dynamic value) =>
          Profile.fromJson(base()..['contact_access'] = 'granted'..[key] = value);
      for (final entry in <String, dynamic>{
        'city': 'Nalgonda',
        'birth_place': 'Guntur',
        'birth_state': 'AP',
        'birth_country': {'id': 1, 'name': 'India'},
        'work_place': 'Hyderabad',
        'father_name': 'Ramesh',
        'father_occupation': 'Farmer',
        'father_phone': '9',
        'mother_name': 'Sita',
        'mother_occupation': 'Teacher',
        'mother_phone': '9',
        'contact_name': 'Uncle',
        'contact_phone': '9',
        'has_siblings': false,
        'elder_brothers': 1,
        'siblings_details': 'x',
        'family_details': 'x',
        'property_share': 'x',
        'property_details': 'x',
      }.entries) {
        expect(withField(entry.key, entry.value).hasPersonalDetails, isTrue,
            reason: '${entry.key} alone should count');
      }
      // NRI place only counts for NRI profiles (the server nulls it otherwise).
      expect(withField('nri_place', 'Dubai').hasPersonalDetails, isTrue);
      expect(withField('birth_place', '').hasPersonalDetails, isFalse);
    });

    test('siblings breakdown reads naturally and is null when nothing is above zero', () {
      Profile p(Map<String, dynamic> extra) => Profile.fromJson(base()..addAll(extra));
      expect(p({'has_siblings': true, 'elder_brothers': 1}).siblingsBreakdown, '1 elder brother');
      expect(
        p({'has_siblings': true, 'elder_sisters': 1, 'younger_sisters': 2, 'elder_brothers': 3, 'younger_brothers': 4})
            .siblingsBreakdown,
        '1 elder sister · 2 younger sisters · 3 elder brothers · 4 younger brothers',
      );
      expect(p({'has_siblings': false, 'elder_sisters': 0, 'younger_brothers': 0}).siblingsBreakdown, isNull);
      expect(p({'has_siblings': false}).siblingsLabel, 'None');
      expect(p({'has_siblings': true}).siblingsLabel, 'Yes');
    });

    test('expired approval counts down to zero, never negative', () {
      final p = Profile.fromJson(base()
        ..['contact_access'] = 'none'
        ..['contact_expires_at'] =
            DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String());
      expect(p.contactDaysLeft, 0);
    });

    test('subcaste rides along with the community on cards', () {
      final without = Profile.fromJson(base());
      expect(without.subcaste, isNull);
      expect(without.communityLine, 'Kamma');
      final with_ = Profile.fromJson(base()..['subcaste'] = {'id': 3, 'name': 'Chowdary'});
      expect(with_.subcaste?.name, 'Chowdary');
      expect(with_.communityLine, 'Kamma · Chowdary');
    });

    test('display helpers: height in feet/inches, weight, details, star/rasi', () {
      final p = Profile.fromJson(base());
      expect(Profile.feetInches(160), '5\' 3"');
      expect(p.heightLabel, '5\' 3" (160 cm)');
      expect(p.heightShort, '5\'3"');
      expect(p.weightLabel, '52 kg');
      expect(p.gothram, 'Bharadwaja');
      expect(p.educationLine, 'B.Tech / B.E. — CSE, JNTU 2018');
      expect(p.professionLine, isNull);
      expect(p.starRasi, 'Rohini · Kumbha / Aquarius');
      expect(p.genderLabel, 'Bride');
    });

    test('v2.1 public fields parse: nationality, occupation type, work country, other income', () {
      final p = Profile.fromJson(base()
        ..['nationality'] = {'id': 1, 'name': 'India'}
        ..['occupation_type'] = {'id': 3, 'name': 'Private job'}
        ..['work_country'] = {'id': 2, 'name': 'United States'}
        ..['other_income'] = 'Rent 2 LPA'
        ..['is_customer_profile'] = true);
      expect(p.nationality?.name, 'India');
      expect(p.occupationType?.name, 'Private job');
      expect(p.workCountry?.id, 2);
      expect(p.otherIncome, 'Rent 2 LPA');
      expect(p.isCustomerProfile, isTrue);
      expect(Profile.fromJson(base()).isCustomerProfile, isFalse);
    });

    test('education levels parse in level order with labels and a summary', () {
      final p = Profile.fromJson(base()
        ..['education_levels'] = [
          {'level': 'graduation', 'details': 'B.Tech, JNTU', 'country': {'id': 1, 'name': 'India'}},
          {'level': '10th', 'details': 'ZPHS Guntur', 'country': null},
          {'level': 'post_graduation', 'details': null, 'country': {'id': 2, 'name': 'United States'}},
        ]);
      expect(p.educationLevels.length, 3);
      final grad = p.educationLevels.firstWhere((e) => e.level == 'graduation');
      expect(grad.label, 'Graduation');
      expect(grad.details, 'B.Tech, JNTU');
      expect(grad.country?.name, 'India');
      expect(grad.valueLine, 'B.Tech, JNTU · India');
      final tenth = p.educationLevels.firstWhere((e) => e.level == '10th');
      expect(tenth.country, isNull);
      expect(tenth.valueLine, 'ZPHS Guntur');
      final pg = p.educationLevels.firstWhere((e) => e.level == 'post_graduation');
      expect(pg.valueLine, 'United States');
      expect(
        p.educationLevelsLabel,
        '10th: ZPHS Guntur; Graduation: B.Tech, JNTU · India; Post graduation: United States',
      );
      expect(grad.toJson(), {'level': 'graduation', 'details': 'B.Tech, JNTU', 'country_id': 1});
      expect(Profile.fromJson(base()).educationLevels, isEmpty);
      expect(Profile.fromJson(base()).educationLevelsLabel, isNull);
    });

    test('education level labels match the paper form', () {
      expect(EducationLevel.levels,
          ['below_10th', '10th', 'intermediate', 'graduation', 'post_graduation']);
      expect(EducationLevel.levelLabel('below_10th'), 'Below 10th');
      expect(EducationLevel.levelLabel('10th'), '10th');
      expect(EducationLevel.levelLabel('intermediate'), 'Intermediate / 12th');
      expect(EducationLevel.levelLabel('graduation'), 'Graduation');
      expect(EducationLevel.levelLabel('post_graduation'), 'Post graduation');
      expect(EducationLevel.levelLabel('phd'), 'phd', reason: 'unknown levels fall through');
      expect(const EducationLevel(level: 'graduation').valueLine, isNull);
    });

    test('cards show the NRI country or a foreign work country — never a protected place', () {
      // India-based, no NRI: nothing public to show, the card falls back to the profession.
      final local = Profile.fromJson(base()..['work_country'] = {'id': 1, 'name': 'India'});
      expect(local.isNri, isFalse);
      expect(local.nriLabel, isNull);
      expect(local.placeLine, isNull);
      expect(local.worksIn, 'India');

      // Work place alone (granted access) never leaks onto the card line.
      final granted = Profile.fromJson(base()..['work_place'] = 'Hyderabad');
      expect(granted.placeLine, isNull);
      expect(granted.worksIn, isNull);

      // A foreign work country without the NRI flag still shows.
      final abroad = Profile.fromJson(base()..['work_country'] = {'id': 5, 'name': 'Germany'});
      expect(abroad.placeLine, 'Germany');
      expect(abroad.worksIn, 'Germany');

      // NRI: the country only — the exact place abroad is protected.
      final nri = Profile.fromJson(base()
        ..['is_nri'] = true
        ..['nri_country'] = {'id': 1, 'name': 'United States'}
        ..['nri_place'] = 'California'
        ..['work_country'] = {'id': 1, 'name': 'India'}
        ..['city'] = 'Nalgonda');
      expect(nri.nriLabel, 'United States');
      expect(nri.placeLine, 'United States');
      expect(nri.worksIn, 'United States');
      expect(nri.nriPlaceLabel, 'California', reason: 'shown only in the granted card');
      expect(nri.placeLine, isNot(contains('California')));
      expect(nri.placeLine, isNot(contains('Nalgonda')));

      // NRI without a country reads as a plain badge.
      final nriNoCountry = Profile.fromJson(base()..['is_nri'] = true);
      expect(nriNoCountry.nriLabel, 'NRI');
      expect(nriNoCountry.placeLine, 'NRI');
      expect(nriNoCountry.nriPlaceLabel, isNull);
    });

    test('unknown status falls back to active', () {
      final p = Profile.fromJson(base()..['status'] = 'something_new');
      expect(p.status, ProfileStatus.active);
    });
  });

  group('ParsedProfile (AI import draft)', () {
    test('v2.1 keys are optional and the education table is normalised', () {
      final r = ParsedProfile.fromJson({
        'draft': {
          'full_name': 'Ravi',
          'nationality_id': 1,
          'occupation_type_id': '3',
          'elder_sisters': 2,
          'education_levels': [
            {'level': 'post_graduation', 'details': 'M.Tech', 'country_id': 2},
            {'level': 'graduation', 'details': 'B.Tech', 'country_id': '1'},
            {'level': 'phd', 'details': 'ignored'},
            'garbage',
          ],
        },
        'unmatched': {'work_country': 'Dubai'},
        'warnings': [],
      });
      expect(r.intField('nationality_id'), 1);
      expect(r.intField('occupation_type_id'), 3, reason: 'numeric strings are accepted');
      expect(r.intField('elder_sisters'), 2);
      expect(r.intField('work_country_id'), isNull, reason: 'absent keys are ignored');
      expect(r.has('work_country_id'), isFalse);
      expect(r.textField('property_share'), isNull);
      final levels = r.educationLevels;
      expect(levels.map((e) => e['level']), ['graduation', 'post_graduation']);
      expect(levels.first['details'], 'B.Tech');
      expect(levels.first['country_id'], 1);
      expect(levels.last['country_id'], 2);
      expect(r.unmatched['work_country'], 'Dubai');
    });

    test('a draft without education_levels yields an empty table', () {
      final r = ParsedProfile.fromJson({'draft': {'full_name': 'Ravi'}});
      expect(r.educationLevels, isEmpty);
      expect(ParsedProfile.fromJson({'draft': {'education_levels': 'nope'}}).educationLevels, isEmpty);
    });
  });

  group('Profile birth details, DOB line and hold state', () {
    Profile parse(Map<String, dynamic> extra) => Profile.fromJson({
          'id': 1,
          'full_name': 'Priya Kumari',
          'gender': 'bride',
          'status': 'active',
          'dob': '1998-04-12',
          'age': 28,
          ...extra,
        });

    test('short profile line shows the age with the DOB in brackets', () {
      expect(parse({}).ageDobLine, '28 yrs (12 Apr 1998)');
      expect(parse({'dob': null}).dobLabel, isNull);
      expect(parse({'dob': null}).ageDobLine, '28 yrs');
      expect(parse({'age': null, 'dob': null}).ageDobLine, isNull);
    });

    test('birth time is shown in 12-hour form; birth place is protected', () {
      expect(parse({'birth_time': '22:40'}).birthTimeLabel, '10:40 PM');
      expect(parse({'birth_time': '00:05'}).birthTimeLabel, '12:05 AM');
      expect(parse({'birth_time': '12:00'}).birthTimeLabel, '12:00 PM');
      expect(parse({'birth_time': '04:35', 'birth_place': 'Guntur'}).birthPlace, 'Guntur');
      expect(parse({'birth_time': '04:35', 'birth_place': 'Guntur'}).birthPlaceLine, 'Guntur');
      expect(parse({'birth_time': '04:35'}).birthPlaceLine, isNull);
      expect(parse({}).birthTimeLabel, isNull);
    });

    test('on_hold status round-trips through the enum', () {
      expect(ProfileStatus.fromApi('on_hold'), ProfileStatus.onHold);
      expect(ProfileStatus.onHold.apiValue, 'on_hold');
      expect(ProfileStatus.onHold.label, 'On hold');
      expect(ProfileStatus.fromApi('nonsense'), ProfileStatus.active);
      expect(parse({'status': 'on_hold'}).isOnHold, isTrue);
    });

    test('hold state: pending, mine, and who holds it (uploader/admin only)', () {
      final pending = parse({'hold_request_status': 'pending', 'hold_request_id': 7});
      expect(pending.holdPending, isTrue);
      expect(pending.holdMine, isFalse);

      final mine = parse({'status': 'on_hold', 'hold_request_status': 'approved', 'hold_request_id': 7});
      expect(mine.holdMine, isTrue);
      expect(mine.heldBy, isNull, reason: 'other agents never learn who holds a profile');

      final owner = parse({
        'status': 'on_hold',
        'can_edit': true,
        'can_delete': true,
        'held_by': {'hold_request_id': 9, 'id': 3, 'full_name': 'Kiran Bureau', 'agency_name': 'Kiran Alliances'},
        'pending_hold_requests': 2,
      });
      expect(owner.canDelete, isTrue);
      expect(owner.heldBy?.fullName, 'Kiran Bureau');
      expect(owner.heldBy?.holdRequestId, 9);
      expect(owner.pendingHoldRequests, 2);
    });
  });

  group('HoldRequest', () {
    test('inbox rows carry the requester, sent rows do not', () {
      final inbox = HoldRequest.fromJson({
        'id': 1,
        'profile_id': 5,
        'profile_name': 'Ravi Teja',
        'status': 'pending',
        'requester': {'id': 3, 'full_name': 'Kiran Bureau', 'agency_name': 'Kiran Alliances'},
      });
      expect(inbox.requesterName, 'Kiran Bureau');
      expect(inbox.isPending, isTrue);
      expect(inbox.statusLabel, contains('waiting'));

      final sent = HoldRequest.fromJson({
        'id': 2,
        'profile_id': 5,
        'profile_name': 'Ravi Teja',
        'status': 'approved',
        'is_mine': true,
      });
      expect(sent.requesterName, isNull);
      expect(sent.isMine, isTrue);
      expect(sent.statusLabel, 'On hold');
      expect(HoldRequest.fromJson({'id': 3, 'profile_id': 5, 'profile_name': 'x', 'status': 'released'}).statusLabel,
          'Hold released');
    });
  });

  group('ContactRequest', () {
    test('inbox rows carry the requester, sent rows do not', () {
      final inbox = ContactRequest.fromJson({
        'id': 5,
        'profile_id': 9,
        'profile_name': 'Priya Kumari',
        'status': 'pending',
        'requester': {'id': 3, 'full_name': 'Agent C', 'agency_name': 'C Bureau', 'phone': '7000000000'},
      });
      expect(inbox.requesterName, 'Agent C');

      final sent = ContactRequest.fromJson({
        'id': 5,
        'profile_id': 9,
        'profile_name': 'Priya Kumari',
        'status': 'pending',
      });
      expect(sent.requesterName, isNull);
    });

    test('status labels read plainly for non-technical users', () {
      ContactRequest of(String status, {int? daysLeft}) => ContactRequest.fromJson({
            'id': 1,
            'profile_id': 1,
            'profile_name': 'X',
            'status': status,
            'days_left': ?daysLeft,
          });

      expect(of('pending').statusLabel, 'Waiting for approval');
      expect(of('approved', daysLeft: 12).statusLabel, 'Approved · 12 days left');
      expect(of('revoked').statusLabel, 'Access revoked');
      expect(of('expired').statusLabel, 'Access expired');
    });
  });
}
