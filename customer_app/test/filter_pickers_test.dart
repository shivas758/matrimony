import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/master_data.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/services/profile_service.dart';
import 'package:gandharva/state/browse_filters.dart';
import 'package:gandharva/state/masters_state.dart';
import 'package:gandharva/ui/screens/browse/filter_sheet.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:gandharva/ui/widgets/searchable_list.dart';
import 'package:provider/provider.dart';

// SPEC §9.24 B (Wedbook Matrimony 3.5.0): Browse → Filters uses the profile
// form's pickers — a list of more than eight values is one picker field
// ("Any" or the chosen values as removable chips) that opens the picker
// sheet (search, checkboxes, Done); short lists stay chips. The filter
// values and the API query are unchanged.

List<Map<String, dynamic>> _items(List<String> names, {int from = 1}) => [
      for (var i = 0; i < names.length; i++) {'id': from + i, 'name': names[i]},
    ];

/// Ten communities; Kamma has nine subcastes (a long list on its own),
/// Reddy two; ten educations, nine languages — and short lists for marital
/// status (four) and religion (three).
Map<String, dynamic> _masters() => {
      'communities': _items(
          ['Kamma', 'Reddy', 'Kapu', 'Brahmin', 'Vysya', 'Velama', 'Raju', 'Yadava', 'Gowda', 'Lingayat']),
      'subcastes': [
        for (final (i, name)
            in ['Chowdary', 'Naidu', 'Rao', 'Babu', 'Prasad', 'Sastry', 'Varma', 'Devi', 'Lakshmi'].indexed)
          {'id': 11 + i, 'community_id': 1, 'name': name},
        {'id': 21, 'community_id': 2, 'name': 'Pakanati'},
        {'id': 22, 'community_id': 2, 'name': 'Motati'},
      ],
      'educations': _items(
          ['B.Tech', 'M.Tech', 'MBA', 'MBBS', 'B.Com', 'M.Com', 'B.Sc', 'M.Sc', 'BA', 'PhD'],
          from: 40),
      'languages': _items(
          ['Telugu', 'Kannada', 'Tamil', 'Hindi', 'English', 'Marathi', 'Malayalam', 'Urdu', 'Odia'],
          from: 60),
      'marital_statuses': _items(['Unmarried', 'Divorced', 'Widowed', 'Separated'], from: 80),
      'religions': _items(['Hindu', 'Christian', 'Muslim'], from: 90),
      'countries': [
        {'id': 1, 'name': 'India'},
        {'id': 5, 'name': 'United States'},
      ],
      'zodiac_signs': [],
      'nakshatrams': [],
    };

class _FakeProfiles extends ProfileService {
  _FakeProfiles(super.api);

  @override
  Future<MasterData> masters() async => MasterData.fromJson(_masters());
}

/// A page with "open" → [FilterSheet.show]; remembers what came back.
class _Host {
  final api = ApiClient();
  late final masters = MastersState(_FakeProfiles(api));
  BrowseFilters? result;
  bool closed = false;

  Widget wrap(BrowseFilters initial, {bool guest = true}) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<MastersState>.value(value: masters),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await FilterSheet.show(context, initial, communities: const [], guest: guest);
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

  /// Masters loaded (Browse does it before opening), sheet open.
  Future<void> open(WidgetTester tester, [BrowseFilters initial = BrowseFilters.empty, bool guest = true]) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await masters.load();
    await tester.pumpWidget(wrap(initial, guest: guest));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Show matches → the sheet closes with the filters.
  Future<BrowseFilters> apply(WidgetTester tester) async {
    await tester.tap(find.text(S.apply));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    return result!;
  }
}

/// The picker field of the filter titled [title].
Finder _picker(String title) => find.byWidgetPredicate((w) => w is MultiPickerField && w.title == title);

/// The filter sheet's own list (not the picker sheet's).
Finder _sheetList() =>
    find.descendant(of: find.byType(FilterSheet), matching: find.byType(Scrollable)).first;

/// Scrolls [f] into the middle of the filter sheet (from the top: the list
/// builds lazily, so something above may no longer exist).
Future<void> _show(WidgetTester tester, Finder f) async {
  tester.state<ScrollableState>(_sheetList()).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(f, 200, scrollable: _sheetList());
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pumpAndSettle();
}

/// Opens the picker of [title] — a tap on the field's leading icon, clear
/// of the chips and their ×.
Future<void> _openPicker(WidgetTester tester, String title) async {
  await _show(tester, _picker(title));
  await tester.tapAt(tester.getTopLeft(_picker(title)) + const Offset(18, 18));
  await tester.pumpAndSettle();
}

Finder _row(String label) => find.widgetWithText(CheckboxListTile, label);

Finder _chipIn(String title, String label) =>
    find.descendant(of: _picker(title), matching: find.widgetWithText(InputChip, label));

