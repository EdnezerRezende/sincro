import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../trusted_contacts/trusted_contacts_providers.dart';
import '../email_triage/email_triage_providers.dart';
import '../email_triage/gmail_connection_repository.dart';
import 'emergency_button.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerFcmToken());
  }

  Future<void> _registerFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        await ref.read(fcmTokenRepositoryProvider).register(token);
      }
    } catch (_) {
      // Registro de notificação é best-effort: o app continua funcionando
      // normalmente mesmo se o dispositivo não conseguir registrar o token
      // (ex: emulador sem Google Play Services, permissão negada).
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(trustedContactsListProvider);
    final gmailStatusAsync = ref.watch(gmailConnectionStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('🌿 Tudo em ordem por hoje.'),
            const SizedBox(height: 8),
            const Text('Finanças chegam em breve.'),
            const SizedBox(height: 16),
            _GmailCard(statusAsync: gmailStatusAsync),
            const SizedBox(height: 16),
            contactsAsync.when(
              data: (contacts) {
                if (contacts.isEmpty) {
                  return const Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _NoContactsHint(),
                      SizedBox(height: 16),
                      EmergencyButton(),
                    ],
                  );
                }
                return const EmergencyButton();
              },
              loading: () => const EmergencyButton(),
              error: (_, __) => const EmergencyButton(),
            ),
          ],
        ),
      ),
    );
  }
}

class _GmailCard extends ConsumerWidget {
  const _GmailCard({required this.statusAsync});

  final AsyncValue<GmailConnectionStatus> statusAsync;

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(gmailConnectionRepositoryProvider).connect();
      ref.invalidate(gmailConnectionStatusProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível conectar o Gmail. Tente novamente.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return statusAsync.when(
      data: (status) {
        if (!status.connected) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('📬 Caixa de Entrada'),
              subtitle: const Text('Conecte seu Gmail para ver um resumo calmo dos seus e-mails.'),
              trailing: ElevatedButton(
                onPressed: () => _connect(context, ref),
                child: const Text('Conectar Gmail'),
              ),
            ),
          );
        }
        return Card(
          child: ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('📬 Caixa de Entrada'),
            subtitle: Text('Conectado como ${status.gmailEmail}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/inbox'),
          ),
        );
      },
      loading: () => const Card(child: ListTile(title: Text('📬 Caixa de Entrada'), subtitle: Text('Carregando...'))),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _NoContactsHint extends StatelessWidget {
  const _NoContactsHint();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          '💡 Adicione um contato de confiança para estar preparado em emergências.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ),
    );
  }
}
