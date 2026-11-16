// Google Play screenshots of the REAL app UI with demo data (SPEC §9.20 G).
//
//   flutter test test/store_screenshots_test.dart --dart-define=SCREENSHOTS=true
//
// writes six 1080×1920 opaque (RGB, no alpha) PNGs to
// ../store/wedbook-matrimony/raw/. Skipped in a normal `flutter test`.
//
// The screens are the app's own widgets on fake services: the app's bundled
// fonts (Poppins, Playfair Display) and MaterialIcons are loaded, so text and
// icons render as on a phone. The photos are generated tiles (a soft
// gradient and a plain silhouette) — never a real person. The Play build
// look: `PaymentService(playStore: true)`, and every profile shown is paid.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gandharva/models/customer.dart';
import 'package:gandharva/models/profile.dart';
import 'package:gandharva/services/agents_service.dart';
import 'package:gandharva/services/api_client.dart';
import 'package:gandharva/services/customer_auth_service.dart';
import 'package:gandharva/services/link_launcher.dart';
import 'package:gandharva/services/payment_service.dart';
import 'package:gandharva/services/phone_auth_gateway.dart';
import 'package:gandharva/services/profile_service.dart';
import 'package:gandharva/services/razorpay_gateway.dart';
import 'package:gandharva/services/upi_launcher.dart';
import 'package:gandharva/state/auth_state.dart';
import 'package:gandharva/state/browse_state.dart';
import 'package:gandharva/state/home_tab.dart';
import 'package:gandharva/state/interests_state.dart';
import 'package:gandharva/state/masters_state.dart';
import 'package:gandharva/state/notifications_state.dart';
import 'package:gandharva/ui/screens/auth/phone_screen.dart';
import 'package:gandharva/ui/screens/browse/profile_detail_screen.dart';
import 'package:gandharva/ui/screens/home_shell.dart';
import 'package:gandharva/ui/screens/my_profile/privacy_screen.dart';
import 'package:gandharva/ui/theme.dart';
import 'package:gandharva/ui/widgets/common.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

/// Phone-like logical size × 3 = exactly 1080 × 1920.
const _logical = Size(360, 640);
const _ratio = 3.0;

final _outDir = Directory('../store/wedbook-matrimony/raw');

// ======================================================================= data

const _myProfileId = 77;
const _detailId = 101;

Map<String, dynamic> _ref(int id, String name) => {'id': id, 'name': name};

final _communities = {
  1: 'Reddy',
  2: 'Kamma',
  3: 'Kapu',
  4: 'Vokkaliga',
  5: 'Lingayat',
  6: 'Velama',
  7: 'Brahmin',
};

Map<String, dynamic> _community(int id) => _ref(id, _communities[id]!);

