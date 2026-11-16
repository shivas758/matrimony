import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a web page in the phone's browser — behind an interface so screens
/// that link out (account deletion, SPEC §9.20 F) can be tested with a fake.
abstract class LinkLauncher {
  /// Opens [uri] outside the app. False when nothing could open it. Never
  /// throws.
  Future<bool> openExternal(Uri uri);
}

/// The real thing — `url_launcher` with an external application.
class UrlLinkLauncher implements LinkLauncher {
  const UrlLinkLauncher();

  @override
  Future<bool> openExternal(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[link] could not open $uri: $e');
      return false;
    }
  }
}
