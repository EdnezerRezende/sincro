import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_row.dart';
import 'add_contact_screen.dart';
import 'trusted_contacts_providers.dart';

/// Rede de apoio na direção A (prancha "Rede de apoio"): contatos num cartão agrupado
/// (nome + relação, remover à direita), atalho para buscar um profissional já cadastrado no app
/// e, no rodapé fixo, "Adicionar contato", "Continuar" e "Pular por enquanto".
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

  Future<void> _addContact(BuildContext context, WidgetRef ref) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddContactScreen()),
    );
    if (added == true) {
      ref.invalidate(trustedContactsListProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(trustedContactsListProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final buscarProfissional = SectionCard(
      children: [
        SectionRow(
          icon: Icons.search,
          title: 'Buscar profissional cadastrado',
          subtitle: 'Pelo nome ou perto de você',
          onTap: () => Navigator.of(context).pushNamed('/professionals'),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Rede de apoio')),
      body: contactsAsync.when(
        data: (contacts) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            children: [
              if (contacts.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Text(
                    'Cadastre ao menos um contato de confiança para continuar.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                )
              else
                SectionCard(
                  children: [
                    for (final contact in contacts)
                      SectionRow(
                        icon: Icons.person_outline,
                        title: contact.nome,
                        subtitle: contact.relacao,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remover contato',
                          onPressed: () => _confirmAndRemove(context, ref, contact.id, contact.nome),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              buscarProfissional,
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Não foi possível carregar seus contatos.')),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Adicionar contato'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () => _addContact(context, ref),
              ),
              const SizedBox(height: 8),
              contactsAsync.maybeWhen(
                data: (contacts) => contacts.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
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
      ),
    );
  }
}