void main() {
  testWidgets('long lists are compact picker fields reading "Any"; short lists stay chips', (tester) async {
    final host = _Host();
    await host.open(tester);

    // Ten communities, eleven subcastes, ten educations: pickers reading "Any"…
    expect(find.descendant(of: _picker(S.community), matching: find.text(S.anyValue)), findsOneWidget);
    for (final title in [S.community, S.subcaste, S.education]) {
      await _show(tester, _picker(title));
      expect(tester.widget<MultiPickerField>(_picker(title)).hint, S.anyValue, reason: title);
      expect(tester.widget<MultiPickerField>(_picker(title)).removableChips, isTrue, reason: title);
    }
    // …so no wall of chips, and no search boxes in the sheet itself.
    for (final name in ['Kamma', 'Lingayat', 'Chowdary', 'MBA', 'PhD']) {
      expect(find.widgetWithText(FilterChip, name), findsNothing, reason: name);
    }
    expect(find.descendant(of: find.byType(FilterSheet), matching: find.byType(ListSearchField)), findsNothing);
    // Nothing for an empty list (no professions in these masters).
    expect(find.text(S.profession.toUpperCase()), findsNothing);

    // Four marital statuses and three religions: plain chips, no picker.
    await _show(tester, find.widgetWithText(FilterChip, 'Widowed'));
    expect(find.widgetWithText(FilterChip, 'Unmarried'), findsOneWidget);
    expect(_picker(S.maritalStatus), findsNothing);
    await _show(tester, find.widgetWithText(FilterChip, 'Christian'));
    expect(_picker(S.religion), findsNothing);

    // Nine languages: a picker again.
    await _show(tester, _picker(S.motherTongue));
    expect(find.widgetWithText(FilterChip, 'Odia'), findsNothing);

    // The guest limit is unchanged: no sort by name.
    await _show(tester, find.text(S.sortNewest));
    expect(find.text(S.sortName), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picker: search, checkboxes, Done → chips in the field → the same filter values and query',
      (tester) async {
    final host = _Host();
    await host.open(tester);
    await _openPicker(tester, S.community);

    // The profile form's picker sheet: the title, a search box, checkboxes, Done.
    expect(find.text(S.searchIn(S.community)), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(find.text(S.done), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, S.searchIn(S.community)), 'red');
    await tester.pump();
    expect(_row('Reddy'), findsOneWidget);
    expect(_row('Kamma'), findsNothing);
    await tester.tap(_row('Reddy'));
    await tester.pump();
    expect(find.text(S.selectedCount(1)), findsOneWidget);
    await tester.tap(find.text(S.done));
    await tester.pumpAndSettle();

    // The field shows the choice as a removable chip.
    expect(_chipIn(S.community, 'Reddy'), findsOneWidget);
    expect(find.descendant(of: _picker(S.community), matching: find.text(S.anyValue)), findsNothing);

    // Subcastes only for the chosen community: Reddy's two, short → chips.
    expect(_picker(S.subcaste), findsNothing);
    await _show(tester, find.widgetWithText(FilterChip, 'Pakanati'));
    expect(find.widgetWithText(FilterChip, 'Motati'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Chowdary'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'Pakanati'));
    await tester.pump();

    // A long list, picked from the sheet too: education.
    await _openPicker(tester, S.education);
    await tester.tap(_row('MBA'));
    await tester.enterText(find.widgetWithText(TextField, S.searchIn(S.education)), 'ph');
    await tester.pump();
    await tester.tap(_row('PhD'));
    await tester.pump();
    expect(find.text(S.selectedCount(2)), findsOneWidget, reason: 'MBA stays chosen while searching');
    await tester.tap(find.text(S.done));
    await tester.pumpAndSettle();
    expect(_chipIn(S.education, 'MBA'), findsOneWidget);
    expect(_chipIn(S.education, 'PhD'), findsOneWidget);

    final f = await host.apply(tester);
    expect(f.communityIds, {2});
    expect(f.subcasteIds, {21});
    expect(f.educationIds, {42, 49});
    final q = f.toQuery();
    expect(q['community_id'], '2');
    expect(q['subcaste_id'], '21');
    expect(q['education_id'], '42,49');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a subcaste is found by its community name; the picker labels them by community', (tester) async {
    final host = _Host();
    // No community chosen: every offered community's subcastes (eleven).
    await host.open(tester);
    await _openPicker(tester, S.subcaste);
    expect(_row('Kamma · Chowdary'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, S.searchIn(S.subcaste)), 'redd');
    await tester.pump();
    expect(_row('Reddy · Pakanati'), findsOneWidget);
    expect(_row('Reddy · Motati'), findsOneWidget);
    expect(_row('Kamma · Chowdary'), findsNothing);
    await tester.tapAt(const Offset(10, 10)); // dismissed: nothing changes
    await tester.pumpAndSettle();

    // Kamma alone: nine subcastes, still a picker — labels without the
    // community, yet typing "kamma" still finds them all.
    await tester.pumpWidget(const SizedBox.shrink());
    final host2 = _Host();
    await host2.open(tester, const BrowseFilters(communityIds: {1}));
    expect(_chipIn(S.community, 'Kamma'), findsOneWidget);
    await _openPicker(tester, S.subcaste);
    expect(_row('Chowdary'), findsOneWidget);
    expect(_row('Kamma · Chowdary'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, S.searchIn(S.subcaste)), 'kamma');
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNWidgets(9));
    expect(tester.takeException(), isNull);
  });

  testWidgets("removing a value: a chip's ×, the field's ×, the sheet's Clear all", (tester) async {
    final host = _Host();
    await host.open(
      tester,
      const BrowseFilters(communityIds: {1, 2}, subcasteIds: {11, 21}, educationIds: {40, 41}, motherTongueIds: {60}),
    );
    expect(_chipIn(S.community, 'Kamma'), findsOneWidget);
    expect(_chipIn(S.community, 'Reddy'), findsOneWidget);

    // One chip's × — Kamma goes, and with it Kamma's subcaste.
    await tester.tap(find.descendant(of: _picker(S.community), matching: find.byTooltip(S.removeValue('Kamma'))));
    await tester.pumpAndSettle();
    expect(_chipIn(S.community, 'Kamma'), findsNothing);
    expect(_chipIn(S.community, 'Reddy'), findsOneWidget);

    // The field's own × clears the whole language choice.
    await _show(tester, _picker(S.motherTongue));
    expect(_chipIn(S.motherTongue, 'Telugu'), findsOneWidget);
    await tester.tap(find.descendant(of: _picker(S.motherTongue), matching: find.byTooltip(S.clear)));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _picker(S.motherTongue), matching: find.text(S.anyValue)), findsOneWidget);

    // Clear all inside the picker sheet, then Done.
    await _openPicker(tester, S.education);
    expect(find.text(S.selectedCount(2)), findsOneWidget);
    await tester.tap(find.text(S.clearAll).last);
    await tester.pump();
    await tester.tap(find.text(S.done));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _picker(S.education), matching: find.text(S.anyValue)), findsOneWidget);

    final f = await host.apply(tester);
    expect(f.communityIds, {2});
    expect(f.subcasteIds, {21}, reason: "Kamma's Chowdary dropped with Kamma");
    expect(f.educationIds, isEmpty);
    expect(f.motherTongueIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved filters come back unchanged when nothing is touched', (tester) async {
    const saved = BrowseFilters(
      gender: 'bride',
      communityIds: {1},
      subcasteIds: {12},
      educationIds: {40},
      maritalStatusIds: {80},
      motherTongueIds: {60, 61},
      workCountryIds: {5},
      ageMin: 24,
      ageMax: 30,
      sort: 'age_asc',
    );
    final host = _Host();
    await host.open(tester, saved, false);
    expect(_chipIn(S.community, 'Kamma'), findsOneWidget);
    await _show(tester, _picker(S.motherTongue));
    expect(_chipIn(S.motherTongue, 'Telugu'), findsOneWidget);
    expect(_chipIn(S.motherTongue, 'Kannada'), findsOneWidget);
    // Not a guest: sort by name is offered.
    await _show(tester, find.text(S.sortName));
    final f = await host.apply(tester);
    expect(f.toQuery(), saved.toQuery());
    expect(tester.takeException(), isNull);
  });

  testWidgets('the generalised field: a widget of its own (chips, ×, Done)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final options = pickOptionsOf(MasterData.fromJson(_masters()).communities);
    var value = <int>{3};
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilterChoiceGroup(
                title: S.community,
                options: options,
                selected: value,
                onChanged: (v) => setState(() => value = v),
              ),
              FilterChoiceGroup(
                title: S.religion,
                options: options.take(8).toList(),
                selected: value,
                onChanged: (v) => setState(() => value = v),
              ),
              FilterChoiceGroup(title: S.foodHabit, options: const [], selected: const {}, onChanged: (_) {}),
            ],
          ),
        ),
      ),
    ));
    expect(find.byType(MultiPickerField), findsOneWidget, reason: 'only the list longer than eight');
    expect(find.widgetWithText(InputChip, 'Kapu'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Kapu'), findsOneWidget, reason: 'the short list: chips');
    expect(find.text(S.foodHabit.toUpperCase()), findsNothing, reason: 'an empty list shows nothing');

    // A short-list chip toggles the same selection.
    await tester.tap(find.widgetWithText(FilterChip, 'Kamma'));
    await tester.pump();
    expect(value, {1, 3});
    expect(find.widgetWithText(InputChip, 'Kamma'), findsOneWidget);

    // Tapping a chosen chip opens the picker (only its × removes it).
    await tester.tap(find.widgetWithText(InputChip, 'Kapu'));
    await tester.pumpAndSettle();
    expect(find.text(S.selectedCount(2)), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, S.searchIn(S.community)), 'ling');
    await tester.pump();
    await tester.tap(_row('Lingayat'));
    await tester.tap(find.text(S.done));
    await tester.pumpAndSettle();
    expect(value, {1, 3, 10});
    expect(tester.takeException(), isNull);
  });
}