/// GET /masters as the v2.8+ server sends it (privacy list = backend/src/lib/privacy.js).
Map<String, dynamic> _masters() => {
      'communities': [for (final e in _communities.entries) _ref(e.key, e.value)],
      'subcastes': [
        {'id': 11, 'community_id': 1, 'name': 'Pakanati'},
        {'id': 41, 'community_id': 4, 'name': 'Gangatkar'},
      ],
      'professions': [_ref(1, 'Software Engineer'), _ref(2, 'Doctor')],
      'educations': [_ref(1, 'B.Tech / B.E.'), _ref(2, 'M.Tech')],
      'marital_statuses': [_ref(1, 'Never married')],
      'countries': [_ref(1, 'India'), _ref(2, 'United States')],
      'zodiac_signs': [],
      'nakshatrams': [],
      'states': [
        {'id': 1, 'name': 'Karnataka', 'code': 'KA', 'active': true, 'sort_order': 1},
      ],
      'privacy_fields': [
        {'key': 'name', 'label': 'Name', 'section': 'personal', 'hint': 'Others see a profile number instead'},
        {'key': 'dob', 'label': 'Date of birth', 'section': 'personal', 'hint': 'Age is always shown'},
        {'key': 'marital_status', 'label': 'Marital status', 'section': 'personal', 'hint': null},
        {'key': 'religion', 'label': 'Religion', 'section': 'personal', 'hint': null},
        {'key': 'community', 'label': 'Community / caste', 'section': 'personal', 'hint': 'Also hides the subcaste'},
        {'key': 'subcaste', 'label': 'Subcaste', 'section': 'personal', 'hint': null},
        {'key': 'mother_tongue', 'label': 'Mother tongue', 'section': 'personal', 'hint': null},
        {'key': 'known_languages', 'label': 'Languages known', 'section': 'personal', 'hint': null},
        {'key': 'height', 'label': 'Height', 'section': 'personal', 'hint': null},
        {'key': 'weight', 'label': 'Weight', 'section': 'personal', 'hint': null},
        {'key': 'complexion', 'label': 'Complexion', 'section': 'personal', 'hint': null},
        {'key': 'food_habit', 'label': 'Food habit', 'section': 'personal', 'hint': null},
        {'key': 'nationality', 'label': 'Nationality', 'section': 'personal', 'hint': null},
        {'key': 'about', 'label': 'About', 'section': 'personal', 'hint': null},
        {'key': 'photos', 'label': 'Other photos', 'section': 'personal', 'hint': 'The main photo is always shown'},
        {'key': 'education', 'label': 'Education', 'section': 'professional', 'hint': null},
        {'key': 'profession', 'label': 'Profession / occupation', 'section': 'professional', 'hint': null},
        {'key': 'income', 'label': 'Income / package', 'section': 'professional', 'hint': null},
        {'key': 'work_location', 'label': 'Work country / NRI', 'section': 'professional', 'hint': null},
        {'key': 'star_rasi', 'label': 'Star & Rasi', 'section': 'horoscope', 'hint': null},
        {'key': 'gothram', 'label': 'Gothram', 'section': 'horoscope', 'hint': null},
        {'key': 'birth_time', 'label': 'Birth time', 'section': 'horoscope', 'hint': null},
      ],
      'privacy_always_visible': ['Main photo', 'Age', 'Gender'],
    };

/// One demo person: public fields only (what other families see).
class _Person {
  const _Person({
    required this.id,
    required this.name,
    required this.gender,
    required this.dob,
    required this.age,
    required this.heightCm,
    required this.community,
    this.subcaste,
    required this.education,
    required this.profession,
    required this.country,
    this.nri = false,
    required this.palette,
  });

  final int id;
  final String name;
  final String gender;
  final String dob;
  final int age;
  final int heightCm;
  final int community;
  final Map<String, dynamic>? subcaste;
  final String education;
  final String profession;
  final String country;
  final bool nri;

  /// Index into [_palettes] for the generated photo.
  final int palette;

  String get photoUrl => '/api/customer/photos/$id';

  Map<String, dynamic> json() => {
        'id': id,
        'full_name': name,
        'gender': gender,
        'status': 'active',
        'dob': dob,
        'age': age,
        'height_cm': heightCm,
        'religion': _ref(1, 'Hindu'),
        'community': _community(community),
        'subcaste': subcaste,
        'education': _ref(id * 10 + 1, education),
        'profession': _ref(id * 10 + 2, profession),
        'occupation_type': _ref(1, 'Private job'),
        'work_country': _ref(nri ? 2 : 1, country),
        'is_nri': nri,
        'nri_country': nri ? _ref(2, country) : null,
        'marital_status': _ref(1, 'Never married'),
        'is_customer_profile': true,
        'photos': [
          {'id': id, 'url': photoUrl, 'is_primary': true},
        ],
        'primary_photo_url': photoUrl,
        'masked_fields': <String>[],
        'interest_status': null,
        'is_interested': false,
      };

  Map<String, dynamic> summary() => {
        'id': id,
        'full_name': name,
        'gender': gender,
        'age': age,
        'community': _community(community),
        'subcaste': subcaste,
        'status': 'active',
        'photo_url': photoUrl,
      };
}

