import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';
import '../../state/browse_state.dart';
import '../../state/home_tab.dart';
import '../../state/interests_state.dart';
import '../../state/masters_state.dart';
import '../../state/notifications_state.dart';
import '../strings.dart';
import 'browse/browse_screen.dart';
import 'interests/interests_screen.dart';
import 'more_screen.dart';
import 'my_profile/my_profiles_screen.dart';

/// Bottom-nav shell for every signed-in customer except a suspended one:
/// Browse · Interested · My profile · More (SPEC §9.12 / §9.17). When the account's
/// access changes (guest ↔ full), Browse and Interested reload. While it is
/// shown the notifications poller runs (every 60 s and on returning to the
/// foreground — SPEC §9.15); it stops when the shell goes away (logout).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late final HomeTab _tab = context.read<HomeTab>();
  AuthState? _auth;
  String? _access;
  NotificationsState? _notifications;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tab
      ..value = HomeTab.browse
      ..addListener(_onTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MastersState>().load();
      // Warm the per-customer caches so the tabs open with data; Browse
      // loads itself when first shown.
      final customer = context.read<AuthState>().customer;
      if (customer != null) {
        context.read<InterestsState>().load(customer.id);
        _notifications = context.read<NotificationsState>()..start(customer.id);
      }
    });
  }

  void _onTab() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _notifications?.refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthState>();
    if (!identical(auth, _auth)) {
      _auth?.removeListener(_onAuthChanged);
      _auth = auth..addListener(_onAuthChanged);
      _access = auth.customer?.access;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.removeListener(_onAuthChanged);
    _notifications?.stop(notify: false);
    _tab.removeListener(_onTab);
    super.dispose();
  }

  void _onAuthChanged() {
    final customer = _auth?.customer;
    if (customer == null || customer.access == _access) return;
    _access = customer.access;
    context.read<BrowseState>().syncAccess(customer.access);
    context.read<InterestsState>().load(customer.id, force: true);
    _notifications?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab.value,
        children: const [
          BrowseScreen(),
          InterestsScreen(),
          MyProfilesScreen(),
          MoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.value,
        height: 68,
        onDestinationSelected: (i) => _tab.value = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: S.browse,
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: S.interested,
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle_rounded),
            label: S.myProfile,
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_rounded),
            selectedIcon: Icon(Icons.menu_open_rounded),
            label: S.more,
          ),
        ],
      ),
    );
  }
}
