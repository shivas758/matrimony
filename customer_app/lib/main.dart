import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'config.dart';
import 'models/notification.dart';
import 'services/agents_service.dart';
import 'services/api_client.dart';
import 'services/customer_auth_service.dart';
import 'services/payment_service.dart';
import 'services/profile_service.dart';
import 'services/push_service.dart';
import 'state/auth_state.dart';
import 'state/browse_state.dart';
import 'state/home_tab.dart';
import 'state/interests_state.dart';
import 'state/masters_state.dart';
import 'state/notifications_state.dart';
import 'ui/screens/auth/blocked_screen.dart';
import 'ui/screens/auth/phone_screen.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/notifications/notifications_screen.dart';
import 'ui/strings.dart';
import 'ui/theme.dart';
import 'ui/widgets/app_logo.dart';

/// For opening a tapped push's target and showing the in-app push banner
/// from outside any screen (SPEC §9.16).
final _navigatorKey = GlobalKey<NavigatorState>();
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

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
  runApp(const GandharvaApp());
}

class GandharvaApp extends StatelessWidget {
  const GandharvaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiClient();
    final authService = CustomerAuthService(api);
    final profileService = ProfileService(api);
    final agentsService = AgentsService(api);
    final paymentService = PaymentService(api);
    final pushService = PushService(api);

    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<CustomerAuthService>.value(value: authService),
        Provider<ProfileService>.value(value: profileService),
        Provider<AgentsService>.value(value: agentsService),
        Provider<PaymentService>.value(value: paymentService),
        Provider<PushService>.value(value: pushService),
        // The home shell's selected tab — app-wide so notification taps
        // (list and push) can switch it.
        ChangeNotifierProvider<HomeTab>(create: (_) => HomeTab()),
        ChangeNotifierProvider<MastersState>(create: (_) => MastersState(profileService)),
        ChangeNotifierProvider<AuthState>(
          create: (_) => AuthState(api: api, auth: authService)..bootstrap(),
        ),
        // Per-customer caches; each keys its data by customer id so a
        // different login on the same device starts clean.
        ChangeNotifierProvider<BrowseState>(create: (_) => BrowseState(profileService)),
        ChangeNotifierProvider<InterestsState>(create: (_) => InterestsState(profileService)),
        // One poller for the bell (SPEC §9.15); HomeShell starts / stops it.
        ChangeNotifierProvider<NotificationsState>(create: (_) => NotificationsState(api)),
      ],
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
        home: const _Root(),
      ),
    );
  }
}

/// Decides which screen to show: splash → phone (OTP login) → home. Guests,
/// pending, rejected and active customers all use Home (SPEC §9.12); only a
/// suspended account gets the blocked screen. Also starts push (SPEC §9.16)
/// once a customer is signed in, and unregisters it at logout.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  AuthState? _auth;
  late final PushService _push = context.read<PushService>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthState>();
    if (identical(auth, _auth)) return;
    _auth?.removeListener(_onAuth);
    _auth = auth
      ..beforeLogout = _push.stop
      ..addListener(_onAuth);
    _push
      ..onForeground = _onForegroundPush
      ..onOpened = _onOpenedPush;
    _onAuth();
  }

  @override
  void dispose() {
    _auth?.removeListener(_onAuth);
    super.dispose();
  }

  /// Any signed-in customer (guest included) gets push, if the server has it on.
  void _onAuth() {
    if (_auth?.phase == AuthPhase.loggedIn && !_push.active) _push.start();
  }

  void _onForegroundPush(PushMessage m) {
    context.read<NotificationsState>().refresh();
    final text = [m.title, m.body].where((s) => s != null && s.isNotEmpty).join(' — ');
    if (text.isEmpty) return;
    final route = pushRoute(m.data);
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: S.view, onPressed: () => _open(route)),
      ));
  }

  void _onOpenedPush(PushMessage m) {
    context.read<NotificationsState>().refresh();
    final route = pushRoute(m.data);
    // From a cold start the home shell may not be built yet.
    WidgetsBinding.instance.addPostFrameCallback((_) => _open(route));
  }

  void _open(NotificationRoute? route) {
    final nav = _navigatorKey.currentState;
    if (nav == null || _auth?.phase != AuthPhase.loggedIn) return;
    openNotificationRoute(nav, route, tabs: context.read<HomeTab>());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    return switch (auth.phase) {
      AuthPhase.starting => const _Splash(),
      AuthPhase.loggedOut => const PhoneScreen(),
      AuthPhase.loggedIn => auth.isSuspended ? const BlockedScreen() : const HomeShell(),
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
              // The tile already carries "MILI MATRIMONY".
              const AppLogo(size: 168),
              const SizedBox(height: 44),
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.gold.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
