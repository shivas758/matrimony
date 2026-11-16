// Google Play screenshots of the real Wedbook Agent screens (SPEC §9.20 G).
//
//   flutter test --dart-define=SCREENSHOTS=true test/store_screenshots_test.dart
//
// renders six screens with demo data and writes them as 1080×1920 opaque
// 24-bit PNGs to <repo>/store/wedbook-agent/raw/. Skipped in a normal
// `flutter test` run. The app's own fonts and the Material icons are loaded
// so text and icons render as on a phone; the "photos" are generated
// gradient tiles with a silhouette — never pictures of real people. It is a
// Play Store build: no UPI widgets anywhere.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrimony_agents/models/agent.dart';
import 'package:matrimony_agents/models/notifications.dart';
import 'package:matrimony_agents/models/profile.dart';
import 'package:matrimony_agents/services/admin_service.dart';
import 'package:matrimony_agents/services/api_client.dart';
import 'package:matrimony_agents/services/auth_service.dart';
import 'package:matrimony_agents/services/clients_service.dart';
import 'package:matrimony_agents/services/contact_service.dart';
import 'package:matrimony_agents/services/hold_service.dart';
import 'package:matrimony_agents/services/link_launcher.dart';
import 'package:matrimony_agents/services/profile_service.dart';
import 'package:matrimony_agents/services/share_service.dart';
import 'package:matrimony_agents/state/auth_state.dart';
import 'package:matrimony_agents/state/home_nav.dart';
import 'package:matrimony_agents/state/masters_state.dart';
import 'package:matrimony_agents/state/notification_routes.dart';
import 'package:matrimony_agents/state/profiles_state.dart';
import 'package:matrimony_agents/state/store_config.dart';
import 'package:matrimony_agents/ui/screens/auth/login_screen.dart';
import 'package:matrimony_agents/ui/screens/home_shell.dart';
import 'package:matrimony_agents/ui/screens/profiles/profile_detail_screen.dart';
import 'package:matrimony_agents/ui/screens/profiles/profile_form_screen.dart';
import 'package:matrimony_agents/ui/strings.dart';
import 'package:matrimony_agents/ui/theme.dart';
import 'package:matrimony_agents/ui/widgets/common.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

/// Phone-like logical size; ×3 gives the 1080×1920 Play screenshot.
const _logical = Size(360, 640);
const _pixelRatio = 3.0;

final _shotKey = GlobalKey();

String get _outDir {
  // `flutter test` runs in the package (app/) directory.
  final repo = Directory.current.parent.path;
  return '$repo${Platform.pathSeparator}store${Platform.pathSeparator}wedbook-agent'
      '${Platform.pathSeparator}raw';
}

// ================================================================ fonts

Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final name = family['family'] as String;
    if (name == 'MaterialIcons') continue; // from the SDK, below
    final loader = FontLoader(name);
    for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  final icons = File(
    '${_flutterRoot()}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await loader.load();
}

/// The Flutter SDK: FLUTTER_ROOT, else found above the flutter_tester binary
/// (`<root>/bin/cache/artifacts/engine/<platform>/flutter_tester`).
String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (Directory('${dir.path}/bin/cache/artifacts/material_fonts').existsSync()) return dir.path;
    dir = dir.parent;
  }
  throw StateError('Flutter SDK not found from ${Platform.resolvedExecutable}');
}

// ================================================================ demo photos

/// Soft two-tone gradients; the figure is a translucent white silhouette.
const _palettes = [
  (Color(0xFFF3C6CF), Color(0xFFB98BB0)), // rose → mauve
  (Color(0xFFBFD7EA), Color(0xFF6E8FB8)), // sky → slate blue
  (Color(0xFFF6D9B0), Color(0xFFD08E6A)), // apricot → terracotta
  (Color(0xFFC8E3D4), Color(0xFF6FA58E)), // mint → sage
  (Color(0xFFE2D4F0), Color(0xFF9A86C2)), // lavender → violet
  (Color(0xFFF9E3A6), Color(0xFFC79A3E)), // butter → gold
  (Color(0xFFD3E4F0), Color(0xFF7D9FB0)), // mist → teal grey
  (Color(0xFFF2CDB8), Color(0xFFB7796A)), // peach → clay
];

