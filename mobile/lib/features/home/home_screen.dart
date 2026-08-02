import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../trusted_contacts/trusted_contacts_providers.dart';
import 'emergency_button.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(trustedContactsListProvider);

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
            const Text('Finanças e e-mails chegam em breve.'),
            const SizedBox(height: 32),
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
