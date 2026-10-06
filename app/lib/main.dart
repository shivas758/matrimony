import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'services/admin_service.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/clients_service.dart';
import 'services/contact_service.dart';
import 'services/hold_service.dart';
import 'services/profile_service.dart';
import 'services/push_service.dart';
import 'services/share_service.dart';
import 'state/auth_state.dart';
import 'state/home_nav.dart';
import 'state/masters_state.dart';
import 'state/notification_routes.dart';
import 'state/profiles_state.dart';
import 'ui/screens/auth/force_password_screen.dart';
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/auth/pending_screen.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/notifications_screen.dart';
import 'ui/strings.dart';
import 'ui/theme.dart';
import 'ui/widgets/app_logo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const MediatorApp());
}

class MediatorApp extends StatefulWidget {
  const MediatorApp({super.key});

  @override
  State<MediatorApp> createState() => _MediatorAppState();
}

class _MediatorAppState extends State<MediatorApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final api = ApiClient();
  late final profileService = ProfileService(api);

  /// Push notifications (SPEC §9.16); off until the server has Firebase keys.
  late final push = PushService(api);
  final homeNav = HomeNav();
  final List<StreamSubscription<PushMessage>> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(push.foregroundMessages.listen(_onForeground));
    _subs.add(push.openedMessages.listen(_onOpened));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    homeNav.dispose();
    super.dispose();
  }

  AuthState? get _auth {
    final ctx = _navigatorKey.currentContext;
    return ctx == null ? null : Provider.of<AuthState>(ctx, listen: false);
  }

  /// App open: refresh the bell and show a small banner.
  void _onForeground(PushMessage m) {
    final auth = _auth;
    auth?.refreshNotifications();
    final text = [m.title, m.body].whereType<String>().where((t) => t.isNotEmpty).join(' — ');
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text.isEmpty ? S.newNotification : text),
        action: auth != null && auth.isActive
            ? SnackBarAction(label: S.view, onPressed: () => _onOpened(m))
            : null,
      ),
    );
  }

  /// A tapped system notification: same routing as the Notifications screen.
  void _onOpened(PushMessage m) {
    final auth = _auth;
    final nav = _navigatorKey.currentState;
    if (auth == null || nav == null || !auth.isActive || auth.mustChangePassword) return;
    auth.refreshNotifications();
    openNotificationTarget(nav, homeNav, notificationTarget(m.toItem(), isAdmin: auth.isAdmin));
  }

  @override
  Widget build(BuildContext context) {

    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<PushService>.value(value: push),
        ChangeNotifierProvider<HomeNav>.value(value: homeNav),
        Provider<ProfileService>.value(value: profileService),
        Provider<AuthService>(create: (_) => AuthService(api)),
        Provider<ContactService>(create: (_) => ContactService(api)),
        Provider<ClientsService>(create: (_) => ClientsService(api)),
        Provider<HoldService>(create: (_) => HoldService(api)),
        Provider<ShareService>(create: (_) => ShareService(api)),
        Provider<ShortlistService>(create: (_) => ShortlistService(api)),
        Provider<AdminService>(create: (_) => AdminService(api)),
        Provider<MyAccountService>(create: (_) => MyAccountService(api)),
        ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profileService)),
        ChangeNotifierProvider<ProfilesState>(create: (_) => ProfilesState(profileService)),
        ChangeNotifierProvider<AuthState>(
          create: (ctx) => AuthState(
            api: api,
            auth: AuthService(api),
            profiles: profileService,
            push: push,
          )..bootstrap(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _Root(),
      ),
    );
  }
}

/// Decides which screen to show:
/// splash → login → set-new-password (temporary password) → pending/suspended → home.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    return switch (auth.phase) {
      AuthPhase.starting => const _Splash(),
      AuthPhase.loggedOut => const LoginScreen(),
      AuthPhase.loggedIn => auth.mustChangePassword
          ? const ForcePasswordScreen()
          : auth.isActive
              ? const HomeShell()
              : const PendingScreen(),
    };
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogoMark(size: 132),
              const SizedBox(height: 12),
              const AppWordmark(onDark: true, size: 40),
              const SizedBox(height: 40),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.goldLight.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
