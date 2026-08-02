import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'add_contact_screen.dart';
import 'trusted_contacts_providers.dart';

class TrustedContactsScreen extends ConsumerWidget {
  const TrustedContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(trustedContactsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Rede de apoio')),
      body: contactsAsync.when(
        data: (contacts) {
          if (contacts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Cadastre ao menos um contato de confiança para continuar.'),
              ),
            );
          }
          return ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return ListTile(title: Text(contact.nome), subtitle: Text(contact.relacao));
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Não foi possível carregar seus contatos.')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Adicionar contato'),
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const AddContactScreen()),
          );
          if (added == true) {
            ref.invalidate(trustedContactsListProvider);
          }
        },
      ),
      bottomNavigationBar: contactsAsync.maybeWhen(
        data: (contacts) => contacts.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
                  child: const Text('Continuar'),
                ),
              )
            : null,
        orElse: () => null,
      ),
    );
  }
}
