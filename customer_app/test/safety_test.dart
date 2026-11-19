import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/config.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/models/safety.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/services/customer_auth_service.dart';
import 'package:gandharva/services/link_launcher.dart';
import 'package:gandharva/services/payment_service.dart';
import 'package:gandharva/services/profile_service.dart';
import 'package:gandharva/state/auth_state.dart';
import 'package:gandharva/state/browse_state.dart';
import 'package:gandharva/state/interests_state.dart';
import 'package:gandharva/ui/screens/auth/signup_screen.dart';
import 'package:gandharva/ui/screens/blocks/blocked_profiles_screen.dart';
import 'package:gandharva/ui/screens/browse/profile_detail_screen.dart';
import 'package:gandharva/ui/screens/more_screen.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:gandharva/ui/widgets/common.dart';
import 'package:provider/provider.dart';

import 'guest_mode_test.dart' show activeMeJson, guestMeJson;

// SPEC §9.22: report, block, terms consent (Google Play UGC policy).

/// Answers GET / POST / DELETE from per-"METHOD path" queues (the last answer
/// sticks); records every call. An answer is a map or an [ApiException].
class _FakeApi extends ApiClient {
  final calls = <(String, String, Object?)>[];
  final Map<String, List<Object>> _answers = {};
  String? token;

  void answer(String method, String path, Object reply) =>
      _answers.putIfAbsent('$method $path', () => []).add(reply);

  List<Object?> bodiesFor(String method, String path) => [
        for (final (m, p, b) in calls)
          if (m == method && p == path) b,
      ];

  Future<Map<String, dynamic>> _reply(String method, String path, Object? body) async {
    calls.add((method, path, body));
    final queue = _answers['$method $path'];
    if (queue == null || queue.isEmpty) throw ApiException('network_error', 'no answer for $method $path');
    final reply = queue.length == 1 ? queue.first : queue.removeAt(0);
    if (reply is ApiException) throw reply;
    return reply as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) => _reply('GET', path, query);

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) => _reply('POST', path, body);

  @override
  Future<Map<String, dynamic>> delete(String path) => _reply('DELETE', path, null);

  @override
  Future<String?> readToken() async => token ?? 'jwt';

  @override
  Future<void> saveToken(String t) async => token = t;

  @override
  String? get tokenSync => token ?? 'jwt';
}

class _FakeLinks implements LinkLauncher {
  final opened = <Uri>[];

  @override
  Future<bool> openExternal(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

class _FixedAuth extends AuthState {
  _FixedAuth(this._c, ApiClient api) : super(api: api, auth: CustomerAuthService(api));

  final Customer _c;

  @override
  Customer? get customer => _c;

  @override
  AgentCard? get agent => _c.agent;

  @override
  Future<bool> refresh() async => true;

  @override
  Future<void> refreshCustomer() async {}
}

Map<String, dynamic> _other(int id, String name, {bool mine = false}) => {
      'id': id,
      'full_name': name,
      'gender': 'groom',
      'status': 'active',
      'age': 29,
      'community': {'id': 1, 'name': 'Kamma'},
      'photos': <Object>[],
      'is_mine': mine,
      'interest': null,
      'masked_fields': <String>[],
    };

Map<String, dynamic> _interest(int id, int profileId, String name) => {
      'id': id,
      'status': 'pending',
      'created_at': '2026-11-12T10:00:00.000Z',
      'profile': {'id': profileId, 'full_name': name, 'gender': 'groom', 'age': 29},
    };

class _Host {
  _Host({Map<String, dynamic>? me}) {
    auth = _FixedAuth(Customer.fromJson(me ?? activeMeJson()), api);
    profiles = ProfileService(api);
    browse = BrowseState(profiles);
    interests = InterestsState(profiles);
  }

  final api = _FakeApi();
  final links = _FakeLinks();
  late final _FixedAuth auth;
  late final ProfileService profiles;
  late final BrowseState browse;
  late final InterestsState interests;

  /// What a pushed page returned.
  final popped = <Object?>[];

  Widget wrap(Widget home, {AuthState? authState}) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<ProfileService>.value(value: profiles),
          Provider<PaymentService>.value(value: PaymentService(api)),
          Provider<LinkLauncher>.value(value: links),
          ChangeNotifierProvider<AuthState>.value(value: authState ?? auth),
          ChangeNotifierProvider<BrowseState>.value(value: browse),
          ChangeNotifierProvider<InterestsState>.value(value: interests),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: home),
      );

