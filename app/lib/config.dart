/// A Google Play build (`--dart-define=STORE=play`, SPEC §9.20 G): no
/// non-Google payment anywhere (no UPI pay / QR / UTR step). The WhatsApp
/// APK leaves it unset.
const bool kPlayStore = String.fromEnvironment('STORE') == 'play';

/// The ONLY place the API location is configured (CLAUDE.md working style).
///
/// Defaults suit an Android emulator talking to a backend on the host machine
/// (10.0.2.2 is the host's loopback as seen from the emulator).
///
/// Override at build time, e.g.
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:3000
///   flutter build apk --release --dart-define=API_BASE_URL=https://profiles.example.in
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Everything under /api; public share pages live at the bare origin.
  static String get apiRoot => '$apiBaseUrl/api';

  /// The Terms & Conditions and this app's Privacy Policy (SPEC §9.22 C).
  static String get termsUrl => '$apiBaseUrl/terms';
  static String get privacyUrl => '$apiBaseUrl/privacy/agent';

  /// The public "delete my account" page (SPEC §9.20 F), for this app.
  static String get deleteAccountUrl => '$apiBaseUrl/delete-account?app=agent';

  /// What people read: launcher label, task switcher, About line. ("Mediator"
  /// until v2.7 — it stays the internal code name; SPEC §9.18 A.)
  static const String appName = 'Wedbook Agent';

  /// Shown on the More screen. Keep in step with `version:` in pubspec.yaml.
  static const String appVersion = '3.5.0';

  /// How long an approved contact stays visible — mirrors the server default.
  static const int contactAccessDays = 15;

  /// Communities an agent gets free (SPEC §9.20 C) — the signup picker's
  /// limit. Mirrors the server default `COMMUNITY_FREE_LIMIT`; My communities
  /// uses the server's own `free_limit` once logged in.
  static const int communityFreeLimit = 3;

  /// One-time fee per community beyond the free ones (₹), mirroring the
  /// server default `EXTRA_COMMUNITY_FEE_INR`.
  static const int extraCommunityFeeInr = 1000;

  /// Live clients that make an agent "approved" (SPEC §9.23 A) — mirrors the
  /// server default `APPROVAL_CLIENTS`; `/auth/me` sends the real value.
  static const int approvalClients = 10;

  /// A UPI reference (UTR) is 12 digits (SPEC §9.20 A).
  static const int utrLength = 12;

  /// Profile list page size.
  static const int pageSize = 20;

  /// Max photos per profile — matches the server's MAX_PHOTOS.
  static const int maxPhotos = 8;

  /// How often the app refreshes the notification badge.
  static const Duration notificationPollInterval = Duration(minutes: 2);
}
