import 'package:flutter/foundation.dart';

/// The selected bottom-nav tab of the home shell, so screens pushed on top
/// (Notifications) can switch it.
class HomeTab extends ValueNotifier<int> {
  HomeTab([super.value = browse]);

  static const browse = 0;
  static const interested = 1;
  static const myProfiles = 2;
  static const more = 3;
}
