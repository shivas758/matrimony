import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/models/master_data.dart';
import 'package:gandharva/models/profile.dart';
import 'package:gandharva/models/publish.dart';
import 'package:gandharva/services/agents_service.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/services/customer_auth_service.dart';
import 'package:gandharva/services/payment_service.dart';
import 'package:gandharva/services/profile_service.dart';
import 'package:gandharva/state/auth_state.dart';
import 'package:gandharva/state/browse_filters.dart';
import 'package:gandharva/state/masters_state.dart';
import 'package:gandharva/ui/screens/agent/change_agent_screen.dart';
import 'package:gandharva/ui/screens/browse/filter_sheet.dart';
import 'package:gandharva/ui/screens/browse/profile_detail_screen.dart';
import 'package:gandharva/ui/screens/more_screen.dart';
import 'package:gandharva/ui/screens/my_profile/my_profile_screen.dart';
import 'package:gandharva/ui/screens/my_profile/privacy_screen.dart';
import 'package:gandharva/ui/screens/my_profile/profile_form_screen.dart';
import 'package:gandharva/ui/screens/my_profile/profile_preview_screen.dart';
import 'package:gandharva/ui/screens/publish/publish_screen.dart';
import 'package:gandharva/ui/strings.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:gandharva/ui/widgets/common.dart';
import 'package:gandharva/ui/widgets/searchable_list.dart';
import 'package:gandharva/ui/widgets/step_header.dart';
import 'package:provider/provider.dart';

import 'guest_mode_test.dart' show activeMeJson, guestMeJson, ownSummary;
import 'models_test.dart' show protectedJson, publicProfileJson;
import 'wedbook_test.dart' show mastersJson, ownProfileJson;

// SPEC §9.23 (v2.13 server, Wedbook Matrimony 3.4.0): gift codes, approved
// agents with "N clients", publish last, "View as others see it", search
// inside long lists.

// ================================================================ fixtures

/// Agent A as `/customer/auth/me` carries it since v2.13: with live_clients.
Map<String, dynamic> agentAJson() => {
      ...(activeMeJson()['agent'] as Map<String, dynamic>),
      'agent_code': 'KA1A',
      'live_clients': 12,
    };

/// A guest who filled in the profile first (no agent yet) — publish last.
Map<String, dynamic> guestWithProfileJson() => {
      ...guestMeJson(),
      'has_profile': true,
      'profile_id': 80,
      'profiles': [ownSummary(80, 'Sita', 'bride', 'payment_pending', paid: false)],
      'unlock': {'agent_linked': false, 'profile_registered': true, 'paid': false, 'approved': false},
    };

/// Agent linked, profile not paid.
Map<String, dynamic> pendingUnpaidJson() => {
      ...guestWithProfileJson(),
      'status': 'pending',
      'agent': agentAJson(),
      'unlock': {'agent_linked': true, 'profile_registered': true, 'paid': false, 'approved': false},
    };

/// Paid, waiting for the agent.
Map<String, dynamic> pendingPaidJson() => {
      ...pendingUnpaidJson(),
      'profiles': [ownSummary(80, 'Sita', 'bride', 'awaiting_approval')],
      'unlock': {'agent_linked': true, 'profile_registered': true, 'paid': true, 'approved': false},
    };

/// After a gift code: linked, approved, paid, live.
Map<String, dynamic> liveJson() => {
      ...pendingPaidJson(),
      'status': 'active',
      'access': 'full',
      'profiles': [
        {...ownSummary(80, 'Sita', 'bride', 'live'), 'paid_via': 'gift'},
      ],
      'unlock': {'agent_linked': true, 'profile_registered': true, 'paid': true, 'approved': true},
    };

/// GET /customer/agents/recommended (SPEC §9.23 C).
Map<String, dynamic> recommendedJson() => {
      'agents': [
        {
          'id': 8,
          'full_name': 'Anitha',
          'agency_name': 'Anitha Matrimony',
          'city': 'Guntur',
          'phone': '9000000008',
          'agent_code': 'AP3C',
          'communities': [
            {'id': 1, 'name': 'Kamma'},
          ],
          'live_clients': 12,
          'match': 'city',
        },
        {
          'id': 9,
          'full_name': 'Bhaskar',
          'agency_name': null,
          'city': 'Vijayawada',
          'phone': '9000000009',
          'agent_code': 'AP4A',
          'communities': [
            {'id': 1, 'name': 'Kamma'},
            {'id': 2, 'name': 'Reddy'},
          ],
          'live_clients': '1',
          'match': 'state',
        },
      ],
      'based_on': {
        'community': {'id': 1, 'name': 'Kamma'},
        'city': 'Guntur',
        'state': 'Andhra Pradesh',
      },
    };

/// The preview before an interest is accepted: name and income switched off.
Map<String, dynamic> previewBeforeJson() => {
      ...publicProfileJson(),
      'id': 77,
      'full_name': 'Profile 77',
      'income_text': null,
      'masked_fields': ['name', 'income'],
      'is_mine': false,
      'preview': true,
      'contact_access': 'none',
      'interest': null,
    };