const _grooms = [
  _Person(
    id: _detailId,
    name: 'Karthik Reddy',
    gender: 'groom',
    dob: '1997-04-12',
    age: 29,
    heightCm: 178,
    community: 1,
    subcaste: {'id': 11, 'name': 'Pakanati'},
    education: 'B.Tech / B.E.',
    profession: 'Software Engineer',
    country: 'India',
    palette: 0,
  ),
  _Person(
    id: 102,
    name: 'Sai Kiran Chowdary',
    gender: 'groom',
    dob: '1995-08-23',
    age: 31,
    heightCm: 175,
    community: 2,
    education: 'MBA',
    profession: 'Business Analyst',
    country: 'United States',
    nri: true,
    palette: 1,
  ),
  _Person(
    id: 103,
    name: 'Pradeep Gowda',
    gender: 'groom',
    dob: '1996-01-30',
    age: 30,
    heightCm: 180,
    community: 4,
    subcaste: {'id': 41, 'name': 'Gangatkar'},
    education: 'B.E. Civil',
    profession: 'Civil Engineer',
    country: 'India',
    palette: 2,
  ),
  _Person(
    id: 104,
    name: 'Venkatesh Naidu',
    gender: 'groom',
    dob: '1998-06-05',
    age: 28,
    heightCm: 173,
    community: 3,
    subcaste: {'id': 31, 'name': 'Telaga'},
    education: 'MBBS, MD',
    profession: 'Doctor',
    country: 'India',
    palette: 3,
  ),
  _Person(
    id: 105,
    name: 'Harsha Vardhan Rao',
    gender: 'groom',
    dob: '1994-11-18',
    age: 32,
    heightCm: 177,
    community: 6,
    education: 'CA',
    profession: 'Chartered Accountant',
    country: 'United Arab Emirates',
    nri: true,
    palette: 4,
  ),
];

/// The detail page of [_grooms].first: every public field filled.
Map<String, dynamic> _detailJson() => {
      ..._grooms.first.json(),
      'weight_kg': 72,
      'complexion': _ref(2, 'Wheatish'),
      'gothram': 'Kashyapa',
      'mother_tongue': _ref(1, 'Telugu'),
      'known_languages': [_ref(1, 'Telugu'), _ref(2, 'Kannada'), _ref(3, 'English')],
      'food_habit': _ref(1, 'Vegetarian'),
      'nationality': _ref(1, 'Indian'),
      'education_details': 'B.Tech CSE, JNTU Hyderabad',
      'education_levels': [
        {'level': 'graduation', 'details': 'B.Tech, JNTU Hyderabad', 'country': _ref(1, 'India')},
        {'level': 'post_graduation', 'details': 'M.Tech, IISc Bengaluru', 'country': _ref(1, 'India')},
      ],
      'profession_details': 'Senior software engineer, product company',
      'income_text': '24 LPA',
      'zodiac': {'id': 5, 'english_name': 'Leo', 'indian_name': 'Simha'},
      'nakshatram': _ref(10, 'Magha'),
      'birth_time': '06:45',
      'about':
          'Calm, family-oriented and fond of Carnatic music. Settled in Bengaluru, visits the family in Nellore often.',
      'photos': [
        {'id': 101, 'url': '/api/customer/photos/101', 'is_primary': true},
        {'id': 1011, 'url': '/api/customer/photos/1011', 'is_primary': false},
        {'id': 1012, 'url': '/api/customer/photos/1012', 'is_primary': false},
      ],
      'contact_access': 'none',
      'interest': null,
    };

