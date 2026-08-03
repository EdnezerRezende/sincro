import 'package:firebase_auth/firebase_auth.dart';
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

/// Only email-triage notifications should ever navigate to /inbox (a discriminator keeps this
/// safe as other notification types are added later), and only while the app has a valid
/// session — otherwise a tap while signed out would push /inbox on top of /login and 401.
void _handleEmailTriageNotificationTap(RemoteMessage? message) {
  if (message == null) return;
  if (message.data['tipo'] != 'email_triage') return;
  if (FirebaseAuth.instance.currentUser == null) return;
  navigatorKey.currentState?.pushNamed('/inbox');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App backgrounded, not terminated: the Flutter engine is already running, so the navigator
  // is ready by the time this fires.
  FirebaseMessaging.onMessageOpenedApp.listen(_handleEmailTriageNotificationTap);

  // App fully terminated (the realistic case after a background sync push): tapping the
  // notification cold-starts the app. onMessageOpenedApp never fires for this case — only
  // getInitialMessage() reports it, and the navigator isn't attached yet until after the first
  // frame, so the navigation is deferred with addPostFrameCallback (same pattern used elsewhere
  // in this codebase, e.g. onboarding_router.dart's post-build redirect).
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleEmailTriageNotificationTap(initialMessage));
  }

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
