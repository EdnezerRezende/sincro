import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase_options.dart';
import 'features/biofeedback/biofeedback_alert_service.dart';
import 'features/biofeedback/biofeedback_background_task.dart';
import 'features/biofeedback/biofeedback_screen.dart';
import 'features/professionals/admin_professionals_list_screen.dart';
import 'features/professionals/professionals_search_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/onboarding/onboarding_router.dart';
import 'features/onboarding/anamnese/anamnese_wizard_screen.dart';
import 'features/trusted_contacts/trusted_contacts_screen.dart';
import 'features/home/home_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/email_triage/inbox_screen.dart';
import 'features/financas/financas_screen.dart';
import 'features/grounding_cards/grounding_cards_library_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

/// Only email-triage notifications should ever navigate to /inbox (a discriminator keeps this
/// safe as other notification types are added later), and only while the app has a valid
/// session — otherwise a tap while signed out would push /inbox on top of /login and 401.
void _handleEmailTriageNotificationTap(RemoteMessage? message) {
  if (message == null) return;
  if (message.data['tipo'] != 'email_triage') return;
  if (FirebaseAuth.instance.currentUser == null) return;
  navigatorKey.currentState?.pushNamed('/inbox');
}

/// Toque numa notificação de alerta do Biofeedback com o app aberto ou em background navega para
/// a tela de detalhe. O discriminador de payload evita reagir a outros tipos de notificação local
/// que este app venha a ter no futuro, e só navega com uma sessão válida — do contrário um toque
/// deslogado (ex.: alerta disparado em background e só tocado depois de um logout) empurraria
/// /biofeedback por cima de /login, igual ao guard de _handleEmailTriageNotificationTap acima.
///
/// Não cobre cold-start (app terminado): `onDidReceiveNotificationResponse` nunca dispara nesse
/// caso — ver o uso de `getNotificationAppLaunchDetails()` em `main()`, que trata esse cenário
/// separadamente, no mesmo espírito do `getInitialMessage()` do FCM acima.
void _handleBiofeedbackAlertTap(NotificationResponse response) {
  if (response.payload != biofeedbackNotificationTapPayload) return;
  if (FirebaseAuth.instance.currentUser == null) return;
  navigatorKey.currentState?.pushNamed('/biofeedback');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // `workmanager` só tem implementação em Android e iOS; no desktop (Linux/Windows) a chamada
  // lança uma MissingPluginException logo na inicialização do app.
  if (Platform.isAndroid || Platform.isIOS) {
    await Workmanager().initialize(biofeedbackCallbackDispatcher);
  }

  // Os alertas do Biofeedback são um recurso só de Android e iOS, e `initialize()` do
  // flutter_local_notifications lança ArgumentError no desktop (Linux/Windows/macOS) quando as
  // settings da plataforma correspondente vêm nulas — como aqui, que só passa android:/iOS:.
  // Mesmo guard usado pelo workmanager logo acima; inventar settings de desktop para um recurso
  // que só existe no celular só criaria caminho morto.
  if (Platform.isAndroid || Platform.isIOS) {
    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _handleBiofeedbackAlertTap,
    );
    if (Platform.isAndroid) {
      // POST_NOTIFICATIONS (Android 13+) precisa ser pedida em runtime; em versões mais antigas
      // isto é um no-op.
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    // Cold-start via notificação local do Biofeedback: `onDidReceiveNotificationResponse` (acima)
    // nunca dispara para esse caso — só `getNotificationAppLaunchDetails()` reporta. O navigator só
    // está anexado após o primeiro frame, daí o addPostFrameCallback (mesmo padrão do
    // getInitialMessage() do FCM logo abaixo).
    final launchDetails = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails!.notificationResponse;
      if (response != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleBiofeedbackAlertTap(response));
      }
    }
  }

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
        '/financas': (_) => const FinancasScreen(),
        '/biofeedback': (_) => const BiofeedbackScreen(),
        '/professionals': (_) => const ProfessionalsSearchScreen(),
        '/grounding-cards': (_) => const GroundingCardsLibraryScreen(),
        '/admin/professionals': (_) => const AdminProfessionalsListScreen(),
      },
    );
  }
}