  /// A page with a button that pushes [page].
  Widget launcher(Widget page, {AuthState? authState}) => wrap(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async =>
                    popped.add(await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        authState: authState,
      );
}

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(_button(label)).onPressed != null;

void main() {
  // ================================================================ models + service

  group('Report / block models and calls (SPEC §9.22 A / B)', () {
    test('the six reasons and their wire values', () {
      expect(ReportReason.values.map((r) => r.apiValue), [
        'fake_profile',
        'inappropriate_photo',
        'offensive_content',
        'scam_or_fraud',
        'harassment',
        'other',
      ]);
      expect(ReportReason.values.map((r) => S.reportReasonLabel(r.apiValue)), [
        'Fake profile',
        'Inappropriate photo',
        'Offensive content',
        'Scam or fraud',
        'Harassment',
        'Other',
      ]);
    });

    test('a blocked row: label as seen, date; a blank label falls back', () {
      final b = BlockedProfile.fromJson({'profile_id': 41, 'profile_label': 'Ravi', 'created_at': '2026-11-12T10:00:00Z'});
      expect(b.profileId, 41);
      expect(b.displayLabel, 'Ravi');
      expect(b.createdAt, DateTime.parse('2026-11-12T10:00:00Z').toLocal());
      expect(BlockedProfile.fromJson({'profile_id': 7, 'profile_label': ' '}).displayLabel, 'Profile 7');
    });

    test('report / block / list / unblock hit the contract routes', () async {
      final api = _FakeApi()
        ..answer('POST', '/customer/profiles/41/report', {'report': {'id': 1, 'status': 'open'}})
        ..answer('POST', '/customer/profiles/41/block', {'ok': true})
        ..answer('GET', '/customer/blocks', {
          'blocks': [
            {'profile_id': 41, 'profile_label': 'Ravi', 'created_at': '2026-11-12T10:00:00Z'},
          ],
        })
        ..answer('DELETE', '/customer/blocks/41', {'ok': true});
      final service = ProfileService(api);

      await service.reportProfile(41, ReportReason.scamOrFraud, details: '  Asked for money  ');
      await service.reportProfile(41, ReportReason.other, details: '   ');
      expect(api.bodiesFor('POST', '/customer/profiles/41/report'), [
        {'reason': 'scam_or_fraud', 'details': 'Asked for money'},
        {'reason': 'other'},
      ]);
      await service.blockProfile(41);
      expect(api.bodiesFor('POST', '/customer/profiles/41/block'), hasLength(1));
      expect((await service.blockedProfiles()).single.displayLabel, 'Ravi');
      await service.unblockProfile(41);
      expect(api.bodiesFor('DELETE', '/customer/blocks/41'), hasLength(1));
    });
  });

  // ================================================================ profile detail ⋮

  group('Profile detail ⋮ (SPEC §9.22 D)', () {
    Future<_Host> openDetail(WidgetTester tester, {bool mine = false}) async {
      await _phone(tester);
      final host = _Host();
      host.api.answer('GET', '/customer/profiles/41', {'profile': _other(41, 'Ravi Kumar', mine: mine)});
      await tester.pumpWidget(host.launcher(const ProfileDetailScreen(profileId: 41)));
      await tester.tap(find.text('open'));
      await _settle(tester);
      return host;
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip(S.moreOptions));
      await _settle(tester);
    }

    testWidgets('another family\'s profile has Report profile and Block', (tester) async {
      await openDetail(tester);
      expect(find.byTooltip(S.moreOptions), findsOneWidget);
      await openMenu(tester);
      expect(find.text(S.reportProfile), findsOneWidget);
      expect(find.text(S.block), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never on my own profile', (tester) async {
      await openDetail(tester, mine: true);
      expect(find.text('Ravi Kumar'), findsWidgets);
      expect(find.byTooltip(S.moreOptions), findsNothing);
    });

    testWidgets('Report: a reason is required; details are optional; thanks after', (tester) async {
      final host = await openDetail(tester);
      host.api.answer('POST', '/customer/profiles/41/report', {'report': {'id': 9, 'status': 'open'}});
      await openMenu(tester);
      await tester.tap(find.text(S.reportProfile));
      await _settle(tester);

      expect(find.text(S.reportProfileBody), findsOneWidget);
      for (final r in ReportReason.values) {
        expect(find.text(S.reportReasonLabel(r.apiValue)), findsOneWidget);
      }
      expect(_enabled(tester, S.submitReport), isFalse, reason: 'no reason picked yet');

      await tester.tap(find.text('Scam or fraud'));
      await tester.pump();
      expect(_enabled(tester, S.submitReport), isTrue);
      await tester.enterText(find.byType(TextField), 'Asked for money before meeting');
      await tester.ensureVisible(find.text(S.submitReport));
      await tester.tap(find.text(S.submitReport));
      await _settle(tester);

      expect(host.api.bodiesFor('POST', '/customer/profiles/41/report').single, {
        'reason': 'scam_or_fraud',
        'details': 'Asked for money before meeting',
      });
      expect(find.text(S.reportProfileBody), findsNothing, reason: 'the sheet closed');
      expect(find.text(S.reportThanks), findsOneWidget);
      expect(find.byType(ProfileDetailScreen), findsOneWidget, reason: 'reporting does not leave the page');
    });

    for (final (status, code, message) in [
      (400, 'own_profile', 'You cannot report your own profile.'),
      (404, 'not_found', 'Profile not found.'),
    ]) {
      testWidgets('Report fails with $status $code → the server\'s message, the sheet stays', (tester) async {
        final host = await openDetail(tester);
        host.api.answer('POST', '/customer/profiles/41/report', ApiException(code, message, status: status));
        await openMenu(tester);
        await tester.tap(find.text(S.reportProfile));
        await _settle(tester);
        await tester.tap(find.text('Fake profile'));
        await tester.pump();
        await tester.ensureVisible(find.text(S.submitReport));
        await tester.tap(find.text(S.submitReport));
        await _settle(tester);
        expect(find.text(message), findsOneWidget);
        expect(find.text(S.reportProfileBody), findsOneWidget);
        expect(find.text(S.reportThanks), findsNothing);
      });
    }

    testWidgets('Block: Cancel keeps everything; confirm blocks, leaves and drops it from my lists', (tester) async {
      await _phone(tester);
      final host = _Host();
      host.api
        ..answer('GET', '/customer/profiles', {
          'profiles': [_other(41, 'Ravi Kumar'), _other(42, 'Suresh')],
          'total': 2,
          'page': 1,
          'access': 'full',
        })
        ..answer('GET', '/customer/interests', {
          'interests': [_interest(5, 41, 'Ravi Kumar'), _interest(6, 42, 'Suresh')],
        })
        ..answer('GET', '/customer/interests', {
          'interests': [_interest(6, 42, 'Suresh')],
        })
        ..answer('GET', '/customer/profiles/41', {'profile': _other(41, 'Ravi Kumar')})
        ..answer('POST', '/customer/profiles/41/block', {'ok': true});
      final customerId = host.auth.customer!.id;
      await host.browse.ensureLoaded(customerId);
      await host.interests.load(customerId);
      expect(host.browse.profiles.map((p) => p.id), [41, 42]);

      await tester.pumpWidget(host.launcher(const ProfileDetailScreen(profileId: 41)));
      await tester.tap(find.text('open'));
      await _settle(tester);

      // Cancel.
      await tester.tap(find.byTooltip(S.moreOptions));
      await _settle(tester);
      await tester.tap(find.text(S.block));
      await _settle(tester);
      expect(find.text(S.blockTitle), findsOneWidget);
      expect(find.text(S.blockBody), findsOneWidget);
      await tester.tap(find.text(S.cancel));
      await _settle(tester);
      expect(host.api.bodiesFor('POST', '/customer/profiles/41/block'), isEmpty);
      expect(find.byType(ProfileDetailScreen), findsOneWidget);

      // Block.
      await tester.tap(find.byTooltip(S.moreOptions));
      await _settle(tester);
      await tester.tap(find.text(S.block));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, S.block));
      await _settle(tester);
      expect(host.api.bodiesFor('POST', '/customer/profiles/41/block'), hasLength(1));
      expect(find.byType(ProfileDetailScreen), findsNothing, reason: 'back to where I came from');
      expect(find.text(S.profileBlocked), findsOneWidget);
      expect(host.browse.profiles.map((p) => p.id), [42]);
      expect(host.browse.total, 1);
      expect(host.api.bodiesFor('GET', '/customer/interests'), hasLength(2), reason: 'interests reloaded');
      expect(host.interests.interests.map((i) => i.profile!.id), [42]);
    });

    testWidgets('Block fails → a message, the page stays', (tester) async {
      final host = await openDetail(tester);
      host.api.answer('POST', '/customer/profiles/41/block', ApiException('network_error', 'offline'));
      await tester.tap(find.byTooltip(S.moreOptions));
      await _settle(tester);
      await tester.tap(find.text(S.block));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, S.block));
      await _settle(tester);
      expect(find.text(S.errNetwork), findsOneWidget);
      expect(find.byType(ProfileDetailScreen), findsOneWidget);
    });
  });

  // ================================================================ Blocked profiles

  group('Blocked profiles (SPEC §9.22 B)', () {
    testWidgets('lists them; Unblock removes the row; the last one leaves the empty state', (tester) async {
      await _phone(tester);
      final host = _Host();
      host.api
        ..answer('GET', '/customer/blocks', {
          'blocks': [
            {'profile_id': 41, 'profile_label': 'Ravi Kumar', 'created_at': '2026-11-12T10:00:00Z'},
            {'profile_id': 42, 'profile_label': 'Suresh', 'created_at': '2026-11-10T10:00:00Z'},
          ],
        })
        ..answer('DELETE', '/customer/blocks/41', {'ok': true})
        ..answer('DELETE', '/customer/blocks/42', {'ok': true});
      await tester.pumpWidget(host.wrap(const BlockedProfilesScreen()));
      await _settle(tester);
      expect(find.text('Ravi Kumar'), findsOneWidget);
      expect(find.text('Suresh'), findsOneWidget);
      expect(find.text(S.blockedOn(formatDate(DateTime.parse('2026-11-12T10:00:00Z')))), findsOneWidget);
      expect(find.text(S.unblock), findsNWidgets(2));

      await tester.tap(find.text(S.unblock).first);
      await _settle(tester);
      expect(host.api.bodiesFor('DELETE', '/customer/blocks/41'), hasLength(1));
      expect(find.text('Ravi Kumar'), findsNothing);
      expect(find.text(S.unblockedSnack('Ravi Kumar')), findsOneWidget);

      await tester.tap(find.text(S.unblock));
      await _settle(tester);
      expect(host.api.bodiesFor('DELETE', '/customer/blocks/42'), hasLength(1));
      expect(find.text(S.noBlockedTitle), findsOneWidget);
      expect(find.text(S.noBlockedBody), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('none yet → the empty state', (tester) async {
      await _phone(tester);
      final host = _Host();
      host.api.answer('GET', '/customer/blocks', {'blocks': <Object>[]});
      await tester.pumpWidget(host.wrap(const BlockedProfilesScreen()));
      await _settle(tester);
      expect(find.text(S.noBlockedTitle), findsOneWidget);
      expect(find.text(S.noBlockedBody), findsOneWidget);
    });

    testWidgets('a failed load offers Retry', (tester) async {
      await _phone(tester);
      final host = _Host();
      host.api
        ..answer('GET', '/customer/blocks', ApiException('network_error', 'offline'))
        ..answer('GET', '/customer/blocks', {'blocks': <Object>[]});
      await tester.pumpWidget(host.wrap(const BlockedProfilesScreen()));
      await _settle(tester);
      expect(find.text(S.errNetwork), findsOneWidget);
      await tester.tap(find.text(S.retry));
      await _settle(tester);
      expect(find.text(S.noBlockedTitle), findsOneWidget);
    });

    testWidgets('More → Blocked profiles opens it', (tester) async {
      await _phone(tester);
      final host = _Host(me: guestMeJson());
      host.api.answer('GET', '/customer/blocks', {'blocks': <Object>[]});
      await tester.pumpWidget(host.wrap(const MoreScreen()));
      await tester.scrollUntilVisible(find.text(S.blockedProfiles), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text(S.blockedProfilesSubtitle), findsOneWidget);
      await tester.tap(find.text(S.blockedProfiles));
      await _settle(tester);
      expect(find.byType(BlockedProfilesScreen), findsOneWidget);
      expect(host.api.bodiesFor('GET', '/customer/blocks'), hasLength(1));
    });
  });

  // ================================================================ terms at signup

  group('Terms consent at signup (SPEC §9.22 C)', () {
    const signupPath = '/customer/auth/signup';

    Future<(_Host, AuthState)> render(WidgetTester tester) async {
      await _phone(tester);
      final host = _Host();
      final auth = AuthState(api: host.api, auth: CustomerAuthService(host.api));
      host.api.answer('POST', signupPath, {'token': 'jwt-new', 'customer': guestMeJson()});
      await tester.pumpWidget(host.launcher(
        const SignupScreen(phone: '9876543210', verificationToken: 'vt-1'),
        authState: auth,
      ));
      await tester.tap(find.text('open'));
      await _settle(tester);
      return (host, auth);
    }

    /// Name + password + confirmation (SPEC §9.24 C).
    Future<void> fillIn(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(TextFormField, S.fullName), 'Srinivasa Reddy');
      await tester.enterText(find.widgetWithText(TextFormField, S.password), 'secret12');
      await tester.enterText(find.widgetWithText(TextFormField, S.confirmPassword), 'secret12');
      await tester.pump();
    }

    testWidgets('Create account stays off until the box is ticked; then accepted_terms is sent', (tester) async {
      final (host, auth) = await render(tester);
      expect(find.textContaining('I agree to the'), findsOneWidget);
      await fillIn(tester);
      expect(_enabled(tester, S.createAccount), isFalse);

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(_enabled(tester, S.createAccount), isTrue);
      await tester.ensureVisible(find.text(S.createAccount));
      await tester.tap(find.text(S.createAccount));
      await _settle(tester);

      expect(host.api.bodiesFor('POST', signupPath).single, {
        'full_name': 'Srinivasa Reddy',
        'phone': '9876543210',
        'password': 'secret12',
        'phone_verification_token': 'vt-1',
        'accepted_terms': true,
      });
      expect(auth.phase, AuthPhase.loggedIn);
      expect(find.byType(SignupScreen), findsNothing);
    });

    testWidgets('both phrases open their page in the browser; the sentence ticks the box', (tester) async {
      final (host, _) = await render(tester);
      await tester.tapOnText(find.textRange.ofSubstring(S.termsLink));
      await tester.pump();
      await tester.tapOnText(find.textRange.ofSubstring(S.privacyLink));
      await tester.pump();
      expect(host.links.opened, [
        Uri.parse('${AppConfig.apiBaseUrl}/terms'),
        Uri.parse('${AppConfig.apiBaseUrl}/privacy/matrimony'),
      ]);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse, reason: 'links do not tick it');

      await tester.tapOnText(find.textRange.ofSubstring('I agree'));
      await tester.pump();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    });

    testWidgets('"Done" on the keyboard before ticking asks for it, sends nothing', (tester) async {
      final (host, _) = await render(tester);
      await fillIn(tester);
      // "Done" on the last field (the confirmation).
      await tester.showKeyboard(find.widgetWithText(TextFormField, S.confirmPassword));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);
      expect(find.text(S.termsRequired), findsOneWidget);
      expect(host.api.bodiesFor('POST', signupPath), isEmpty);

      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.text(S.termsRequired), findsNothing);
    });
  });
}