Future<Uint8List> _portrait(int seed, {required bool bride}) async {
  const w = 600.0, h = 800.0;
  final (top, bottom) = _palettes[seed % _palettes.length];
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));
  c.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(w * 0.4, h), [top, bottom]),
  );
  // A soft light in one corner.
  c.drawCircle(
    Offset(seed.isEven ? w * 0.82 : w * 0.18, h * 0.14),
    230,
    Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70),
  );
  final figure = Paint()..color = Colors.white.withValues(alpha: 0.62);
  const cx = w / 2;
  if (bride) {
    // Long hair behind the head and shoulders.
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(cx, 395), width: 270, height: 400),
        const Radius.circular(135),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.34),
    );
  }
  c.drawOval(Rect.fromCenter(center: const Offset(cx, 310), width: 196, height: 236), figure);
  c.drawRect(Rect.fromCenter(center: const Offset(cx, 445), width: 78, height: 70), figure);
  final shoulders = Path()
    ..moveTo(cx - 290, h)
    ..cubicTo(cx - 290, 560, cx - 210, 478, cx - 60, 470)
    ..lineTo(cx + 60, 470)
    ..cubicTo(cx + 210, 478, cx + 290, 560, cx + 290, h)
    ..close();
  c.drawPath(shoulders, figure);
  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

final Map<int, MemoryImage> _photos = {};

Future<void> _makePhotos() async {
  for (final p in _cards) {
    final id = p['id'] as int;
    final bride = p['gender'] == 'bride';
    for (var k = 0; k < 3; k++) {
      _photos[_photoId(id, k)] = MemoryImage(await _portrait(id + k * 3, bride: bride));
    }
  }
}

int _photoId(int profileId, int k) => profileId * 10 + k;

ImageProvider _photoFor(String url) {
  final id = int.tryParse(Uri.parse(url).pathSegments.last) ?? 0;
  return _photos[id] ?? _photos.values.first;
}

// ================================================================ demo data

Map<String, dynamic> _ref(int id, String name) => {'id': id, 'name': name};

final _reddy = _ref(1, 'Reddy');
final _kamma = _ref(2, 'Kamma');
final _velama = _ref(3, 'Velama');
final _goud = _ref(4, 'Goud');
final _vokkaliga = _ref(5, 'Vokkaliga');
final _bunt = _ref(6, 'Bunt');
final _india = _ref(1, 'India');
final _usa = _ref(2, 'United States');
final _australia = _ref(3, 'Australia');
final _uae = _ref(4, 'United Arab Emirates');

final _me = <String, dynamic>{
  'id': 4,
  'full_name': 'Ramesh Goud',
  'agency_name': 'Sri Sai Vivaha Vedika',
  'phone': '9849012345',
  'city': 'Hyderabad',
  'role': 'agent',
  'status': 'active',
  'communities': [_reddy, _kamma, _velama, _goud],
  'state': {'id': 1, 'name': 'Telangana', 'code': 'TS'},
  'agent_code': 'TS1A',
};

Map<String, dynamic> _masters() => {
  'communities': [_reddy, _kamma, _velama, _goud, _vokkaliga, _bunt],
  'subcastes': [
    {'id': 11, 'community_id': 1, 'name': 'Motati'},
    {'id': 12, 'community_id': 1, 'name': 'Pakanati'},
    {'id': 21, 'community_id': 2, 'name': 'Chowdary'},
    {'id': 41, 'community_id': 4, 'name': 'Gamalla'},
  ],
  'professions': [
    _ref(1, 'Software Engineer'),
    _ref(2, 'Doctor'),
    _ref(3, 'Chartered Accountant'),
    _ref(4, 'Teacher'),
    _ref(5, 'Civil Engineer'),
    _ref(6, 'Bank Officer'),
    _ref(7, 'Business'),
  ],
  'educations': [
    _ref(1, 'B.Tech / B.E.'),
    _ref(2, 'M.S. / M.Tech'),
    _ref(3, 'MBBS'),
    _ref(4, 'CA'),
    _ref(5, 'B.Ed'),
    _ref(6, 'MBA'),
  ],
  'marital_statuses': [_ref(1, 'Never married'), _ref(2, 'Divorced')],
  'complexions': [_ref(1, 'Fair'), _ref(2, 'Wheatish')],
  'countries': [_india, _usa, _australia, _uae],
  'religions': [_ref(1, 'Hindu')],
  'languages': [_ref(1, 'Telugu'), _ref(2, 'English'), _ref(3, 'Hindi'), _ref(4, 'Kannada')],
  'food_habits': [_ref(1, 'Vegetarian'), _ref(2, 'Non-vegetarian')],
  'occupation_types': [_ref(1, 'Private job'), _ref(2, 'Government job'), _ref(3, 'Business')],
  'zodiac_signs': [
    {'id': 2, 'english_name': 'Taurus', 'indian_name': 'Vrishabha'},
    {'id': 5, 'english_name': 'Leo', 'indian_name': 'Simha'},
  ],
  'nakshatrams': [_ref(4, 'Rohini'), _ref(10, 'Magha')],
  'states': [
    {'id': 1, 'name': 'Telangana', 'code': 'TS', 'active': true},
    {'id': 2, 'name': 'Andhra Pradesh', 'code': 'AP', 'active': true},
    {'id': 3, 'name': 'Karnataka', 'code': 'KA', 'active': true},
  ],
};