/// … and after: everything, with the on-request block and a made-up interest.
Map<String, dynamic> previewAfterJson() => {
      ...publicProfileJson(),
      ...protectedJson(),
      'id': 77,
      'full_name': 'Priya',
      'masked_fields': [],
      'is_mine': false,
      'preview': true,
      'contact_access': 'granted',
      'interest': {'status': 'accepted', 'days_left': 15},
    };

/// Ten communities — longer than eight, so they get a search box.
Map<String, dynamic> longMastersJson() => {
      ...mastersJson(),
      'communities': [
        for (final (id, name) in const [
          (1, 'Kamma'),
          (2, 'Reddy'),
          (3, 'Kapu'),
          (4, 'Brahmin'),
          (5, 'Vysya'),
          (6, 'Velama'),
          (7, 'Raju'),
          (8, 'Yadava'),
          (9, 'Gowda'),
          (10, 'Lingayat'),
        ])
          {'id': id, 'name': name},
      ],
    };

// ================================================================ fakes

class _FakeAuth extends AuthState {
  _FakeAuth(this._c, ApiClient api) : super(api: api, auth: CustomerAuthService(api));

  Customer _c;
  int refreshes = 0;

  @override
  Customer? get customer => _c;

  @override
  AgentCard? get agent => _c.agent;

  @override
  Future<bool> refresh() async {
    refreshes++;
    return true;
  }

  @override
  Future<void> refreshCustomer() async => refreshes++;

  @override
  void setCustomer(Customer customer) {
    _c = customer;
    notifyListeners();
  }
}

class _FakeAgents extends AgentsService {
  _FakeAgents(super.api);

  RecommendedAgents recommendation = RecommendedAgents.fromJson(recommendedJson());
  Customer linked = Customer.fromJson(pendingUnpaidJson());
  int recommendedCalls = 0;
  int? agentId;
  String? code;
  String? phone;

  @override
  Future<RecommendedAgents> recommended() async {
    recommendedCalls++;
    return recommendation;
  }

  @override
  Future<Customer> linkAgent({String? agentPhone, String? agentCode, int? agentId}) async {
    phone = agentPhone;
    code = agentCode;
    this.agentId = agentId;
    return linked;
  }

  @override
  Future<List<AgentCard>> directory({String? q, int? communityId, String? city}) async => [
        AgentCard.fromJson({...recommendedJson()['agents'][0] as Map<String, dynamic>}),
      ];
}

class _FakePayments extends PaymentService {
  _FakePayments(super.api, {super.playStore = false});

  GiftCodeResult? result;
  ApiException? failWith;
  (int, String)? redeemed;

  @override
  Future<GiftCodeResult> redeemGiftCode(int profileId, String code) async {
    redeemed = (profileId, code);
    if (failWith != null) throw failWith!;
    return result!;
  }
}

class _FakeProfiles extends ProfileService {
  _FakeProfiles(super.api, {Map<String, dynamic>? masters, Map<String, dynamic>? own})
      : _masters = masters ?? mastersJson(),
        _own = own ?? ownProfileJson();

  final Map<String, dynamic> _masters;
  final Map<String, dynamic> _own;
  final previews = <(int, bool)>[];
  Map<String, dynamic>? created;
  Map<String, dynamic>? patched;

  @override
  Future<MasterData> masters() async => MasterData.fromJson(_masters);

  @override
  Future<Profile> myProfile(int id) async => Profile.fromJson(_own);

  @override
  Future<Profile> preview(int id, {bool after = false}) async {
    previews.add((id, after));
    return Profile.fromJson(after ? previewAfterJson() : previewBeforeJson());
  }

  @override
  Future<Profile> createProfile(Map<String, dynamic> fields, List<String> photoPaths) async {
    created = fields;
    return Profile.fromJson({..._own, 'full_name': fields['full_name'], 'paid': false, 'visibility': 'payment_pending'});
  }

  @override
  Future<Profile> updateProfile(int id, Map<String, dynamic> fields) async {
    patched = fields;
    return Profile.fromJson(_own);
  }
}

class _Host {
  _Host(Map<String, dynamic> me, {Map<String, dynamic>? masters, Map<String, dynamic>? own, bool playStore = false})
      : customer = Customer.fromJson(me) {
    profiles = _FakeProfiles(api, masters: masters, own: own);
    agents = _FakeAgents(api);
    payments = _FakePayments(api, playStore: playStore);
    auth = _FakeAuth(customer, api);
  }

  final Customer customer;
  final api = ApiClient();
  late final _FakeProfiles profiles;
  late final _FakeAgents agents;
  late final _FakePayments payments;
  late final _FakeAuth auth;

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          Provider<ProfileService>.value(value: profiles),
          Provider<AgentsService>.value(value: agents),
          Provider<PaymentService>.value(value: payments),
          ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profiles)),
          ChangeNotifierProvider<AuthState>.value(value: auth),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: child),
      );
}

/// Answers GET / POST by path; records every call.
class _RecordingApi extends ApiClient {
  final calls = <(String, String, Object?)>[];
  final answers = <String, Object>{};

  Object _answer(String path) {
    final a = answers[path];
    if (a == null) throw StateError('unexpected call $path');
    if (a is ApiException) throw a;
    return a;
  }

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    calls.add(('GET', path, query));
    return _answer(path) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    calls.add(('POST', path, body));
    return _answer(path) as Map<String, dynamic>;
  }
}

