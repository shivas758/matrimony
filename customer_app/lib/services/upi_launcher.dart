import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a `upi://pay?…` link with whichever UPI app the phone has (SPEC
/// §9.20 E) — behind an interface so the checkout can be tested with a fake.
abstract class UpiLauncher {
  /// Hands [uri] to a UPI app (GPay, PhonePe, Paytm, BHIM …, Android shows a
  /// chooser when there are several). False when no app can open it. Never
  /// throws.
  Future<bool> open(String uri);
}

/// The real thing — `url_launcher` with an external application. Needs the
/// `upi` scheme in the manifest's `<queries>` on Android 11+.
class UrlUpiLauncher implements UpiLauncher {
  const UrlUpiLauncher();

  @override
  Future<bool> open(String uri) async {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return false;
    try {
      return await launchUrl(parsed, mode: LaunchMode.externalApplication);
    } catch (e) {
      // ActivityNotFoundException surfaces as a PlatformException on some versions.
      debugPrint('[upi] could not open a UPI app: $e');
      return false;
    }
  }
}
