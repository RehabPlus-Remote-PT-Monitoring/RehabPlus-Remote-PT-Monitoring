import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_keys.dart';
import 'firebase_options.dart';
import 'services/app_provider.dart';
import 'services/app_settings.dart';
import 'services/push_service.dart';
import 'screens/consent_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_page.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final provider = AppProvider();
  // Draw the animated splash straight away; Firebase and the patient's data
  // load behind it, and the splash continues once [startUp] is done.
  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: RehabPlusApp(startUp: startUp(provider)),
    ),
  );
}

/// Startup work shown behind the splash. Resolves to whether a patient is
/// signed in (Firebase keeps the user signed in across app restarts).
Future<bool> startUp(AppProvider provider) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  PushService.I.listen();
  await Future.wait([provider.init(), AppSettings.I.load()]);
  return FirebaseAuth.instance.currentUser != null;
}

class RehabPlusApp extends StatelessWidget {
  const RehabPlusApp({super.key, this.signedIn = false, this.startUp});

  /// Used when [startUp] is null (tests): no loading, go by this flag.
  final bool signedIn;

  /// Startup work to wait for behind the splash; resolves to "signed in".
  final Future<bool>? startUp;

  Future<Widget> _firstScreen() async {
    final isSignedIn = await (startUp ?? Future.value(signedIn));
    if (!isSignedIn) return const LoginPage();
    // Tests (no startUp) have no Firebase: go straight to the dashboard.
    if (startUp == null) return const DashboardScreen();
    // The Terms and Privacy Policy must be accepted before the dashboard.
    return ConsentScreen.gate();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RehabPlus',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      // Screens are styled for light mode only; dark mode is a separate job.
      themeMode: ThemeMode.light,
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BCD4),
          primary: const Color(0xFF00BCD4),
          secondary: const Color(0xFF0097A7),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF00BCD4),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: const Color(0xFF00BCD4).withValues(alpha: 0.2),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF00838F));
            }
            return const IconThemeData(color: Colors.grey);
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00BCD4),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BCD4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF006064),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
      // Animated startup screen, then the dashboard or the login page.
      home: SplashScreen(
        next: _firstScreen(),
        // A notification that launched the app opens once the splash is gone.
        onFinished: PushService.I.openLaunchMessage,
      ),
    );
  }
}