/// My own profile (the account holder's daughter), paid and live, with its ID.
Map<String, dynamic> _ownJson() => {
      'id': _myProfileId,
      'full_name': 'Lakshmi Sravani',
      'gender': 'bride',
      'status': 'active',
      'dob': '1999-03-14',
      'age': 27,
      'height_cm': 163,
      'weight_kg': 54,
      'complexion': _ref(1, 'Fair'),
      'religion': _ref(1, 'Hindu'),
      'community': _community(1),
      'subcaste': {'id': 11, 'name': 'Pakanati'},
      'gothram': 'Bharadwaja',
      'mother_tongue': _ref(1, 'Telugu'),
      'known_languages': [_ref(1, 'Telugu'), _ref(3, 'English'), _ref(4, 'Hindi')],
      'food_habit': _ref(1, 'Vegetarian'),
      'nationality': _ref(1, 'Indian'),
      'education': _ref(2, 'M.Tech'),
      'education_details': 'M.Tech, NIT Warangal',
      'education_levels': [],
      'profession': _ref(1, 'Software Engineer'),
      'profession_details': 'Data engineer',
      'occupation_type': _ref(1, 'Private job'),
      'work_country': _ref(1, 'India'),
      'marital_status': _ref(1, 'Never married'),
      'zodiac': {'id': 1, 'english_name': 'Pisces', 'indian_name': 'Meena'},
      'nakshatram': _ref(25, 'Revati'),
      'birth_time': '09:20',
      'income_text': '16 LPA',
      'is_nri': false,
      'about': 'Cheerful, loves cooking and Kuchipudi. Looking for a kind, well-settled partner.',
      'is_customer_profile': true,
      'photos': [
        {'id': 77, 'url': '/api/customer/photos/77', 'is_primary': true},
        {'id': 771, 'url': '/api/customer/photos/771', 'is_primary': false},
        {'id': 772, 'url': '/api/customer/photos/772', 'is_primary': false},
      ],
      'primary_photo_url': '/api/customer/photos/77',
      'is_mine': true,
      'paid': true,
      'paid_at': '2026-11-02T10:30:00.000Z',
      'visibility': 'live',
      'profile_fee_inr': 150,
      'delete_request': null,
      'payment': null,
      'profile_code': 'GN-KA3B-A014',
      'hidden_fields': ['income', 'birth_time'],
      'audience_all': false,
      'audience_communities': [_community(2), _community(6)],
      'masked_fields': <String>[],
      // on request — it is mine
      'city': 'Nellore',
      'state': 'Andhra Pradesh',
      'father_name': 'Srinivasa Reddy',
      'father_occupation': 'Retired bank manager',
      'mother_name': 'Padmavathi',
      'mother_occupation': 'Homemaker',
      'contact_name': 'Srinivasa Reddy',
      'contact_phone': '9876543210',
      'has_siblings': true,
      'siblings_count': 1,
      'elder_brothers': 1,
      'family_details': 'Nuclear family, settled in Bengaluru for 15 years.',
    };

Map<String, dynamic> _meJson() => {
      'id': 9,
      'full_name': 'Srinivasa Reddy',
      'phone': '9876543210',
      'status': 'active',
      'source': 'app',
      'approved_at': '2026-11-03T09:00:00.000Z',
      'customer_code': 'GN-KA3B-A014',
      'agent': {
        'id': 3,
        'full_name': 'Ramesh Gowda',
        'agency_name': 'Sri Sai Marriage Bureau',
        'city': 'Mysuru',
        'phone': '9845012345',
        'agent_code': 'KA3B',
        'communities': [_community(1), _community(2), _community(4)],
      },
      'profile_id': _myProfileId,
      'has_profile': true,
      'access': 'full',
      'max_profiles': 1,
      'profile_fee_inr': 150,
      'payment_provider': 'upi',
      'profiles': [
        {
          'id': _myProfileId,
          'full_name': 'Lakshmi Sravani',
          'gender': 'bride',
          'age': 27,
          'community': _community(1),
          'status': 'active',
          'photo_url': '/api/customer/photos/77',
          'paid': true,
          'paid_at': '2026-11-02T10:30:00.000Z',
          'visibility': 'live',
          'profile_code': 'GN-KA3B-A014',
          'payment': null,
        },
      ],
      'unlock': {'agent_linked': true, 'profile_registered': true, 'paid': true, 'approved': true},
    };

Map<String, dynamic> _interestsJson() {
  final from = {'id': _myProfileId, 'full_name': 'Lakshmi Sravani', 'gender': 'bride'};
  return {
    'interests': [
      {
        'id': 31,
        'status': 'accepted',
        'created_at': '2026-11-08T11:00:00.000Z',
        'decided_at': '2026-11-09T15:00:00.000Z',
        'access_expires_at': '2026-11-24T15:00:00.000Z',
        'days_left': 11,
        'profile': _grooms[3].summary(),
        'from_profile': from,
      },
      {
        'id': 32,
        'status': 'pending',
        'created_at': '2026-11-11T18:30:00.000Z',
        'profile': _grooms[0].summary(),
        'from_profile': from,
      },
      {
        'id': 33,
        'status': 'pending',
        'created_at': '2026-11-12T08:15:00.000Z',
        'profile': _grooms[2].summary(),
        'from_profile': from,
      },
    ],
  };
}

Map<String, dynamic> _notificationsJson() => {
      'action_count': 0,
      'items': [
        {
          'type': 'interest_accepted',
          'group': 'update',
          'id': 31,
          'interest_id': 31,
          'profile_id': 104,
          'my_profile_id': _myProfileId,
          'title': 'Details shared with you',
          'body': 'Venkatesh Naidu — for Lakshmi Sravani',
          'at': '2026-11-09T15:00:00.000Z',
        },
        {
          'type': 'account_approved',
          'group': 'update',
          'id': 9,
          'title': 'Your account is approved',
          'body': 'Ramesh Gowda approved your account.',
          'at': '2026-11-03T09:00:00.000Z',
        },
      ],
    };

