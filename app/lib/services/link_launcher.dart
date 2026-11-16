import 'package:url_launcher/url_launcher.dart';

/// Opens a link outside the app: a `upi://pay?…` link in whichever UPI app
/// the phone has (SPEC §9.20), the account-deletion page in the browser
/// (§9.20 F), a `tel:` number in the dialer. Provided through Provider so
/// tests can swap in a fake.
abstract class LinkLauncher {
  /// False when no app took the link (e.g. no UPI app installed).
  Future<bool> launch(Uri uri);
}

class ExternalLinkLauncher implements LinkLauncher {
  const ExternalLinkLauncher();

  @override
  Future<bool> launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // PlatformException when nothing handles the scheme.
      return false;
    }
  }
}
