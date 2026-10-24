import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_diagnostics.dart';
import 'core/app_keys.dart';
import 'core/app_theme.dart';
import 'core/diagnostic_logger.dart';
import 'firebase_options.dart';
import 'services/app_lock_service.dart';
import 'services/app_provider.dart';
import 'services/app_settings.dart';
import 'services/push_service.dart';
import 'screens/app_lock_screen.dart';
import 'screens/consent_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_page.dart';
import 'screens/splash_screen.dart';
import 'screens/startup_error_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // First, so that errors during startup are captured and logged too.
  AppDiagnostics.install();

  final provider = AppProvider();
  // Draw the animated splash straight away; Firebase and the patient's data
  // load behind it, and the splash continues once [runStartUp] is done.
  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: RehabPlusApp(startUp: runStartUp(provider)),
    ),
  );
}

/// Startup work shown behind the splash. Resolves to whether a patient is
/// signed in (Firebase keeps the user signed in across app restarts).
///
/// Independent steps run concurrently: the phone's settings don't need
/// Firebase, so they load while Firebase initialises. Each step is timed in
/// the diagnostic log ("Startup" tag), which shows what makes startup slow.
Future<bool> runStartUp(AppProvider provider) async {
  final logger = DiagnosticLogger.I;
  final total = Stopwatch()..start();

  final settingsLoaded = logger.timed(
    'Startup',
    'Load phone settings',
    AppSettings.I.load,
  );
  AppLockRouter.attach();
  await logger.timed(
    'Startup',
    'Firebase init',
    () => Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ),
  );
  PushService.I.listen();
  // The optional PIN lock is saved per patient, so it needs the signed-in
  // uid from Firebase.
  final appLockLoaded = logger.timed(
    'Startup',
    'Load app lock',
    AppLockService.I.load,
  );

  final signedIn = FirebaseAuth.instance.currentUser != null;
  await Future.wait([
    settingsLoaded,
    appLockLoaded,
    logger.timed('Startup', 'Load patient data', provider.init),
  ]);

  logger.info('Startup', 'Startup finished', {
    'ms': total.elapsedMilliseconds,
    'signedIn': signedIn,
  });
  return signedIn;
}

class RehabPlusApp extends StatefulWidget {
  const RehabPlusApp({super.key, this.signedIn = false, this.startUp});

  /// Used when [startUp] is null (tests): no loading, go by this flag.
  final bool signedIn;

  /// Startup work to wait for behind the splash; resolves to "signed in".
  final Future<bool>? startUp;

  Future<Widget> _firstScreen() => _screenAfter(startUp ?? Future.value(signedIn));

  /// Waits for [startUpWork] and picks the first real screen. If startup
  /// failed (rare: Firebase couldn't initialise), shows an error screen with
  /// a retry button instead of leaving the splash on screen forever.
  Future<Widget> _screenAfter(Future<bool> startUpWork) async {
    final bool isSignedIn;
    try {
      isSignedIn = await startUpWork;
    } catch (e, st) {
      DiagnosticLogger.I.error('Startup', 'Startup failed', null, e, st);
      return StartupErrorScreen(
        onRetry: () {
          final provider = navigatorKey.currentContext!.read<AppProvider>();
          return _screenAfter(runStartUp(provider));
        },
      );
    }
    if (!isSignedIn) return const LoginPage();
    // Tests (no startUp) have no Firebase: go straight to the dashboard.
    if (startUp == null) return const DashboardScreen();
    // Settings > App lock: the PIN comes before anything else. The consent
    // check (and the dashboard) only run once it's unlocked.
    if (AppLockService.I.lockIfEnabled('startup')) {
      return const AppLockScreen.startup(next: ConsentScreen.gate);
    }
    // The Terms and Privacy Policy must be accepted before the dashboard.
    return ConsentScreen.gate();
  }

  @override
  State<RehabPlusApp> createState() => _RehabPlusAppState();
}

class _RehabPlusAppState extends State<RehabPlusApp> {
  /// Created once: the app rebuilds when a setting such as the theme
  /// changes, and that must not start a second startup.
  late final Future<Widget> _firstScreen = widget._firstScreen();

  @override
  Widget build(BuildContext context) {
    // Rebuilds on Settings > Appearance changes (theme, text size).
    return ListenableBuilder(
      listenable: AppSettings.I,
      builder: (context, _) => _app(),
    );
  }

  Widget _app() {
    return MaterialApp(
      title: 'RehabPlus',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      // Settings > Appearance > Theme: light, dark or the phone's setting.
      // Screens take their neutral colours from AppPalette (context.palette).
      themeMode: AppSettings.I.themeMode,
      // Settings > Text size, on top of the phone's own text size.
      builder: (context, child) => ListenableBuilder(
        listenable: AppSettings.I,
        builder: (context, _) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(
                mq.textScaler.scale(1) * AppSettings.I.textScale,
              ),
            ),
            child: child!,
          );
        },
      ),
      // iOS-style look for both modes: lib/core/app_theme.dart.
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      // Animated startup screen, then the dashboard or the login page.
      home: SplashScreen(
        next: _firstScreen,
        onFinished: () {
          // From now on, coming back after a minute away asks for the PIN.
          AppLockService.I.arm();
          // A notification that launched the app opens once the splash is
          // gone.
          PushService.I.openLaunchMessage();
        },
      ),
    );
  }
}
