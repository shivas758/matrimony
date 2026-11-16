import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../config.dart';

/// Which store the build is for (SPEC §9.20 G). A Play Store build
/// (`--dart-define=STORE=play`) offers no non-Google payment: the paid
/// community step shows that online payment isn't available yet, and the
/// admin adds extra communities. Provided through Provider so tests can
/// try both builds; without a provider the build flag [kPlayStore] decides.
class StoreConfig {
  const StoreConfig({this.playStore = kPlayStore});

  final bool playStore;

  /// Whether this build hides non-Google payments.
  static bool isPlayStore(BuildContext context) =>
      Provider.of<StoreConfig?>(context, listen: false)?.playStore ?? kPlayStore;
}
