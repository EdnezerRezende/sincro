import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/onboarding/onboarding_router.dart';
import 'features/onboarding/anamnese/anamnese_wizard_screen.dart';
import 'features/trusted_contacts/trusted_contacts_screen.dart';
import 'features/home/home_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/email_triage/inbox_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onMessageOpenedApp.listen((_) {
    navigatorKey.currentState?.pushNamed('/inbox');
  });
  runApp(const ProviderScope(child: SincroApp()));
}

class SincroApp extends StatelessWidget {
  const SincroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Sincro',
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/onboarding-router': (_) => const OnboardingRouterScreen(),
        '/onboarding/anamnese': (_) => const AnamneseWizardScreen(),
        '/onboarding/contacts': (_) => const TrustedContactsScreen(),
        '/home': (_) => const HomeScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/inbox': (_) => const InboxScreen(),
      },
    );
  }
}