List<Map<String, dynamic>> _photosOf(int id, [int n = 1]) => [
  for (var k = 0; k < n; k++)
    {'id': _photoId(id, k), 'url': '/api/photos/${_photoId(id, k)}', 'is_primary': k == 0},
];

Map<String, dynamic> _card(
  int id,
  String name,
  String gender,
  int age,
  String dob,
  int height,
  Map<String, dynamic> community,
  String profession, {
  Map<String, dynamic>? subcaste,
  Map<String, dynamic>? nriCountry,
  String? code,
}) => {
  'id': id,
  'full_name': name,
  'gender': gender,
  'age': age,
  'dob': dob,
  'height_cm': height,
  'community': community,
  'subcaste': ?subcaste,
  'profession': {'id': id, 'name': profession},
  'work_country': nriCountry ?? _india,
  'is_nri': nriCountry != null,
  'nri_country': ?nriCountry,
  'status': 'active',
  'photos': _photosOf(id),
  'is_mine': code != null,
  'profile_code': ?code,
};

final _cards = [
  _card(
    101,
    'Sravani Reddy',
    'bride',
    26,
    '1999-04-12',
    163,
    _reddy,
    'Software Engineer',
    subcaste: _ref(11, 'Motati'),
    code: 'GN-TS1A-A001',
  ),
  _card(
    102,
    'Sai Kiran Chowdary',
    'groom',
    29,
    '1996-08-21',
    178,
    _kamma,
    'Software Engineer',
    subcaste: _ref(21, 'Chowdary'),
    nriCountry: _usa,
  ),
  _card(103, 'Harika Rao', 'bride', 25, '2000-01-30', 160, _velama, 'Doctor'),
  _card(
    104,
    'Venkatesh Goud',
    'groom',
    31,
    '1994-11-02',
    175,
    _goud,
    'Civil Engineer',
    subcaste: _ref(41, 'Gamalla'),
    nriCountry: _australia,
    code: 'GN-TS1A-A002',
  ),
  _card(105, 'Divya Sree Kamma', 'bride', 24, '2001-06-18', 158, _kamma, 'Teacher'),
  _card(
    106,
    'Pranay Reddy',
    'groom',
    30,
    '1995-03-09',
    180,
    _reddy,
    'Bank Officer',
    subcaste: _ref(12, 'Pakanati'),
  ),
  _card(107, 'Kavya Gowda', 'bride', 27, '1998-09-25', 165, _vokkaliga, 'Chartered Accountant'),
  _card(108, 'Rakesh Shetty', 'groom', 32, '1993-12-14', 177, _bunt, 'Business', nriCountry: _uae),
];