// ======================================================================= fakes

/// Answers every GET from the demo data; nothing is ever written.
class _DemoApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    if (path == '/masters') return _masters();
    if (path == '/customer/profiles') {
      return {
        'profiles': [for (final g in _grooms) g.json()],
        'total': 48,
        'page': 1,
        'access': 'full',
        'gender': 'groom',
      };
    }
    if (path == '/customer/profiles/$_detailId') return {'profile': _detailJson()};
    if (path == '/customer/my-profiles/$_myProfileId') return {'profile': _ownJson()};
    if (path == '/customer/interests') return _interestsJson();
    if (path == '/customer/notifications') return _notificationsJson();
    throw ApiException('not_found', 'no demo data for $path', status: 404);
  }

  @override
  Future<Map<String, dynamic>> post(String path, {Object? body}) async =>
      throw ApiException('read_only', 'demo');

  @override
  Future<String?> readToken() async => 'demo';

  @override
  String? get tokenSync => 'demo';
}

class _DemoAuth extends AuthState {
  _DemoAuth(this._c, ApiClient api) : super(api: api, auth: CustomerAuthService(api));

  final Customer? _c;

  @override
  AuthPhase get phase => _c == null ? AuthPhase.loggedOut : AuthPhase.loggedIn;

  @override
  Customer? get customer => _c;

  @override
  AgentCard? get agent => _c?.agent;

  @override
  Future<bool> refresh() async => true;

  @override
  Future<void> refreshCustomer() async {}
}

class _NoPhoneAuth implements PhoneAuthGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoRazorpay implements RazorpayGateway {
  @override
  Future<RazorpayOutcome> open(Map<String, dynamic> options) async => const RazorpayCancelled();
}

class _NoUpi implements UpiLauncher {
  @override
  Future<bool> open(String uri) async => false;
}

class _NoLinks implements LinkLauncher {
  @override
  Future<bool> openExternal(Uri uri) async => false;
}

// ======================================================================= photos

/// Soft two-tone backgrounds for the generated portrait tiles.
const _palettes = [
  [Color(0xFFF3D9C7), Color(0xFFD9A38C)], // peach
  [Color(0xFFD7E3F1), Color(0xFF94AFCF)], // sky
  [Color(0xFFDDE8D6), Color(0xFF9DB98F)], // sage
  [Color(0xFFE9DDF0), Color(0xFFB59BC9)], // lavender
  [Color(0xFFF1E4C6), Color(0xFFC9A86A)], // sand
  [Color(0xFFF4D6DC), Color(0xFFCF8D9C)], // rose
];

/// A portrait tile: gradient, soft light and a plain head-and-shoulders
/// silhouette (with long hair for a bride). No real person.
Future<Uint8List> _portrait({required int palette, required bool bride, double shift = 0}) async {
  const w = 900.0, h = 1000.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final colors = _palettes[palette % _palettes.length];
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, h * shift),
        const Offset(w, h),
        colors,
      ),
  );
  canvas.drawCircle(
    const Offset(w * 0.5, h * 0.42),
    w * 0.55,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(w * 0.5, h * 0.42),
        w * 0.55,
        [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)],
      ),
  );
  // Opaque, so the overlapping parts read as one shape.
  final figure = Paint()..color = Color.lerp(colors[0], Colors.white, 0.6)!;
  final shade = Paint()..color = Color.lerp(colors[1], Colors.black, 0.12)!;
  const cx = w / 2;
  const headY = h * 0.40;
  const headR = w * 0.155;
  if (bride) {
    // Hair falling to the shoulders, behind the head.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(cx - headR * 1.25, headY - headR * 1.15, cx + headR * 1.25, headY + headR * 2.3),
        topLeft: const Radius.circular(headR * 1.25),
        topRight: const Radius.circular(headR * 1.25),
        bottomLeft: const Radius.circular(headR * 0.5),
        bottomRight: const Radius.circular(headR * 0.5),
      ),
      shade,
    );
  }
  // Shoulders.
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTRB(cx - w * 0.36, headY + headR * 1.55, cx + w * 0.36, h + w * 0.3),
      const Radius.circular(w * 0.3),
    ),
    figure,
  );
  // Neck + head.
  canvas.drawRect(Rect.fromLTRB(cx - headR * 0.42, headY + headR * 0.6, cx + headR * 0.42, headY + headR * 1.8), figure);
  canvas.drawCircle(const Offset(cx, headY), headR, figure);
  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// url → generated photo, for every photo URL in the demo data.
