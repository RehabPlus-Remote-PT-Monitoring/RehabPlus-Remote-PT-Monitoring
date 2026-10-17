import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/app_keys.dart';
import 'firebase_options.dart';
import 'services/app_provider.dart';
import 'services/push_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  PushService.I.listen();
  final provider = AppProvider();
  await provider.init();
  if (FirebaseAuth.instance.currentUser != null) {
    PushService.I.registerForCurrentUser(); // not awaited: may show a prompt
  }
  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      // Firebase keeps the user signed in across app restarts.
      child: RehabPlusApp(
        signedIn: FirebaseAuth.instance.currentUser != null,
      ),
    ),
  );
}

class RehabPlusApp extends StatelessWidget {
  const RehabPlusApp({super.key, this.signedIn = false});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RehabPlus',
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        ),
      ),
      home: signedIn ? const DashboardScreen() : const LoginPage(),
    );
  }
}
