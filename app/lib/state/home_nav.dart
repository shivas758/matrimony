import 'package:flutter/foundation.dart';

import 'notification_routes.dart';

/// The home shell's selected tab, plus one-shot sub-tab requests so a
/// notification can land on Requests → Inbox or Clients → Interests
/// (SPEC §9.14). Provided by HomeShell.
class HomeNav extends ChangeNotifier {
  HomeTab _tab = HomeTab.profiles;
  final Map<HomeTab, int> _pendingSubTab = {};

  HomeTab get tab => _tab;

  void select(HomeTab tab) {
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }

  /// Switch to [tab] and ask it to show [subTab].
  void go(HomeTab tab, {int? subTab}) {
    _tab = tab;
    if (subTab != null) _pendingSubTab[tab] = subTab;
    notifyListeners();
  }

  /// Back to Profiles with nothing pending (logout). No rebuild.
  void reset() {
    _tab = HomeTab.profiles;
    _pendingSubTab.clear();
  }

  /// The sub-tab [tab] should switch to, once; null when none was asked for.
  int? takeSubTab(HomeTab tab) => _pendingSubTab.remove(tab);
}
