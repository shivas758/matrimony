/// The ONLY place the API location is configured (CLAUDE.md working style).
///
/// Defaults suit an Android emulator talking to a backend on the host machine
/// (10.0.2.2 is the host's loopback as seen from the emulator).
///
/// Override at build time, e.g.
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:3000
///   flutter build apk --release --dart-define=API_BASE_URL=https://profiles.example.in
/// The Google Play build (`--dart-define=STORE=play`, SPEC §9.20 G): Play only
/// allows Google Play Billing for in-app features, so this build offers no
/// other payment (no UPI, no Razorpay) — the checkout says online payment
/// isn't available yet. The WhatsApp APKs leave it off. Screens read it
/// through [PaymentService.playStore] so tests can flip it.
const bool kPlayStore = String.fromEnvironment('STORE') == 'play';

class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Everything under /api. Customer routes live under /api/customer.
  static String get apiRoot => '$apiBaseUrl/api';

  /// The public account-deletion page (SPEC §9.20 F), opened in the browser.
  static String get deleteAccountUrl => '$apiBaseUrl/delete-account?app=customer';

  /// Terms & Conditions and this app's privacy policy, linked from the signup
  /// consent checkbox (SPEC §9.22 C).
  static String get termsUrl => '$apiBaseUrl/terms';
  static String get privacyUrl => '$apiBaseUrl/privacy/matrimony';

  /// The name people read (SPEC §9.18 A). The package id and the Dart package
  /// keep the internal code name "gandharva" so installs update in place.
  static const String appName = 'Wedbook Matrimony';

  /// How long an accepted interest keeps the on-request fields visible — mirrors the server default.
  static const int accessDays = 15;

  /// Profile list page size.
  static const int pageSize = 20;

  /// Max photos per profile — matches the server's MAX_PHOTOS.
  static const int maxPhotos = 8;

  /// How often Get started re-checks the account while approval is pending.
  static const Duration statusPollInterval = Duration(minutes: 1);
}