/// Another agent's NRI profile, as an agent sees it before a contact request.
Map<String, dynamic> _detail102() => {
  ..._cards[1],
  'photos': _photosOf(102, 3),
  'weight_kg': 74,
  'complexion': _ref(2, 'Wheatish'),
  'religion': _ref(1, 'Hindu'),
  'gothram': 'Kasyapa',
  'mother_tongue': _ref(1, 'Telugu'),
  'known_languages': [_ref(1, 'Telugu'), _ref(2, 'English'), _ref(3, 'Hindi')],
  'food_habit': _ref(2, 'Non-vegetarian'),
  'nationality': _india,
  'education': _ref(2, 'M.S. / M.Tech'),
  'education_details': 'Computer Science, Arizona State University',
  'profession': _ref(1, 'Software Engineer'),
  'profession_details': 'Senior engineer at a product company',
  'occupation_type': _ref(1, 'Private job'),
  'marital_status': _ref(1, 'Never married'),
  'zodiac': {'id': 5, 'english_name': 'Leo', 'indian_name': 'Simha'},
  'nakshatram': _ref(10, 'Magha'),
  'birth_time': '06:45',
  'income_text': '₹55 lakh per annum',
  'about':
      'Calm, family-oriented and fond of cricket and old Telugu film songs. Working in Dallas '
      'for six years; plans to settle in Hyderabad in the long run.',
  'contact_access': 'none',
  'can_edit': false,
  'can_delete': false,
};

/// My own upload, opened in the profile form.
Map<String, dynamic> _detail101() => {
  ..._cards[0],
  'photos': _photosOf(101, 2),
  'weight_kg': 56,
  'complexion': _ref(1, 'Fair'),
  'religion': _ref(1, 'Hindu'),
  'gothram': 'Bharadwaja',
  'mother_tongue': _ref(1, 'Telugu'),
  'known_languages': [_ref(1, 'Telugu'), _ref(2, 'English'), _ref(3, 'Hindi')],
  'food_habit': _ref(1, 'Vegetarian'),
  'nationality': _india,
  'education': _ref(1, 'B.Tech / B.E.'),
  'education_details': 'ECE, JNTU Hyderabad 2020',
  'profession': _ref(1, 'Software Engineer'),
  'occupation_type': _ref(1, 'Private job'),
  'marital_status': _ref(1, 'Never married'),
  'zodiac': {'id': 2, 'english_name': 'Taurus', 'indian_name': 'Vrishabha'},
  'nakshatram': _ref(4, 'Rohini'),
  'birth_time': '10:20',
  'about': 'Works at an IT company in Hitech City. Loves Carnatic music and cooking.',
  'contact_access': 'granted',
  'city': 'Nalgonda',
  'state': 'Telangana',
  'father_name': 'K. Narasimha Reddy',
  'father_occupation': 'Retired headmaster',
  'can_edit': true,
  'can_delete': true,
};

Map<String, dynamic> _client(
  int id,
  String name,
  String phone,
  String status,
  String source,
  String created, {
  Map<String, dynamic>? profile,
  int interests = 0,
}) => {
  'id': id,
  'full_name': name,
  'phone': phone,
  'status': status,
  'source': source,
  'agent_id': 4,
  'profile': ?profile,
  'profiles': [?profile],
  'interests_count': interests,
  'created_at': created,
};

Map<String, dynamic> _summary(
  int id,
  String name,
  String gender,
  int age,
  Map<String, dynamic> community, {
  bool paid = true,
  String? code,
}) => {
  'id': id,
  'full_name': name,
  'gender': gender,
  'age': age,
  'community': community,
  'status': paid ? 'active' : 'hidden',
  'paid': paid,
  'profile_code': ?code,
};

final _clients = [
  _client(
    51,
    'Lakshmi Prasanna',
    '9701234567',
    'pending',
    'app',
    '2026-11-12T09:30:00Z',
    profile: _summary(
      201,
      'Lakshmi Prasanna',
      'bride',
      25,
      _velama,
      paid: false,
      code: 'GN-TS1A-A007',
    ),
  ),
  _client(
    52,
    'Srinivas Reddy',
    '9848022338',
    'active',
    'form',
    '2026-10-28T11:00:00Z',
    profile: _summary(202, 'Srinivas Reddy', 'groom', 30, _reddy, code: 'GN-TS1A-A003'),
    interests: 2,
  ),
  _client(
    53,
    'Anusha Goud',
    '9912345678',
    'active',
    'app',
    '2026-10-19T15:20:00Z',
    profile: _summary(203, 'Anusha Goud', 'bride', 27, _goud, code: 'GN-TS1A-A004'),
    interests: 1,
  ),
  _client(
    54,
    'Mahesh Chowdary',
    '9866554433',
    'active',
    'app',
    '2026-10-02T08:45:00Z',
    profile: _summary(204, 'Mahesh Chowdary', 'groom', 33, _kamma, code: 'GN-TS1A-A005'),
  ),
];

