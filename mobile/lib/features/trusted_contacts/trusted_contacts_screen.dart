import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'add_contact_screen.dart';
import 'trusted_contacts_providers.dart';

class TrustedContactsScreen extends ConsumerWidget {
  const TrustedContactsScreen({super.key});

  Future<void> _confirmAndRemove(BuildContext context, WidgetRef ref, String id, String nome) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover contato?'),
        content: Text('$nome deixará de fazer parte da sua rede de apoio. Você pode adicionar novamente quando quiser.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remover')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(trustedContactsRepositoryProvider).remove(id);
      ref.invalidate(trustedContactsListProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível remover o contato. Tente novamente.')),
        );
      }
    }
  }

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
              return ListTile(
                title: Text(contact.nome),
                subtitle: Text(contact.relacao),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remover contato',
                  onPressed: () => _confirmAndRemove(context, ref, contact.id, contact.nome),
                ),
              );
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
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            contactsAsync.maybeWhen(
              data: (contacts) => contacts.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
                        child: const Text('Continuar'),
                      ),
                    )
                  : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
              child: const Text('Pular por enquanto'),
            ),
          ],
        ),
      ),
    );
  }
}
