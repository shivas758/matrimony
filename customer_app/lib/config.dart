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

  /// Everything under /api. Customer routes live under /api/customer.
  static String get apiRoot => '$apiBaseUrl/api';

  static const String appName = 'Gandharva';
  static const String tagline = 'Connecting Hearts, Creating Families';

  /// How long an accepted interest keeps the on-request fields visible — mirrors the server default.
  static const int accessDays = 15;

  /// Profile list page size.
  static const int pageSize = 20;

  /// Max photos per profile — matches the server's MAX_PHOTOS.
  static const int maxPhotos = 8;

  /// How often Get started re-checks the account while approval is pending.
  static const Duration statusPollInterval = Duration(minutes: 1);
}