Future<Map<String, MemoryImage>> _photos() async {
  final out = <String, MemoryImage>{};
  Future<void> add(int photoId, int palette, bool bride, [double shift = 0]) async {
    out[ApiClient.absoluteUrl('/api/customer/photos/$photoId')] =
        MemoryImage(await _portrait(palette: palette, bride: bride, shift: shift));
  }

  for (final g in _grooms) {
    await add(g.id, g.palette, false);
  }
  await add(1011, 0, false, 0.4);
  await add(1012, 2, false, 0.2);
  await add(77, 5, true);
  await add(771, 3, true, 0.3);
  await add(772, 4, true, 0.2);
  return out;
}

/// Decodes every photo into the image cache, so the screens show them on
/// the first frame (decoding is real async work).
Future<void> _precache(Iterable<ImageProvider> images) async {
  for (final image in images) {
    final stream = image.resolve(ImageConfiguration.empty);
    final done = Completer<void>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) {
        if (!done.isCompleted) done.complete();
        stream.removeListener(listener);
      },
      onError: (Object e, StackTrace? _) {
        if (!done.isCompleted) done.completeError(e);
      },
    );
    stream.addListener(listener);
    await done.future;
  }
}

// ======================================================================= fonts

/// The app's fonts from the bundled FontManifest.json, MaterialIcons from the
/// Flutter SDK when the manifest has none — real glyphs instead of test boxes.
Future<void> _loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  var icons = false;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    final loader = FontLoader(family);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
    if (family == 'MaterialIcons') icons = true;
  }
  if (!icons) {
    final loader = FontLoader('MaterialIcons')..addFont(_sdkMaterialIcons());
    await loader.load();
  }
}

/// `<flutter root>/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf`,
/// found from the flutter_tester binary (…/bin/cache/artifacts/engine/…).
Future<ByteData> _sdkMaterialIcons() async {
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.path != dir.parent.path && !dir.path.endsWith('artifacts')) {
    dir = dir.parent;
  }
  final file = File('${dir.path}${Platform.pathSeparator}material_fonts${Platform.pathSeparator}MaterialIcons-Regular.otf');
  return ByteData.sublistView(await file.readAsBytes());
}

// ======================================================================= PNG

/// RGBA (straight alpha) → an opaque 24-bit RGB PNG: Play wants no alpha.
Uint8List _rgbPng(int width, int height, Uint8List rgba) {
  final stride = width * 3 + 1;
  final raw = Uint8List(stride * height);
  for (var y = 0; y < height; y++) {
    raw[y * stride] = 0; // filter: none
    for (var x = 0; x < width; x++) {
      final s = (y * width + x) * 4;
      final d = y * stride + 1 + x * 3;
      final a = rgba[s + 3];
      for (var c = 0; c < 3; c++) {
        // Over white, should anything be translucent.
        raw[d + c] = (rgba[s + c] * a + 255 * (255 - a)) ~/ 255;
      }
    }
  }
  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final body = [...ascii.encode(type), ...data];
    out
      ..add(_u32(data.length))
      ..add(body)
      ..add(_u32(_crc32(body)));
  }

  chunk('IHDR', [..._u32(width), ..._u32(height), 8, 2, 0, 0, 0]);
  chunk('IDAT', ZLibCodec(level: 9).encode(raw));
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

