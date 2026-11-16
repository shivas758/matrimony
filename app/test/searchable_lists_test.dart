import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/master_data.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/state/masters_state.dart';
import 'package:matrimony_agents/state/profile_filters.dart';
import 'package:matrimony_agents/ui/screens/profiles/filter_sheet.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:matrimony_agents/ui/widgets/searchable_lists.dart';
import 'package:provider/provider.dart';

/// SPEC §9.23 E — search inside long lists: the filter, the chip group, the
/// single and multi picker sheets, the form field, and the filter sheet.

const _communityNames = [
  'Reddy',
  'Kamma',
  'Kapu',
  'Brahmin',
  'Vysya',
  'Velama',
  'Yadava',
  'Goud',
  'Padmasali',
  'Rajaka',
];

List<PickerOption> _communities() => [
      for (var i = 0; i < _communityNames.length; i++) PickerOption(i + 1, _communityNames[i]),
    ];

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    );

/// The chip labels currently on screen, in order.
List<String> _chipLabels(WidgetTester tester) => tester
    .widgetList<FilterChip>(find.byType(FilterChip))
    .map((c) => ((c.label as Text).data ?? ''))
    .toList();

void main() {
  group('filterPickerOptions', () {
    final options = [
      const PickerOption(1, 'Reddy'),
      const PickerOption(2, 'Kamma'),
      const PickerOption(3, 'Motati', keywords: 'Reddy'),
      const PickerOption(4, 'Chowdary', keywords: 'Kamma'),
    ];

    test('case-insensitive, anywhere in the name, original order', () {
      expect(filterPickerOptions(options, 'CHOW').map((o) => o.id), [4]);
      // "Kamma" itself and the subcaste whose community it is.
      expect(filterPickerOptions(options, 'AMM').map((o) => o.id), [2, 4]);
      expect(filterPickerOptions(options, ' tat ').map((o) => o.id), [3]);
      expect(filterPickerOptions(options, '').map((o) => o.id), [1, 2, 3, 4]);
      expect(filterPickerOptions(options, 'zzz'), isEmpty);
    });

    test('a subcaste also matches its community name (keywords)', () {
      expect(filterPickerOptions(options, 'reddy').map((o) => o.id), [1, 3]);
      expect(filterPickerOptions(options, 'kamma').map((o) => o.id), [2, 4]);
    });

    test('kept (selected) ids always stay, in place', () {
      expect(filterPickerOptions(options, 'motati', keep: {2}).map((o) => o.id), [2, 3]);
      expect(filterPickerOptions(options, 'zzz', keep: {4}).map((o) => o.id), [4]);
    });

    test('long = more than 8', () {
      expect(kSearchThreshold, 8);
      expect(isLongList(8), isFalse);
      expect(isLongList(9), isTrue);
    });

    test('masterOptions keeps ids and names', () {
      final o = masterOptions(const [MasterItem(id: 7, name: 'B.Tech')]);
      expect(o.single.id, 7);
      expect(o.single.label, 'B.Tech');
    });
  });

  group('SearchableChipGroup', () {
    testWidgets('8 or fewer chips: no search field', (tester) async {
      await tester.pumpWidget(_host(SearchableChipGroup(
        options: _communities().take(8).toList(),
        selected: const {},
        onToggle: (_) {},
      )));
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilterChip), findsNWidgets(8));
    });

    testWidgets('a long list: typing filters; selected chips stay visible; toggles report',
        (tester) async {
      final selected = <int>{4}; // Brahmin
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) => SearchableChipGroup(
          searchLabel: S.community,
          options: _communities(),
          selected: selected,
          onToggle: (id) => setState(() => selected.contains(id) ? selected.remove(id) : selected.add(id)),
        ),
      )));

      expect(find.text(S.searchIn(S.community)), findsOneWidget);
      expect(find.byType(FilterChip), findsNWidgets(10));

      await tester.enterText(find.byType(TextField), 'ka');
      await tester.pump();
      // Kamma, Kapu, Rajaka match; Brahmin is selected so it stays.
      expect(_chipLabels(tester), ['Kamma', 'Kapu', 'Brahmin', 'Rajaka']);

      await tester.tap(find.widgetWithText(FilterChip, 'Kapu'));
      await tester.pump();
      expect(selected, {4, 3});

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(_chipLabels(tester), ['Kapu', 'Brahmin'], reason: 'only the selected ones');

      // Clearing the search brings every chip back.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(find.byType(FilterChip), findsNWidgets(10));
    });

    testWidgets('nothing matches and nothing selected: the "nothing matches" line', (tester) async {
      await tester.pumpWidget(_host(SearchableChipGroup(
        options: _communities(),
        selected: const {},
        onToggle: (_) {},
      )));
      await tester.enterText(find.byType(TextField), 'qqq');
      await tester.pump();
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text(S.noListMatches), findsOneWidget);
    });
  });

  group('MasterSelectField', () {
    testWidgets('a short list stays the plain dropdown', (tester) async {
      await tester.pumpWidget(_host(MasterSelectField(
        label: S.community,
        options: _communities().take(5).toList(),
        value: 2,
        onChanged: (_) {},
      )));
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      expect(find.text('Kamma'), findsOneWidget);
    });

    testWidgets('a long list opens the picker sheet: search, tap to pick, None clears',
        (tester) async {
      int? value = 1;
      final changes = <int?>[];
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (context, setState) => MasterSelectField(
          label: '${S.community} *',
          icon: Icons.groups_rounded,
          options: _communities(),
          value: value,
          onChanged: (v) => setState(() {
            changes.add(v);
            value = v;
          }),
        ),
      )));
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.text('Reddy'), findsOneWidget);

      await tester.tap(find.text('Reddy'));
      await tester.pumpAndSettle();
      expect(find.byType(PickerSheet), findsOneWidget);
      // The sheet's title drops the required mark; its search hint follows.
      expect(find.text(S.community), findsOneWidget);
      expect(find.text(S.searchIn(S.community)), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-none')), findsOneWidget);

      await tester.enterText(
        find.descendant(of: find.byType(PickerSheet), matching: find.byType(TextField)),
        'GOU',
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('pick-8')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-1')), findsNothing, reason: 'single choice filters strictly');
      expect(find.byKey(const ValueKey('pick-none')), findsNothing, reason: 'None only without a search');

      await tester.tap(find.byKey(const ValueKey('pick-8')));
      await tester.pumpAndSettle();
      expect(find.byType(PickerSheet), findsNothing);
      expect(changes, [8]);
      expect(find.text('Goud'), findsOneWidget);

      // Reopen and clear with None.
      await tester.tap(find.text('Goud'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-none')));
      await tester.pumpAndSettle();
      expect(changes, [8, null]);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('dismissing the sheet changes nothing; the validator sees the value',
        (tester) async {
      final form = GlobalKey<FormState>();
      final changes = <int?>[];
      await tester.pumpWidget(_host(Form(
        key: form,
        child: MasterSelectField(
          label: S.community,
          options: _communities(),
          value: null,
          allowClear: false,
          validator: (v) => v == null ? S.communityRequired : null,
          onChanged: changes.add,
        ),
      )));
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text(S.communityRequired), findsOneWidget);

      await tester.tap(find.byType(MasterSelectField));
      await tester.pumpAndSettle();
      expect(find.byType(PickerSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-none')), findsNothing, reason: 'not clearable');
      await tester.tapAt(const Offset(10, 10)); // the barrier
      await tester.pumpAndSettle();
      expect(find.byType(PickerSheet), findsNothing);
      expect(changes, isEmpty);
    });
  });

  group('multi picker sheet', () {
    testWidgets('checkboxes + Done; ticked ones stay while searching; Clear all',
        (tester) async {
      Set<int>? result;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showMultiPickerSheet(
                context,
                title: S.knownLanguages,
                options: _communities(),
                selected: {1},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsWidgets);
      await tester.enterText(
        find.descendant(of: find.byType(PickerSheet), matching: find.byType(TextField)),
        'vel',
      );
      await tester.pump();
      // Velama matches; Reddy is ticked and stays.
      expect(find.byKey(const ValueKey('pick-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-6')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-2')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pick-6')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, S.done));
      await tester.pumpAndSettle();
      expect(result, {1, 6});

      // Clear all, then Done → empty set.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, S.clearAll));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, S.done));
      await tester.pumpAndSettle();
      expect(result, <int>{});
    });

    testWidgets('a short single list: no search box, rows are list tiles, note shown',
        (tester) async {
      PickResult? picked;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await showSinglePickerSheet(
                context,
                title: S.requestCommunity,
                note: S.requestCommunityNote,
                options: _communities().take(3).toList(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(S.requestCommunityNote), findsOneWidget);
      expect(find.descendant(of: find.byType(PickerSheet), matching: find.byType(TextField)),
          findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'Kapu'));
      await tester.pumpAndSettle();
      expect(picked?.id, 3);
    });
  });

  group('filter sheet (SPEC §9.23 E)', () {
    MasterData masters() => MasterData.fromJson({
          'communities': [
            for (var i = 0; i < _communityNames.length; i++)
              {'id': i + 1, 'name': _communityNames[i]},
          ],
          'subcastes': [
            {'id': 11, 'community_id': 1, 'name': 'Motati'},
            {'id': 12, 'community_id': 1, 'name': 'Pakanati'},
            {'id': 21, 'community_id': 2, 'name': 'Chowdary'},
          ],
          'professions': [
            {'id': 1, 'name': 'Doctor'},
          ],
          'educations': [],
          'marital_statuses': [],
          'zodiac_signs': [],
          'nakshatrams': [],
          'countries': [
            for (var i = 1; i <= 12; i++) {'id': i, 'name': 'Country $i'},
          ],
        });

    testWidgets('community search keeps the selected; subcastes match their community',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final state = MastersState(_FakeProfiles(masters()));
      await state.load();
      ProfileFilters? result;
      await tester.pumpWidget(ChangeNotifierProvider<MastersState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await FilterSheet.show(
                  context,
                  const ProfileFilters(communityIds: {1, 2}),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final communityGroup = find.byKey(ValueKey('chips-${S.community}'));
      expect(communityGroup, findsOneWidget);
      // Only the long community list gets a search field; the one profession does not.
      expect(find.descendant(of: communityGroup, matching: find.byType(TextField)), findsOneWidget);
      expect(find.byKey(ValueKey('chips-${S.profession}')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('chips-${S.profession}')),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );

      await tester.enterText(
        find.descendant(of: communityGroup, matching: find.byType(TextField)),
        'goud',
      );
      await tester.pump();
      final labels = tester
          .widgetList<FilterChip>(
            find.descendant(of: communityGroup, matching: find.byType(FilterChip)),
          )
          .map((c) => (c.label as Text).data)
          .toList();
      expect(labels, ['Reddy', 'Kamma', 'Goud'], reason: 'selected Reddy and Kamma stay');

      // Subcastes of both communities, labelled with the community.
      final subcastes = find.byKey(ValueKey('chips-${S.subcaste}'));
      expect(find.descendant(of: subcastes, matching: find.byType(FilterChip)), findsNWidgets(3));
      expect(find.text('Reddy · Motati'), findsOneWidget);
      expect(
        filterPickerOptions(
          const [
            PickerOption(11, 'Motati', keywords: 'Reddy'),
            PickerOption(21, 'Chowdary', keywords: 'Kamma'),
          ],
          'kamma',
        ).map((o) => o.id),
        [21],
      );

      // Work country uses the searchable multi picker.
      await tester.ensureVisible(find.text(S.anyWorkCountry));
      await tester.tap(find.text(S.anyWorkCountry));
      await tester.pumpAndSettle();
      expect(find.byType(PickerSheet), findsOneWidget);
      await tester.enterText(
        find.descendant(of: find.byType(PickerSheet), matching: find.byType(TextField)),
        'country 12',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pick-12')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, S.done));
      await tester.pumpAndSettle();
      expect(find.text('Country 12'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, S.apply));
      await tester.pumpAndSettle();
      expect(result?.workCountryIds, {12});
      expect(result?.communityIds, {1, 2});
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeProfiles extends ProfileService {
  _FakeProfiles(this.data) : super(ApiClient());

  final MasterData data;

  @override
  Future<MasterData> masters() async => data;
}