Future<void> _phone(WidgetTester tester, {Size size = const Size(1080, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Replaces the tree so the screens' poll timers are disposed.
Future<void> _dispose(WidgetTester tester) => tester.pumpWidget(const SizedBox.shrink());

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await tester.pump();
}

/// Scrolls [f] to the middle of its list (clear of the bars above and below).
Future<void> _center(WidgetTester tester, Finder f) async {
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pump();
}

/// Lets a focus scroll finish (a blinking cursor never "settles"), then taps.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.pump(const Duration(milliseconds: 500));
  await _center(tester, f);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(f);
}

Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

void main() {
  // ================================================================ models

  group('Models (SPEC §9.23)', () {
    test('live_clients: a number, a numeric string, absent / garbage → unknown', () {
      AgentCard card(Object? v) => AgentCard.fromJson({'id': 1, 'full_name': 'A', 'live_clients': ?v});
      expect(card(12).liveClients, 12);
      expect(card('7').liveClients, 7);
      expect(card(null).liveClients, isNull, reason: 'an older server sends no count');
      expect(card('lots').liveClients, isNull);
      expect(card(-1).liveClients, isNull);
      expect(Customer.fromJson(pendingUnpaidJson()).agent!.liveClients, 12, reason: 'me → customer.agent');
      expect(Customer.fromJson(activeMeJson()).agent!.liveClients, isNull);
    });

    test('"N clients"', () {
      expect(S.clientsCount(1), '1 client');
      expect(S.clientsCount(0), '0 clients');
      expect(S.clientsCount(12), '12 clients');
    });

    test('recommended agents: rows with live_clients and match, and what they were based on', () {
      final r = RecommendedAgents.fromJson(recommendedJson());
      expect(r.agents.map((a) => a.fullName), ['Anitha', 'Bhaskar']);
      expect(r.agents.first.liveClients, 12);
      expect(r.agents.first.match, 'city');
      expect(r.agents.first.agentCode, 'AP3C');
      expect(r.agents.last.liveClients, 1);
      expect(r.agents.last.communities.map((c) => c.name), ['Kamma', 'Reddy']);
      expect(r.basedOn!.community!.name, 'Kamma');
      expect(r.basedOn!.label, 'Kamma · Guntur, Andhra Pradesh');
    });

    test('no profile yet → no recommendations; junk rows are skipped', () {
      final none = RecommendedAgents.fromJson({'agents': [], 'based_on': null});
      expect(none.agents, isEmpty);
      expect(none.basedOn, isNull);
      final odd = RecommendedAgents.fromJson({
        'agents': [
          'x',
          {'full_name': 'no id'},
          {'id': 3, 'full_name': 'Ok'},
        ],
        'based_on': {'community': null, 'city': ' ', 'state': 'Karnataka'},
      });
      expect(odd.agents.single.fullName, 'Ok');
      expect(odd.basedOn!.label, 'Karnataka');
      expect(RecommendedAgents.fromJson(const {}).agents, isEmpty);
    });

    test('gift-code answer: the account and my profile', () {
      final r = GiftCodeResult.fromJson({
        'customer': liveJson(),
        'profile': {...ownProfileJson(), 'id': 80, 'paid_via': 'gift', 'visibility': 'live'},
      });
      expect(r.customer.isActive, isTrue);
      expect(r.customer.profiles.single.paidVia, 'gift');
      expect(r.profile!.paidVia, 'gift');
      expect(r.profile!.needsPublishing, isFalse);
      expect(GiftCodeResult.fromJson({'customer': liveJson()}).profile, isNull);
    });

    test('paid_via, the preview flag and the preview\'s id-less interest', () {
      expect(Profile.fromJson({...ownProfileJson(), 'paid_via': 'cash'}).paidVia, 'cash');
      expect(Profile.fromJson(ownProfileJson()).paidVia, isNull);
      final after = Profile.fromJson(previewAfterJson());
      expect(after.isPreview, isTrue);
      expect(after.isMine, isFalse);
      expect(after.interest!.isLive, isTrue);
      expect(after.accessDaysLeft, 15);
      expect(after.detailsShared, isTrue);
      final before = Profile.fromJson(previewBeforeJson());
      expect(before.detailsShared, isFalse);
      expect(before.nameHidden, isTrue);
      expect(S.paidViaLine('gift'), 'Fee: covered by a gift code');
    });

    test('needsPublishing: payment pending / awaiting approval; not live or hidden', () {
      bool needs(String? visibility, {bool paid = false}) =>
          Profile.fromJson({...ownProfileJson(), 'visibility': visibility, 'paid': paid, 'paid_at': null}).needsPublishing;
      expect(needs('payment_pending'), isTrue);
      expect(needs('awaiting_approval', paid: true), isTrue);
      expect(needs('live', paid: true), isFalse);
      expect(needs('hidden', paid: true), isFalse, reason: 'published — the agent hid it');
      expect(needs(null), isTrue, reason: 'an older server: unpaid');
      expect(needs(null, paid: true), isFalse);
      expect(ProfileSummary.fromJson(ownSummary(80, 'Sita', 'bride', 'payment_pending', paid: false)).needsPublishing,
          isTrue);
    });

    test('the publish step: agent → payment → approval → live, in either order', () {
      expect(PublishStep.from(hasAgent: false, paid: false, approved: false), PublishStep.agent);
      expect(PublishStep.from(hasAgent: true, paid: false, approved: false), PublishStep.payment);
      expect(PublishStep.from(hasAgent: true, paid: false, approved: true), PublishStep.payment,
          reason: 'approved first, the fee still to pay');
      expect(PublishStep.from(hasAgent: true, paid: true, approved: false), PublishStep.approval);
      expect(PublishStep.from(hasAgent: true, paid: true, approved: true), PublishStep.live);

      PublishStep of(Map<String, dynamic> me) {
        final c = Customer.fromJson(me);
        return PublishStep.of(c, c.profiles.first);
      }

      expect(of(guestWithProfileJson()), PublishStep.agent);
      expect(of(pendingUnpaidJson()), PublishStep.payment);
      expect(of(pendingPaidJson()), PublishStep.approval);
      expect(of(liveJson()), PublishStep.live);
      // No profile row: the account's checklist decides.
      expect(PublishStep.of(Customer.fromJson({...pendingPaidJson(), 'profiles': []})), PublishStep.approval);
    });

    test('gift-code errors: the server\'s sentence; ours when it sent none', () {
      expect(
        giftCodeMessage(ApiException('gift_code_other_agent', 'This code is from agent KA2B.', status: 409)),
        'This code is from agent KA2B.',
      );
      expect(giftCodeMessage(ApiException('gift_code_not_found', '', status: 404)), S.errGiftCodeNotFound);
      expect(giftCodeMessage(ApiException('gift_code_used', ' ', status: 409)), S.errGiftCodeUsed);
      expect(giftCodeMessage(ApiException('too_many_attempts', '', status: 429)), S.errGiftCodeTooMany,
          reason: 'not the OTP wording');
      expect(giftCodeMessage(ApiException('agent_not_active', "That agent's account is paused", status: 400)),
          "That agent's account is paused");
      expect(giftCodeMessage(ApiException('network_error', 'SocketException')), S.errNetwork);
    });
  });

  // ================================================================ services

  group('Service wiring (SPEC §9.23 B / C / D)', () {
    test('redeem: POST /customer/my-profiles/:id/gift-code {code} as typed (trimmed)', () async {
      final api = _RecordingApi()
        ..answers['/customer/my-profiles/80/gift-code'] = {
          'customer': liveJson(),
          'profile': {...ownProfileJson(), 'id': 80, 'paid_via': 'gift'},
        };
      final r = await PaymentService(api, playStore: true).redeemGiftCode(80, '  wb-k7m2qx ');
      final (method, path, body) = api.calls.single;
      expect((method, path), ('POST', '/customer/my-profiles/80/gift-code'));
      expect(body, {'code': 'wb-k7m2qx'});
      expect(r.customer.isActive, isTrue);
      expect(r.profile!.paidVia, 'gift');
    });

    test('redeem errors come through as ApiException', () async {
      final api = _RecordingApi()
        ..answers['/customer/my-profiles/80/gift-code'] =
            ApiException('gift_code_used', 'This gift code has already been used.', status: 409);
      expect(
        () => PaymentService(api).redeemGiftCode(80, 'WB-K7M2QX'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'gift_code_used')),
      );
    });

    test('recommended: GET /customer/agents/recommended; a 404 (older server) → none', () async {
      final api = _RecordingApi()..answers['/customer/agents/recommended'] = recommendedJson();
      final r = await AgentsService(api).recommended();
      expect(api.calls.single.$2, '/customer/agents/recommended');
      expect(r.agents, hasLength(2));

      final old = _RecordingApi()..answers['/customer/agents/recommended'] = ApiException('not_found', 'Not found', status: 404);
      expect((await AgentsService(old).recommended()).agents, isEmpty);

      final down = _RecordingApi()..answers['/customer/agents/recommended'] = ApiException('server_error', 'x', status: 500);
      expect(() => AgentsService(down).recommended(), throwsA(isA<ApiException>()));
    });

    test('preview: GET /customer/my-profiles/:id/preview?as=before|after', () async {
      final api = _RecordingApi()..answers['/customer/my-profiles/77/preview'] = {'profile': previewAfterJson()};
      final service = ProfileService(api);
      final after = await service.preview(77, after: true);
      await service.preview(77);
      expect(api.calls.map((c) => c.$3), [
        {'as': 'after'},
        {'as': 'before'},
      ]);
      expect(after.isPreview, isTrue);
      expect(after.fatherName, 'Venkat Rao');
    });
  });

  // ================================================================ publish screen

  group('Publish my profile (SPEC §9.23 F)', () {
    Future<_Host> open(WidgetTester tester, Map<String, dynamic> me, {bool playStore = false}) async {
      await _phone(tester);
      final host = _Host(me, playStore: playStore);
      await tester.pumpWidget(host.wrap(const PublishScreen(profileId: 80)));
      await tester.pump(); // refresh + recommendations asked
      await tester.pump(); // recommendations answered
      return host;
    }

    StepHeader header(WidgetTester tester) => tester.widget<StepHeader>(find.byType(StepHeader));

    testWidgets('no agent → the agent step: gift code, recommended (N clients), directory, number or code',
        (tester) async {
      final host = await open(tester, guestWithProfileJson());
      expect(find.text(S.publishMyProfile), findsOneWidget, reason: 'the title');
      expect(header(tester).current, 0);
      expect(header(tester).labels, [S.publishStepAgent, S.publishStepPayment, S.publishStepApproval]);
      expect(find.text(S.giftCodeQuestion), findsOneWidget);
      expect(find.text(S.giftCodeLabel), findsOneWidget);
      expect(host.agents.recommendedCalls, 1);

      await _scrollTo(tester, find.text(S.recommendedTitle.toUpperCase()));
      expect(find.text('${S.recommendedBasedOn} · Kamma · Guntur, Andhra Pradesh'), findsOneWidget);
      await _scrollTo(tester, find.text('Anitha'));
      expect(find.text('Anitha Matrimony · Guntur'), findsOneWidget);
      expect(find.text('Agent code AP3C'), findsOneWidget);
      expect(find.text(S.clientsCount(12)), findsOneWidget);
      await _scrollTo(tester, find.text('Bhaskar'));
      expect(find.text(S.clientsCount(1)), findsOneWidget);
      expect(find.byTooltip(S.call), findsWidgets, reason: 'each card can call the agent');

      await _scrollTo(tester, find.text(S.enterAgentNumberOrCode));
      expect(find.text(S.searchAllAgents), findsOneWidget);
      expect(find.text(S.agentPhoneLink), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('Choose a recommended agent → confirm → linked → the payment step', (tester) async {
      final host = await open(tester, guestWithProfileJson());
      await _scrollTo(tester, find.text(S.choose).first);
      await tester.tap(find.text(S.choose).first);
      await tester.pumpAndSettle();
      expect(find.text(S.chooseAgentConfirm('Anitha')), findsOneWidget);
      await tester.tap(find.text(S.choose).last);
      await tester.pump();
      await tester.pump();
      expect(host.agents.agentId, 8);
      expect(host.auth.refreshes, greaterThan(0), reason: 'the account is re-read after the link');
      expect(header(tester).current, 1);
      expect(_button(S.payFee(150)), findsOneWidget);
      expect(find.text(S.useGiftCode), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('the agent\'s number or code links from here too', (tester) async {
      final host = await open(tester, guestWithProfileJson());
      await _scrollTo(tester, find.text(S.agentPhoneLink));
      await tester.enterText(find.widgetWithText(TextField, S.agentPhoneOrCodeHint), 'ka1a');
      await _tap(tester, find.text(S.agentPhoneLink));
      await tester.pump();
      await tester.pump();
      expect(host.agents.code, 'KA1A');
      expect(header(tester).current, 1, reason: 'on to the payment');
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('a gift code from the agent step links, pays and publishes at once', (tester) async {
      final host = await open(tester, guestWithProfileJson());
      host.payments.result = GiftCodeResult.fromJson({
        'customer': liveJson(),
        'profile': {...ownProfileJson(), 'id': 80, 'paid_via': 'gift', 'visibility': 'live'},
      });
      await tester.enterText(find.byKey(const ValueKey('gift-code-field')), ' wb-k7m2qx ');
      await _tap(tester, find.text(S.giftCodeApply));
      await tester.pump();
      await tester.pump();
      expect(host.payments.redeemed, (80, 'wb-k7m2qx'));
      expect(find.text(S.publishLiveTitle), findsOneWidget);
      expect(find.byType(StepHeader), findsNothing);
      expect(find.text(S.giftCodeApplied), findsOneWidget, reason: 'the snack survives the step change');
      expect(host.auth.refreshes, greaterThan(0));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('a refused code: the server\'s sentence under the field; nothing changes', (tester) async {
      final host = await open(tester, guestWithProfileJson());
      host.payments.failWith =
          ApiException('gift_code_used', 'This gift code was already used on 12 Nov.', status: 409);
      await tester.enterText(find.byKey(const ValueKey('gift-code-field')), 'WB-K7M2QX');
      await _tap(tester, find.text(S.giftCodeApply));
      await tester.pump();
      await tester.pump();
      expect(find.text('This gift code was already used on 12 Nov.'), findsOneWidget);
      expect(header(tester).current, 0);

      // Empty → asks for it, sends nothing.
      host.payments.redeemed = null;
      await tester.enterText(find.byKey(const ValueKey('gift-code-field')), '  ');
      await _tap(tester, find.text(S.giftCodeApply));
      await tester.pump();
      expect(find.text(S.giftCodeEmpty), findsOneWidget);
      expect(host.payments.redeemed, isNull);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('agent but unpaid → the payment step: agent card with Change, Pay ₹150, Use a gift code',
        (tester) async {
      await open(tester, pendingUnpaidJson());
      expect(header(tester).current, 1);
      expect(header(tester).completed, {0});
      expect(find.text('Agent A'), findsOneWidget);
      expect(find.text(S.clientsCount(12)), findsOneWidget, reason: 'the agent card');
      expect(find.text(S.change), findsOneWidget, reason: 'not active yet');
      expect(_button(S.payFee(150)), findsOneWidget);
      expect(find.byKey(const ValueKey('gift-code-field')), findsNothing);
      await tester.tap(find.text(S.useGiftCode));
      await tester.pump();
      expect(find.byKey(const ValueKey('gift-code-field')), findsOneWidget);

      // Change → back to the agent step (with Cancel).
      await tester.tap(find.text(S.change));
      await tester.pump();
      await tester.pump();
      expect(header(tester).current, 0);
      await _scrollTo(tester, find.text(S.cancel));
      await tester.tap(find.text(S.cancel));
      await tester.pump();
      expect(header(tester).current, 1);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('the Play build: no Pay, the neutral note, the gift code straight away', (tester) async {
      await open(tester, {...pendingUnpaidJson(), 'payment_provider': 'upi'}, playStore: true);
      expect(header(tester).current, 1);
      expect(find.text(S.paymentUnavailable), findsOneWidget);
      expect(find.text(S.payFee(150)), findsNothing);
      expect(find.byKey(const ValueKey('gift-code-field')), findsOneWidget, reason: 'gift codes still work');
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('paid, not approved → waiting for the agent, with Call and Check again', (tester) async {
      final host = await open(tester, pendingPaidJson());
      expect(header(tester).current, 2);
      expect(header(tester).completed, {0, 1});
      expect(find.text(S.publishWaitingTitle), findsOneWidget);
      expect(find.text(S.publishWaitingBody('Agent A')), findsOneWidget);
      expect(find.text(S.call), findsOneWidget);
      final before = host.auth.refreshes;
      await tester.tap(find.text(S.checkAgain));
      await tester.pump();
      expect(host.auth.refreshes, before + 1);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('paid and approved → "Your profile is live"', (tester) async {
      await open(tester, liveJson());
      expect(find.text(S.publishLiveTitle), findsOneWidget);
      expect(find.text(S.publishLiveBody), findsOneWidget);
      expect(find.byType(StepHeader), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('fits a narrow phone (320 dp) on every step', (tester) async {
      for (final me in [guestWithProfileJson(), pendingUnpaidJson(), pendingPaidJson(), liveJson()]) {
        await _phone(tester, size: const Size(960, 1800));
        final host = _Host(me);
        await tester.pumpWidget(host.wrap(const PublishScreen(profileId: 80)));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _dispose(tester);
      }
    });
  });

  // ================================================================ "N clients" elsewhere

  group('"N clients" on the directory and My agent (SPEC §9.23 F)', () {
    testWidgets('directory rows', (tester) async {
      await _phone(tester);
      final host = _Host(guestWithProfileJson());
      await tester.pumpWidget(host.wrap(const ChangeAgentScreen(link: true)));
      await tester.pump();
      await tester.pump();
      await _scrollTo(tester, find.text(S.clientsCount(12)));
      expect(find.text(S.clientsCount(12)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('My agent on More; an older server (no count) shows none', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_Host(pendingUnpaidJson()).wrap(const MoreScreen()));
      expect(find.text(S.clientsCount(12)), findsOneWidget);
      await tester.pumpWidget(_Host(activeMeJson()).wrap(const MoreScreen()));
      await tester.pump();
      expect(find.textContaining('client'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ================================================================ My profile

  group('My profile: Publish my profile, View as others see it (SPEC §9.23 D / F)', () {
    Map<String, dynamic> unpublished() => {
          ...ownProfileJson(),
          'id': 80,
          'paid': false,
          'paid_at': null,
          'visibility': 'payment_pending',
          'profile_code': null,
        };

    testWidgets('an unpublished profile: Publish my profile → the publish screen', (tester) async {
      await _phone(tester);
      final host = _Host(guestWithProfileJson(), own: unpublished());
      await tester.pumpWidget(host.wrap(const MyProfileScreen(profileId: 80)));
      await tester.pump();
      await tester.pump();
      expect(find.text(S.visibilityTitle('payment_pending')), findsOneWidget);
      expect(_button(S.publishMyProfile), findsOneWidget);
      expect(find.text(S.payFee(150)), findsNothing, reason: 'paying is a step of publishing');
      await tester.tap(find.text(S.publishMyProfile));
      await tester.pumpAndSettle();
      expect(find.byType(PublishScreen), findsOneWidget);
      expect(find.text(S.giftCodeQuestion), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('a live profile: no Publish button; the fee line says how it was paid', (tester) async {
      await _phone(tester);
      final host = _Host(liveJson(), own: {...ownProfileJson(), 'paid_via': 'gift'});
      await tester.pumpWidget(host.wrap(const MyProfileScreen(profileId: 77)));
      await tester.pump();
      await tester.pump();
      expect(find.text(S.publishMyProfile), findsNothing);
      expect(find.text(S.paidViaLine('gift')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });

    testWidgets('View as others see it → the preview, both tabs, no actions', (tester) async {
      await _phone(tester);
      final host = _Host(liveJson());
      await tester.pumpWidget(host.wrap(const MyProfileScreen(profileId: 77)));
      await tester.pump();
      await tester.pump();
      await _scrollTo(tester, find.text(S.viewAsOthers));
      await tester.tap(find.text(S.viewAsOthers));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePreviewScreen), findsOneWidget);
      expect(host.profiles.previews.first, (77, false));
      expect(tester.takeException(), isNull);
      await _dispose(tester);
    });
  });

  // ================================================================ preview screen

  group('View as others see it (SPEC §9.23 D)', () {
    Finder detailScroll() =>
        find.descendant(of: find.byType(ProfileDetailView), matching: find.byType(Scrollable)).first;

    testWidgets('before / after tabs render the profile page from canned JSON', (tester) async {
      await _phone(tester);
      final host = _Host(liveJson());
      await tester.pumpWidget(host.wrap(const ProfilePreviewScreen(profileId: 77)));
      await tester.pump();
      await tester.pump();

      expect(find.text(S.previewBanner), findsOneWidget);
      expect(find.text(S.previewTabBefore), findsOneWidget);
      expect(find.text(S.previewTabAfter), findsOneWidget);
      // Before: the neutral name, the hidden-details note, no on-request block.
      expect(find.text('Profile 77'), findsOneWidget);
      expect(find.text(S.someDetailsHidden), findsOneWidget);
      expect(find.text(S.imInterested), findsNothing);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing, reason: 'no report / block');
      await tester.scrollUntilVisible(find.text(S.previewBeforeNote), 300, scrollable: detailScroll());
      expect(find.text(S.previewBeforeNote), findsOneWidget);
      expect(find.text('Venkat Rao'), findsNothing);
      expect(find.text('12 LPA'), findsNothing, reason: 'the income is switched off');

      // After: the name, everything shared, the 15 days.
      await tester.tap(find.text(S.previewTabAfter));
      await tester.pumpAndSettle();
      expect(host.profiles.previews, [(77, false), (77, true)]);
      expect(find.text('Priya'), findsOneWidget);
      expect(find.text(S.someDetailsHidden), findsNothing);
      await tester.scrollUntilVisible(find.text(S.sharedDetailsTitle), 300, scrollable: detailScroll());
      expect(find.text('${S.detailsShared} · ${S.daysLeft(15)}'), findsOneWidget);
      expect(find.text('Venkat Rao'), findsWidgets);
      expect(find.text(S.imInterested), findsNothing);
      expect(find.text(S.withdraw), findsNothing);

      // Back to before: kept, not loaded again.
      await tester.tap(find.text(S.previewTabBefore));
      await tester.pumpAndSettle();
      expect(host.profiles.previews, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  });

  // ================================================================ searchable lists

  group('Search inside long lists (SPEC §9.23 E)', () {
    final options = pickOptionsOf(MasterData.fromJson(longMastersJson()).communities);

    test('filtering: case-insensitive, anywhere in the name or keywords; selected always kept', () {
      expect(isLongList(8), isFalse);
      expect(isLongList(9), isTrue);
      expect(filterOptions(options, '').length, 10);
      expect(filterOptions(options, 'RED').map((o) => o.label), ['Reddy']);
      expect(filterOptions(options, 'ya').map((o) => o.label), ['Vysya', 'Yadava', 'Lingayat']);
      expect(filterOptions(options, 'ya', keep: {1}).map((o) => o.label), ['Kamma', 'Vysya', 'Yadava', 'Lingayat']);
      expect(filterOptions(options, 'zzz'), isEmpty);
      const subcaste = PickOption(9, 'Chowdary', keywords: 'Kamma');
      expect(subcaste.matches('kam'), isTrue, reason: 'a subcaste is found by its community');
      expect(subcaste.matches('chow'), isTrue);
      expect(subcaste.matches('reddy'), isFalse);
    });

    testWidgets('chip group: a search field above more than eight chips; selected chips stay', (tester) async {
      await _phone(tester);
      final selected = <int>{1};
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ListView(
              children: [
                SearchableChipGroup(
                  title: S.community,
                  options: options,
                  selected: selected,
                  onToggle: (id) => setState(() => selected.contains(id) ? selected.remove(id) : selected.add(id)),
                ),
                SearchableChipGroup(
                  title: S.religion,
                  options: options.take(8).toList(),
                  selected: const {},
                  onToggle: (_) {},
                ),
              ],
            ),
          ),
        ),
      ));
      expect(find.byType(TextField), findsOneWidget, reason: 'only the long group');
      expect(find.text(S.searchIn(S.community)), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Lingayat'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'red');
      await tester.pump();
      final long = find.byType(SearchableChipGroup).first;
      Finder chip(String name) => find.descendant(of: long, matching: find.widgetWithText(FilterChip, name));
      expect(chip('Reddy'), findsOneWidget);
      expect(chip('Kamma'), findsOneWidget, reason: 'selected');
      expect(chip('Lingayat'), findsNothing);
      expect(chip('Kapu'), findsNothing);

      await tester.tap(chip('Reddy'));
      await tester.pump();
      expect(selected, {1, 2});

      await tester.enterText(find.byType(TextField), 'qq');
      await tester.pump();
      expect(find.text(S.nothingMatches), findsOneWidget);
      expect(chip('Kamma'), findsOneWidget);
      expect(chip('Reddy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('single picker field: search, tap to pick, Clear', (tester) async {
      await _phone(tester);
      int? value;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsets.all(16),
              child: SearchablePickerField(
                label: '${S.community} *',
                options: options,
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(SearchablePickerField));
      await tester.pumpAndSettle();
      expect(find.text(S.community), findsOneWidget, reason: 'the sheet title, without the star');
      expect(find.text('Lingayat'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'gow');
      await tester.pump();
      expect(find.text('Lingayat'), findsNothing);
      await tester.tap(find.text('Gowda'));
      await tester.pumpAndSettle();
      expect(value, 9);
      expect(find.text('Gowda'), findsOneWidget, reason: 'shown in the field');

      await tester.tap(find.byType(SearchablePickerField));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.clear));
      await tester.pumpAndSettle();
      expect(value, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('multi picker field: checkboxes + Done; dismissing changes nothing', (tester) async {
      await _phone(tester);
      var value = <int>{3};
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsets.all(16),
              child: MultiPickerField(
                title: S.chooseCommunities,
                hint: S.selectHint,
                options: options,
                selected: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      ));
      expect(find.text('Kapu'), findsOneWidget);
      await tester.tap(find.byType(MultiPickerField));
      await tester.pumpAndSettle();
      expect(find.text(S.selectedCount(1)), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'v');
      await tester.pump();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Velama'));
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Vysya'));
      await tester.pump();
      expect(find.text(S.selectedCount(3)), findsOneWidget);
      await tester.tap(find.text(S.done));
      await tester.pumpAndSettle();
      expect(value, {3, 5, 6});
      expect(find.text('Kapu, Vysya, Velama'), findsOneWidget);

      await tester.tap(find.byType(MultiPickerField));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Kapu'));
      await tester.tapAt(const Offset(10, 10)); // the scrim: dismissed
      await tester.pumpAndSettle();
      expect(value, {3, 5, 6});
      expect(tester.takeException(), isNull);
    });

    testWidgets('Browse filters: ten communities are a picker field with a search box (SPEC §9.24 B)',
        (tester) async {
      await _phone(tester);
      final host = _Host(guestWithProfileJson(), masters: longMastersJson());
      await tester.pumpWidget(host.wrap(
        const Scaffold(body: FilterSheet(initial: BrowseFilters.empty, communities: [], guest: true)),
      ));
      // Browse loads the masters before it opens the sheet.
      await tester.element(find.byType(FilterSheet)).read<MastersState>().load();
      await tester.pump();
      expect(find.widgetWithText(FilterChip, 'Lingayat'), findsNothing, reason: 'no wall of chips');
      final field = find.byType(MultiPickerField).first;
      await _scrollTo(tester, field);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, S.searchIn(S.community)), 'lin');
      await tester.pump();
      expect(find.widgetWithText(CheckboxListTile, 'Lingayat'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Kamma'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('profile form (a guest, no agent): the community opens the search picker and is required',
        (tester) async {
      await _phone(tester);
      final host = _Host(guestWithProfileJson()..['profiles'] = [], masters: longMastersJson());
      await tester.pumpWidget(host.wrap(const ProfileFormScreen(prefillName: true)));
      await tester.pumpAndSettle();
      final community = find.widgetWithText(SearchablePickerField, '${S.community} *');
      expect(community, findsOneWidget, reason: 'ten communities → the picker, not a dropdown');

      // Name prefilled; pick the date of birth; Next without a community.
      await tester.tap(find.text(S.selectDate));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.next));
      await tester.pumpAndSettle();
      expect(find.text(S.communityRequired), findsOneWidget);
      expect(find.text(S.stepOf(1, 4)), findsOneWidget);

      await tester.ensureVisible(community);
      await tester.tap(community);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'yad');
      await tester.pump();
      await tester.tap(find.text('Yadava'));
      await tester.pumpAndSettle();
      expect(find.text(S.communityRequired), findsNothing);
      await tester.tap(find.text(S.next));
      await tester.pumpAndSettle();
      expect(find.text(S.stepOf(2, 4)), findsOneWidget, reason: 'step 1 is valid now');
      expect(tester.takeException(), isNull);
    });

    testWidgets('privacy audience: more than eight communities → picked chips + Choose communities',
        (tester) async {
      await _phone(tester);
      final own = {...ownProfileJson(), 'hidden_fields': [], 'audience_communities': []};
      final host = _Host(liveJson(), masters: longMastersJson(), own: own);
      await tester.pumpWidget(host.wrap(PrivacyScreen(profile: Profile.fromJson(own))));
      await tester.pumpAndSettle();
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text(S.audienceSelected), 200, scrollable: list);
      await _center(tester, find.text(S.audienceSelected));
      await tester.tap(find.text(S.audienceSelected));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(S.chooseCommunities), 200, scrollable: list);
      await _center(tester, find.text(S.chooseCommunities));
      expect(find.widgetWithText(FilterChip, 'Reddy'), findsNothing, reason: 'no wall of chips');
      await tester.tap(find.text(S.chooseCommunities));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'gow');
      await tester.pump();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Gowda'));
      await tester.tap(find.text(S.done));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Gowda'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, S.save));
      await tester.pumpAndSettle();
      expect(host.profiles.patched!['audience_community_ids'], [9]);
      expect(tester.takeException(), isNull);
    });
  });
}