// ======================================================================= test

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Play Store screenshots → store/wedbook-matrimony/raw', (tester) async {
    tester.view.physicalSize = _logical * _ratio;
    tester.view.devicePixelRatio = _ratio;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    // Real elevation shadows (tests flatten them by default); restored below.
    debugDisableShadows = false;

    final photos = (await tester.runAsync(() async {
      await _loadFonts();
      final p = await _photos();
      await _precache(p.values);
      return p;
    }))!;
    AuthedPhoto.debugImageOverride = (url) => photos[url] ?? photos.values.first;

    final api = _DemoApi();
    final profiles = ProfileService(api);
    final shotKey = GlobalKey();
    final navKey = GlobalKey<NavigatorState>();
    final homeTab = HomeTab();

    Widget app(Customer? customer, Widget home) => RepaintBoundary(
          key: shotKey,
          child: MultiProvider(
            providers: [
              Provider<ApiClient>.value(value: api),
              Provider<CustomerAuthService>.value(value: CustomerAuthService(api)),
              Provider<ProfileService>.value(value: profiles),
              Provider<AgentsService>.value(value: AgentsService(api)),
              // The Play build: no UPI / Razorpay anywhere.
              Provider<PaymentService>.value(value: PaymentService(api, playStore: true)),
              Provider<PhoneAuthGateway>.value(value: _NoPhoneAuth()),
              Provider<RazorpayGateway>.value(value: _NoRazorpay()),
              Provider<UpiLauncher>.value(value: _NoUpi()),
              Provider<LinkLauncher>.value(value: _NoLinks()),
              ChangeNotifierProvider<HomeTab>.value(value: homeTab),
              ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profiles)),
              ChangeNotifierProvider<AuthState>(create: (_) => _DemoAuth(customer, api)),
              ChangeNotifierProvider<BrowseState>(create: (_) => BrowseState(profiles)),
              ChangeNotifierProvider<InterestsState>(create: (_) => InterestsState(profiles)),
              ChangeNotifierProvider<NotificationsState>(create: (_) => NotificationsState(api)),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              navigatorKey: navKey,
              home: home,
            ),
          ),
        );

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> shoot(String name) async {
      await settle();
      // Asset images (the logo) decode for real, not in fake time: wait for
      // every image on screen, then paint again.
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await settle();
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: _ratio);
        expect((image.width, image.height), (1080, 1920), reason: name);
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        final png = _rgbPng(image.width, image.height, rgba!.buffer.asUint8List());
        image.dispose();
        await _outDir.create(recursive: true);
        await File('${_outDir.path}/$name').writeAsBytes(png);
      });
    }

    try {
      final me = Customer.fromJson(_meJson());

      // 1 — sign in with the mobile number.
      await tester.pumpWidget(app(null, const PhoneScreen()));
      await settle();
      await tester.enterText(find.byType(TextFormField), '9876543210');
      FocusManager.instance.primaryFocus?.unfocus();
      await shoot('01_login.png');

      // 2 — Browse: the matching profiles.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app(me, const HomeShell()));
      await shoot('02_browse.png');

      // 3 — one profile.
      navKey.currentState!.push(MaterialPageRoute(builder: (_) => const ProfileDetailScreen(profileId: _detailId)));
      await settle();
      // Part of the photo, more of the profile.
      final detailScroll = find.descendant(
        of: find.byType(ProfileDetailScreen),
        matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down),
      );
      tester.state<ScrollableState>(detailScroll.first).position.jumpTo(130);
      await shoot('03_profile.png');
      navKey.currentState!.pop();
      await settle();

      // 4 — My profile: paid, live, with its ID.
      homeTab.value = HomeTab.myProfiles;
      await shoot('04_my_profile.png');

      // 5 — Privacy settings.
      navKey.currentState!.push(
        MaterialPageRoute(builder: (_) => PrivacyScreen(profile: Profile.fromJson(_ownJson()))),
      );
      await settle();
      // The switches: income and birth time are kept back; switch the
      // gothram off too, so Save is live — and show that part of the page.
      final privacyList = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(find.text('Gothram'), 300, scrollable: privacyList);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Gothram'));
      await settle();
      await tester.scrollUntilVisible(find.text('PROFESSIONAL'), -300, scrollable: privacyList);
      await Scrollable.ensureVisible(tester.element(find.text('PROFESSIONAL')));
      await shoot('05_privacy.png');
      navKey.currentState!.pop();
      await settle();

      // 6 — Interests.
      homeTab.value = HomeTab.interested;
      await shoot('06_interests.png');
    } finally {
      // Dispose the shell (its notification poller) before the checks run.
      await tester.pumpWidget(const SizedBox.shrink());
      AuthedPhoto.debugImageOverride = null;
      debugDisableShadows = true;
    }
  }, skip: !_enabled);
}