final _feed = <String, dynamic>{
  'badge': 3,
  'items': <Map<String, dynamic>>[],
  'counts': {
    'contact_requests_inbox': 2,
    'hold_requests_inbox': 0,
    'pending_clients': 1,
    'interests_inbox': 2,
  },
};

// ================================================================ fakes

/// Answers the app's API calls with the demo data above.
class _DemoApi extends ApiClient {
  @override
  String? get tokenSync => 'demo';

  @override
  Future<String?> readToken() async => 'demo';

  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    switch (seg) {
      case ['masters']:
        return _masters();
      case ['profiles']:
        final page = int.tryParse('${query?['page'] ?? 1}') ?? 1;
        return {'profiles': page == 1 ? _cards : const [], 'total': 248, 'page': page};
      case ['profiles', 'parse', 'status']:
        return {'enabled': false};
      case ['profiles', final id]:
        return {'profile': id == '101' ? _detail101() : _detail102()};
      case ['notifications']:
        return _feed;
      case ['clients']:
        return {'clients': _clients};
      case ['contact-requests']:
        return {'contact_requests': const []};
      case ['hold-requests']:
        return {'hold_requests': const []};
      case ['interests']:
        return {'interests': const []};
      case ['agent-change-requests']:
        return {'agent_change_requests': const []};
      case ['clients', 'delete-requests']:
        return {'delete_requests': const []};
      case ['shortlists']:
        return {'groups': const []};
    }
    // ignore: avoid_print
    print('screenshots: unhandled GET $path');
    return {};
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) async => {};
}

class _DemoAuth extends AuthState {
  _DemoAuth(_DemoApi api) : super(api: api, auth: AuthService(api), profiles: ProfileService(api));

  final _agent = Agent.fromJson(_me);
  final _notifications = NotificationFeed.fromJson(_feed);

  @override
  Agent? get agent => _agent;

  @override
  bool get isActive => true;

  @override
  bool get isAdmin => false;

  @override
  NotificationFeed get notifications => _notifications;

  @override
  int get badge => _notifications.badge;

  @override
  int get requestsBadge => _notifications.requestsBadge;

  @override
  int get clientsBadge => _notifications.clientsBadge;

  @override
  Future<void> refreshNotifications() async {}

  @override
  Future<void> refreshAgent() async {}
}

class _NoLauncher implements LinkLauncher {
  @override
  Future<bool> launch(Uri uri) async => true;
}

class _World {
  final api = _DemoApi();
  late final profileService = ProfileService(api);
  late final auth = _DemoAuth(api);
  final nav = HomeNav();
  final navigatorKey = GlobalKey<NavigatorState>();

  Widget app(Widget home) => RepaintBoundary(
    key: _shotKey,
    child: MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        // A Play Store build: no UPI widgets (SPEC §9.20 G).
        Provider<StoreConfig>.value(value: const StoreConfig(playStore: true)),
        Provider<LinkLauncher>.value(value: _NoLauncher()),
        ChangeNotifierProvider<HomeNav>.value(value: nav),
        Provider<ProfileService>.value(value: profileService),
        Provider<AuthService>(create: (_) => AuthService(api)),
        Provider<ContactService>(create: (_) => ContactService(api)),
        Provider<ClientsService>(create: (_) => ClientsService(api)),
        Provider<HoldService>(create: (_) => HoldService(api)),
        Provider<ShareService>(create: (_) => ShareService(api)),
        Provider<ShortlistService>(create: (_) => ShortlistService(api)),
        Provider<AdminService>(create: (_) => AdminService(api)),
        Provider<MyAccountService>(create: (_) => MyAccountService(api)),
        ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profileService)),
        ChangeNotifierProvider<ProfilesState>(create: (_) => ProfilesState(profileService)),
        ChangeNotifierProvider<AuthState>.value(value: auth),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Wedbook Agent',
        theme: AppTheme.light(),
        home: home,
      ),
    ),
  );

  Future<void> push(WidgetTester tester, Widget screen) async {
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => screen));
    await tester.pumpAndSettle();
  }
}

// ================================================================ capture

