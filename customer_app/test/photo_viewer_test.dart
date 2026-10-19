import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/ui/widgets/photo_viewer.dart';

// SPEC §9.17: the full-screen viewer opens at the tapped photo, counts n/N
// and swipes between photos. No token → AuthedPhoto shows its placeholder, so
// nothing touches the network.
void main() {
  const urls = ['https://x.test/1', 'https://x.test/2', 'https://x.test/3'];

  Future<void> pumpViewer(WidgetTester tester, {int initialIndex = 0, List<String> list = urls}) =>
      tester.pumpWidget(MaterialApp(home: PhotoViewer(urls: list, api: ApiClient(), initialIndex: initialIndex)));

  testWidgets('opens at the tapped photo and counts', (tester) async {
    await pumpViewer(tester, initialIndex: 1);
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('swiping moves to the next photo', (tester) async {
    await pumpViewer(tester);
    expect(find.text('1/3'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('an out-of-range index is clamped; one photo shows no counter', (tester) async {
    await pumpViewer(tester, initialIndex: 9);
    expect(find.text('3/3'), findsOneWidget);
    await pumpViewer(tester, list: const ['https://x.test/only']);
    expect(find.textContaining('/1'), findsNothing);
  });
}
