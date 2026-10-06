import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';
import '../../state/home_nav.dart';
import '../../state/masters_state.dart';
import '../../state/notification_routes.dart';
import '../../state/profiles_state.dart';
import '../strings.dart';
import 'clients/clients_screen.dart';
import 'more_screen.dart';
import 'profiles/profile_list_screen.dart';
import 'requests/requests_screen.dart';
import 'shortlists/shortlists_screen.dart';

/// Bottom-nav shell for active agents: Profiles · Requests · Clients ·
/// Shortlists · More (SPEC §5 navigation).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Selected tab, switchable from the Notifications screen and pushes
  /// (SPEC §9.14 / §9.16). App-level, so a tapped push can reach it.
  late final HomeNav _nav = context.read<HomeNav>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MastersState>().load();
      final profiles = context.read<ProfilesState>();
      profiles.loadPresets();
      profiles.refresh();
    });
  }

  @override
  void dispose() {
    // Logged out: the next session starts on Profiles.
    _nav.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = context.watch<HomeNav>().tab.index;
    // Contact + hold requests waiting for my decision.
    final requestsBadge = context.select<AuthState, int>((a) => a.requestsBadge);
    // Pending clients + interests on my uploads + transfers to decide (SPEC §9.10).
    final clientsBadge = context.select<AuthState, int>((a) => a.clientsBadge);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          ProfileListScreen(),
          RequestsScreen(),
          ClientsScreen(),
          ShortlistsScreen(),
          MoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        height: 68,
        onDestinationSelected: (i) {
          final tab = HomeTab.values[i];
          _nav.select(tab);
          if (tab == HomeTab.requests || tab == HomeTab.clients) {
            context.read<AuthState>().refreshNotifications();
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: S.profiles,
          ),
          NavigationDestination(
            icon: _badged(requestsBadge, const Icon(Icons.mark_email_unread_outlined)),
            selectedIcon: _badged(requestsBadge, const Icon(Icons.mark_email_unread_rounded)),
            label: S.requests,
          ),
          NavigationDestination(
            icon: _badged(clientsBadge, const Icon(Icons.contacts_outlined)),
            selectedIcon: _badged(clientsBadge, const Icon(Icons.contacts_rounded)),
            label: S.clients,
          ),
          const NavigationDestination(
            icon: Icon(Icons.bookmark_outline_rounded),
            selectedIcon: Icon(Icons.bookmark_rounded),
            label: S.shortlists,
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_rounded),
            selectedIcon: Icon(Icons.menu_open_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }

  Widget _badged(int count, Widget icon) => Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: icon,
      );
}