/// Every image on screen decoded (real async), so nothing shows a spinner.
Future<void> _settleImages(WidgetTester tester) async {
  for (var round = 0; round < 2; round++) {
    final elements = find.byType(Image, skipOffstage: false).evaluate().toList();
    await tester.runAsync(() async {
      for (final e in elements) {
        if (!e.mounted) continue;
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pumpAndSettle();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _settleImages(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  final png = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final bytes = _rgbPng(raw!.buffer.asUint8List(), image.width, image.height);
    image.dispose();
    return bytes;
  });
  final file = File('$_outDir${Platform.pathSeparator}$name');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png!);
  // ignore: avoid_print
  print('screenshots: wrote ${file.path}');
  debugDisableShadows = true;
}

/// RGBA → a 24-bit RGB PNG (no alpha channel, as Google Play asks), any
/// translucent pixel composited onto white.
Uint8List _rgbPng(Uint8List rgba, int width, int height) {
  final rows = BytesBuilder(copy: false);
  final row = Uint8List(1 + width * 3);
  for (var y = 0; y < height; y++) {
    row[0] = 0; // filter: none
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final a = rgba[i + 3];
      for (var c = 0; c < 3; c++) {
        final v = rgba[i + c];
        row[1 + x * 3 + c] = a == 255 ? v : ((v * a + 255 * (255 - a)) ~/ 255);
      }
    }
    rows.add(Uint8List.fromList(row));
  }
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typeBytes = ascii.encode(type);
    out.add(_u32(data.length));
    out.add(typeBytes);
    out.add(data);
    out.add(_u32(_crc32([...typeBytes, ...data])));
  }

  chunk('IHDR', [..._u32(width), ..._u32(height), 8, 2, 0, 0, 0]); // 8-bit RGB
  chunk('IDAT', zlib.encode(rows.takeBytes()));
  chunk('IEND', const []);
  return out.takeBytes();
}

List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = _logical * _pixelRatio;
  tester.view.devicePixelRatio = _pixelRatio;
  addTearDown(tester.view.reset);
  // flutter_test draws elevation shadows as hard black outlines; real soft
  // shadows here (put back before the test ends — the binding checks it).
  debugDisableShadows = false;
}

// ================================================================ the six shots

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
    await _makePhotos();
    AuthedPhoto.debugImageOverride = _photoFor;
  });

  tearDownAll(() => AuthedPhoto.debugImageOverride = null);

  testWidgets('01 login', skip: !_enabled, (tester) async {
    _phone(tester);
    final w = _World();
    await tester.pumpWidget(w.app(const LoginScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, S.phone), '9849012345');
    await tester.enterText(find.widgetWithText(TextFormField, S.password), 'wedbook26');
    await _capture(tester, '01_login.png');
  });

  testWidgets('02 profiles list', skip: !_enabled, (tester) async {
    _phone(tester);
    final w = _World();
    await tester.pumpWidget(w.app(const HomeShell()));
    await tester.pumpAndSettle();
    await _capture(tester, '02_profiles.png');
  });

  testWidgets('03 profile detail', skip: !_enabled, (tester) async {
    _phone(tester);
    final w = _World();
    await tester.pumpWidget(w.app(const HomeShell()));
    await tester.pumpAndSettle();
    await w.push(tester, const ProfileDetailScreen(profileId: 102));
    // Half-collapse the photo header: the name, chips, the contact lock and
    // the facts all on one screen.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -330));
    await tester.pumpAndSettle();
    await _capture(tester, '03_profile_detail.png');
  });

  testWidgets('04 profile form', skip: !_enabled, (tester) async {
    _phone(tester);
    final w = _World();
    await tester.pumpWidget(w.app(const HomeShell()));
    await tester.pumpAndSettle();
    final mine = Profile.fromJson(_detail101());
    await w.push(tester, ProfileFormScreen(existing: mine));
    await _capture(tester, '04_profile_form.png');
  });

  testWidgets('05 clients', skip: !_enabled, (tester) async {
    _phone(tester);
    final w = _World();
    w.nav.select(HomeTab.clients);
    await tester.pumpWidget(w.app(const HomeShell()));
    await tester.pumpAndSettle();
    await _capture(tester, '05_clients.png');
  });

  testWidgets('06 share without contacts', skip: !_enabled, (tester) async {
    _phone(tester);
    final w = _World();
    await tester.pumpWidget(w.app(const HomeShell()));
    await tester.pumpAndSettle();
    await w.push(tester, const ProfileDetailScreen(profileId: 102));
    await tester.tap(find.text(S.shareTitle));
    await tester.pumpAndSettle();
    await _capture(tester, '06_share.png');
  });
}
